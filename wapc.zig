extern "wapc" fn __guest_request(operation_ptr: [*]u8, payload_ptr: [*]u8) void;
extern "wapc" fn __guest_response(ptr: [*]u8, len: usize) void;
extern "wapc" fn __guest_error(ptr: [*]u8, len: usize) void;

extern "wapc" fn __host_call(binding_ptr: [*]const u8, binding_len: usize, namespace_ptr: [*]const u8, namespace_len: usize, operation_ptr: [*]const u8, operation_len: usize, payload_ptr: [*]const u8, payload_len: usize) bool;
extern "wapc" fn __host_response_len() usize;
extern "wapc" fn __host_response(ptr: [*]u8) void;
extern "wapc" fn __host_error_len() usize;
extern "wapc" fn __host_error(ptr: [*]u8) void;

const std = @import("std");
const mem = std.mem;
const heap = std.heap;

pub const Function = struct {
    name: []const u8,
    invoke: fn (
        allocator: mem.Allocator,
        payload: []u8,
    ) anyerror!?[]u8,
};

fn guestError(allocator: mem.Allocator, err: anyerror) !void {
    var message = std.ArrayList(u8).init(allocator);
    defer message.deinit();
    try message.appendSlice("guest error: ");
    try message.appendSlice(@errorName(err));
    __guest_error(@ptrCast([*]u8, message.items), message.items.len);
}

fn functionNotFoundError(allocator: mem.Allocator, operation: []u8) !void {
    var message = std.ArrayList(u8).init(allocator);
    defer message.deinit();
    try message.appendSlice("Could not find function ");
    try message.appendSlice(operation);
    __guest_error(@ptrCast([*]u8, message.items), message.items.len);
}

pub fn handleCall(allocator: mem.Allocator, operation_size: usize, payload_size: usize, comptime fns: []const Function) bool {
    var operation_buf = allocator.alloc(u8, operation_size) catch return false;
    defer allocator.free(operation_buf);

    var payload_buf = allocator.alloc(u8, payload_size) catch return false;
    defer allocator.free(payload_buf);

    __guest_request(operation_buf.ptr, payload_buf.ptr);

    inline for (fns) |function| {
        if (mem.eql(u8, operation_buf, function.name)) {
            const response_maybe = function.invoke(allocator, payload_buf) catch |err| {
                guestError(allocator, err) catch return false;
                return false;
            };
            if (response_maybe) |response| {
                defer allocator.free(response);
                __guest_response(response.ptr, response.len);
            } else {
                __guest_response(@intToPtr([*]u8, 1), 0);
            }
            return true;
        }
    }

    functionNotFoundError(allocator, operation_buf) catch return false;
    return false;
}

pub fn hostCall(allocator: mem.Allocator, binding: []const u8, namespace: []const u8, operation: []const u8, payload: []const u8) ![]u8 {
    const result = __host_call(binding.ptr, binding.len, namespace.ptr, namespace.len, operation.ptr, operation.len, payload.ptr, payload.len);
    if (!result) {
        var message = std.ArrayList(u8).init(allocator);
        defer message.deinit();
        try message.appendSlice("Host error: ");
        // ask the host what happened
        const error_len = __host_error_len();
        const host_message = try allocator.alloc(u8, error_len);
        defer allocator.free(host_message);
        __host_error(host_message.ptr);
        try message.appendSlice(host_message);
        // echo back the host error from the guest
        __guest_error(@ptrCast([*]u8, message.items), message.items.len);
        return error.HostError;
    }

    const response_len = __host_response_len();
    const response = try allocator.alloc(u8, response_len);
    __host_response(response.ptr);

    return response;
}

extern "wapc" fn __guest_request(operation_ptr: [*]u8, payload_ptr: [*]u8) void;
extern "wapc" fn __guest_response(ptr: [*]u8, len: usize) void;
extern "wapc" fn __guest_error(ptr: [*]u8, len: usize) void;

extern "wapc" fn __host_call(binding_ptr: [*]u8, binding_len: usize, namespace_ptr: [*]u8, namespace_len: usize, operation_ptr: [*]u8, operation_len: usize, payload_ptr: [*]u8, payload_len: usize) bool;
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
    ) anyerror![]u8,
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
            const response = function.invoke(allocator, payload_buf) catch |err| {
                guestError(allocator, err) catch return false;
                return false;
            };
            __guest_response(response.ptr, response.len);
            return true;
        }
    }

    functionNotFoundError(allocator, operation_buf) catch return false;
    return false;
}

pub fn hostCall(allocator: mem.Allocator, binding: []u8, namespace: []u8, operation: []u8, payload: []u8) ![]u8 {
    const result = __host_call(binding.ptr, binding.len, namespace.ptr, namespace.len, operation.ptr, operation.len, payload.ptr, payload.len);
    if (!result) {
        const errorLen = __host_error_len();
        const errorPrefix = "Host error: ";
        const message = allocator.alloc(u8, errorPrefix.len + errorLen) catch return error.HostError;
        defer allocator.free(message);

        mem.copy(u8, message, &errorPrefix);
        __host_error(message.ptr + errorPrefix.len);
        __guest_error(message.ptr, message.len);

        return error.HostError;
    }

    const responseLen = __host_response_len();
    const response = try allocator.alloc(u8, responseLen);
    __host_response(response.ptr);

    return response;
}

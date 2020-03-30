extern "wapc" fn __guest_request(operation_ptr: [*]u8, payload_ptr: [*]u8) void;
extern "wapc" fn __guest_response(ptr: [*]u8, len: usize) void;
extern "wapc" fn __guest_error(ptr: [*]u8, len: usize) void;

extern "wapc" fn __host_call(binding_ptr: [*]u8, binding_len: usize, namespace_ptr: [*]u8, namespace_len: usize, operation_ptr: [*]u8, operation_len: usize, payload_ptr: [*]u8, payload_len: usize) bool;
extern "wapc" fn __host_response_len() usize;
extern "wapc" fn __host_response(ptr: [*]u8) void;
extern "wapc" fn __host_error_len() usize;
extern "wapc" fn __host_error(ptr: [*]u8) void;

extern fn __console_log(ptr: [*]u8, len: usize) void;

const std = @import("std");
const mem = std.mem;
const heap = std.heap;

pub const Function = struct {
    pub const Error = error{HostError,OutOfMemory};
    name: []u8,
    invoke: fn (
        allocator: *mem.Allocator,
        payload: []u8,
    ) Error![]u8,
};

pub fn handleCall(operation_size: usize, payload_size: usize, fns: []Function) bool {
    var sbuf: [1000]u8 = undefined;
    var allocator = &std.heap.FixedBufferAllocator.init(sbuf[0..]).allocator;

    var operation_buf = allocator.alloc(u8, operation_size) catch |err| return false;
    var payload_buf = allocator.alloc(u8, payload_size) catch |err| return false;
    __guest_request(operation_buf.ptr, payload_buf.ptr);

    for (fns) |function| {
        if (mem.eql(u8, operation_buf, function.name)) {
            const response = function.invoke(allocator, payload_buf) catch |err| return false;
            __guest_response(response.ptr, response.len);

            return true;
        }
    }

    const functionNotFound = "Could not find function ";
    const message = allocator.alloc(u8, functionNotFound.len + operation_buf.len) catch |err| return false;
    mem.copy(u8, message, &functionNotFound);
    mem.copy(u8, message[functionNotFound.len..], operation_buf);
    __guest_error(message.ptr, message.len);

    return false;
}

pub fn hostCall(allocator: *mem.Allocator, binding: []u8, namespace: []u8, operation: []u8, payload: []u8) ![]u8 {
    const result = __host_call(binding.ptr, binding.len, namespace.ptr, namespace.len, operation.ptr, operation.len, payload.ptr, payload.len);
    if (!result) {
        const errorLen = __host_error_len();
        const errorPrefix = "Host error: ";
        const message = allocator.alloc(u8, errorPrefix.len +errorLen) catch |err| return error.HostError;
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

# waPC Guest Library for Zig

This is the Zig implementation of the **waPC** standard for WebAssembly guest modules. It allows any waPC-compliant WebAssembly host to invoke to procedures inside a Zig compiled guest and similarly for the guest to invoke procedures exposed by the host.

## Example
The following is a simple example of synchronous, bi-directional procedure calls between a WebAssembly host runtime and the guest module.

`hello.zig` (copy `wapc.zig` into the same directory)

```zig
const wapc = @import("wapc.zig");
const std = @import("std");
const mem = std.mem;

export fn __guest_call(operation_size: usize, payload_size: usize) bool {
    return wapc.handleCall(operation_size, payload_size, &functions);
}

var functions = [_]wapc.Function{
    wapc.Function{.name = &"hello", .invoke = sayHello},
};

fn sayHello(allocator: *mem.Allocator, payload: []u8) ![]u8 {
    const hostHello = try wapc.hostCall(allocator, &"myBinding", &"sample", &"hello", &"Simon");
    const prefix = "Hello, ";
    const message = try allocator.alloc(u8, prefix.len + payload.len + hostHello.len + 1);
    mem.copy(u8, message, &prefix);
    mem.copy(u8, message[prefix.len..], payload);
    mem.copy(u8, message[prefix.len+payload.len..], hostHello);
    message[message.len-1] = '!';
    return message;
}
```

```sh
zig build-lib hello.zig -target wasm32-freestanding
```
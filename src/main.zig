const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();
    //
    while (true) {
        const connection = try listener.accept();
        try stdout.print("client connected!", .{});

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        var allocator = gpa.allocator();

        var httpv1 = Response.init(allocator);
        defer httpv1.deinit();

        const requestBuf = allocator.alloc(u8, 1024) catch unreachable;
        defer allocator.free(requestBuf);
        _ = try connection.stream.read(requestBuf);
        var request = Request.init(allocator);
        try request.parse(requestBuf);
        defer request.deinit();

        request.debugPrint();
        try router.handleRoutes(allocator, connection, request);

        connection.stream.close();
    }
}

const Response = @import("./http/response.zig").Response;
const Request = @import("./http/request.zig").Request;
const mem = std.mem;
const router = @import("./router.zig");

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

        const requestBuf = allocator.alloc(u8, 1024) catch unreachable;
        defer allocator.free(requestBuf);
        _ = try connection.stream.read(requestBuf);
        var request = Request.init(allocator);
        try request.parse(requestBuf);
        defer request.deinit();

        request.debugPrint();

        if (mem.eql(u8, request.path, "/")) {
            const httpResponse = try httpv1.setStatusCode("200").setStatusMessage("OK").build();
            defer allocator.free(httpResponse);
            try connection.stream.writeAll(httpResponse);
        } else if (mem.startsWith(u8, request.path, "/echo/")) {
            const str = request.path[6..];
            const httpResponse = try httpv1.setStatusCode("200").setStatusMessage("OK").setBody(str).addHeader("Content-Type", "text/plain").build();
            defer allocator.free(httpResponse);
            try connection.stream.writeAll(httpResponse);
        } else {
            const httpResponse = try httpv1.setStatusCode("404").setStatusMessage("Not Found").build();
            defer allocator.free(httpResponse);
            try connection.stream.writeAll(httpResponse);
        }
        connection.stream.close();
    }
}

const Response = @import("./http/response.zig").Response;
const Request = @import("./http/request.zig").Request;
const mem = std.mem;

const std = @import("std");
const mem = std.mem;
const Connection = std.net.Server.Connection;

const Request = @import("./http/request.zig").Request;
const Response = @import("./http/response.zig").Response;

pub fn handleRoutes(allocator: mem.Allocator, connection: Connection, request: Request) !void {
    var response = Response.init(allocator);
    defer response.deinit();

    if (mem.eql(u8, request.path, "/")) {
        const httpResponse = try response.setStatusCode("200").setStatusMessage("OK").build();
        defer allocator.free(httpResponse);
        try connection.stream.writeAll(httpResponse);
    } else if (mem.startsWith(u8, request.path, "/echo/")) {
        const str = request.path[6..];
        const httpResponse = try response
            .setStatusCode("200")
            .setStatusMessage("OK")
            .setBody(str)
            .addHeader("Content-Type", "text/plain")
            .build();
        defer allocator.free(httpResponse);
        try connection.stream.writeAll(httpResponse);
    } else if (mem.startsWith(u8, request.path, "/user-agent")) {
        const userAgent = request.getHeader("User-Agent") orelse "Unknown User-Agent";
        const httpResponse = try response
            .setStatusCode("200")
            .setStatusMessage("OK")
            .setBody(userAgent)
            .addHeader("Content-Type", "text/plain")
            .build();
        defer allocator.free(httpResponse);
        try connection.stream.writeAll(httpResponse);
    } else {
        const httpResponse = try response.setStatusCode("404").setStatusMessage("Not Found").build();
        defer allocator.free(httpResponse);
        try connection.stream.writeAll(httpResponse);
    }
}

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
    } else if (mem.startsWith(u8, request.path, "/files/")) {
        const fileName = request.path[7..];
        var it = std.process.args();
        _ = it.next(); // skip the first argument (the program name)
        // skip the second argument (the file path)
        _ = it.next();
        const dirPath = it.next().?;
        const fullPath = std.fs.path.join(allocator, &.{ dirPath, fileName }) catch unreachable;
        defer allocator.free(fullPath);

        switch (request.method) {
            .GET => {
                const file = std.fs.cwd().openFile(fullPath, .{}) catch {
                    const httpResponse = try response
                        .setStatusCode("404")
                        .setStatusMessage("Not Found")
                        .build();
                    defer allocator.free(httpResponse);
                    try connection.stream.writeAll(httpResponse);
                    return;
                };
                defer file.close();

                const fileSize = try file.getEndPos();
                const body = try file.readToEndAlloc(allocator, fileSize);
                defer allocator.free(body);
                const httpResponse = try response
                    .setStatusCode("200")
                    .setStatusMessage("OK")
                    .setBody(body)
                    .addHeader("Content-Type", "application/octet-stream")
                    .build();
                defer allocator.free(httpResponse);
                try connection.stream.writeAll(httpResponse);
            },
            .POST => {
                const newFile = try std.fs.cwd().createFile(fullPath, .{});
                defer newFile.close();

                const body = request.body.?;
                try newFile.writeAll(body);

                const httpResponse = try response
                    .setStatusCode("201")
                    .setStatusMessage("Created")
                    .build();

                defer allocator.free(httpResponse);
                try connection.stream.writeAll(httpResponse);
            },
            else => return error.InvalidMethod,
        }
    } else {
        const httpResponse = try response.setStatusCode("404").setStatusMessage("Not Found").build();
        defer allocator.free(httpResponse);
        try connection.stream.writeAll(httpResponse);
    }
}

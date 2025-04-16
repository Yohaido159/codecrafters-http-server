const Request = @import("./request.zig").Request;

pub const Response = struct {
    httpVersion: []const u8,
    statusCode: []const u8,
    statusMessage: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: mem.Allocator,
    request: Request,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, request: Request) Self {
        return Self{
            .httpVersion = "HTTP/1.1",
            .statusCode = undefined,
            .statusMessage = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
            .request = request,
        };
    }
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    pub fn setStatusCode(self: *Self, statusCode: []const u8) *Self {
        self.statusCode = statusCode;
        return self;
    }

    pub fn setStatusMessage(self: *Self, statusMessage: []const u8) *Self {
        self.statusMessage = statusMessage;
        return self;
    }

    pub fn addHeader(self: *Self, name: []const u8, value: []const u8) *Self {
        self.headers.put(name, value) catch unreachable;
        return self;
    }

    pub fn setBody(self: *Self, body: []const u8) *Self {
        self.body = body;
        return self;
    }

    pub fn build(self: *Self) []const u8 {
        var result = ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        if (self.request.getHeader("Accept-Encoding")) |accept_encoding| {
            if (mem.eql(u8, accept_encoding, "gzip")) {
                _ = self.addHeader("Content-Encoding", "gzip");
            }
        }
        //
        // Status line
        result.appendSlice(self.httpVersion) catch unreachable;
        result.appendSlice(" ") catch unreachable;
        result.appendSlice(self.statusCode) catch unreachable;
        result.appendSlice(" ") catch unreachable;
        result.appendSlice(self.statusMessage) catch unreachable;
        result.appendSlice("\r\n") catch unreachable;
        var headers_iterator = self.headers.iterator();

        while (headers_iterator.next()) |entry| {
            result.appendSlice(entry.key_ptr.*) catch unreachable;
            result.appendSlice(": ") catch unreachable;
            result.appendSlice(entry.value_ptr.*) catch unreachable;
            result.appendSlice("\r\n") catch unreachable;
        }

        if (self.body) |body| {
            const content_length = std.fmt.allocPrint(self.allocator, "{d}", .{body.len}) catch unreachable;
            defer self.allocator.free(content_length);
            result.appendSlice("Content-Length: ") catch unreachable;
            result.appendSlice(content_length) catch unreachable;
            result.appendSlice("\r\n") catch unreachable;
        }
        // Empty line separating headers from body
        result.appendSlice("\r\n") catch unreachable;

        // Body
        if (self.body) |body| {
            result.appendSlice(body) catch unreachable;
        }
        return result.toOwnedSlice() catch unreachable;
    }
};

const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

test "simple response" {
    const allocator = std.testing.allocator;
    var http = Response.init(allocator);

    const result = http.setStatusCode("200")
        .setStatusMessage("OK")
        .build();

    defer allocator.free(result);

    const expected = "HTTP/1.1 200 OK\r\n\r\n";
    try std.testing.expectEqualSlices(u8, result, expected);
}

test "response with headers" {
    const allocator = std.testing.allocator;
    var response = Response.init(allocator);
    defer response.deinit();

    const result = response
        .setStatusCode("404")
        .setStatusMessage("Not Found")
        .addHeader("Content-Type", "text/html")
        .addHeader("Server", "Zig HTTP Server")
        .build();
    defer allocator.free(result);

    // Note: Headers may appear in any order when iterating a hash map
    // For a proper test, we would need to parse and check each header separately
    // This is a simplified check
    try std.testing.expect(mem.indexOf(u8, result, "HTTP/1.1 404 Not Found\r\n") != null);
    try std.testing.expect(mem.indexOf(u8, result, "Content-Type: text/html\r\n") != null);
    try std.testing.expect(mem.indexOf(u8, result, "Server: Zig HTTP Server\r\n") != null);
    try std.testing.expect(mem.endsWith(u8, result, "\r\n\r\n"));
}

test "response with body" {
    const allocator = std.testing.allocator;
    var response = Response.init(allocator);
    defer response.deinit();

    const body = "<!DOCTYPE html><html><body><h1>Hello, World!</h1></body></html>";
    const result = try response
        .setStatusCode("200")
        .setStatusMessage("OK")
        .addHeader("Content-Type", "text/html")
        .setBody(body)
        .build();
    defer allocator.free(result);

    try std.testing.expect(mem.indexOf(u8, result, "HTTP/1.1 200 OK\r\n") != null);
    try std.testing.expect(mem.indexOf(u8, result, "Content-Type: text/html\r\n") != null);
    try std.testing.expect(mem.indexOf(u8, result, "Content-Length: 63\r\n") != null);
    try std.testing.expect(mem.indexOf(u8, result, body) != null);
}

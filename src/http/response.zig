pub const Response = struct {
    httpVersion: []const u8,
    statusCode: []const u8,
    statusMessage: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: mem.Allocator,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .httpVersion = "HTTP/1.1",
            .statusCode = undefined,
            .statusMessage = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
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

    pub fn build(self: *Self) ![]const u8 {
        var result = ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Status line
        try result.appendSlice(self.httpVersion);
        try result.appendSlice(" ");
        try result.appendSlice(self.statusCode);
        try result.appendSlice(" ");
        try result.appendSlice(self.statusMessage);
        try result.appendSlice("\r\n");
        var headers_iterator = self.headers.iterator();

        while (headers_iterator.next()) |entry| {
            try result.appendSlice(entry.key_ptr.*);
            try result.appendSlice(": ");
            try result.appendSlice(entry.value_ptr.*);
            try result.appendSlice("\r\n");
        }
        if (self.body) |body| {
            const content_length = try std.fmt.allocPrint(self.allocator, "{d}", .{body.len});
            defer self.allocator.free(content_length);
            try result.appendSlice("Content-Length: ");
            try result.appendSlice(content_length);
            try result.appendSlice("\r\n");
        }
        // Empty line separating headers from body
        try result.appendSlice("\r\n");

        // Body
        if (self.body) |body| {
            try result.appendSlice(body);
        }
        return result.toOwnedSlice();
    }
};

const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

test "simple response" {
    const allocator = std.testing.allocator;
    var http = Response.init(allocator);

    const result = try http.setStatusCode("200")
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

    const result = try response
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

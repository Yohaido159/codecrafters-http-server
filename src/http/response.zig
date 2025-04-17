const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

const compression = @import("../compression.zig");
const Compressor = compression.Compressor;
const CompressionType = compression.CompressionType;

const Request = @import("./request.zig").Request;

pub const Response = struct {
    httpVersion: []const u8,
    statusCode: []const u8,
    statusMessage: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: mem.Allocator,
    request: Request,
    compression_type: CompressionType,
    compressor: Compressor,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, request: Request) Self {
        var self = Self{
            .httpVersion = "HTTP/1.1",
            .statusCode = undefined,
            .statusMessage = undefined,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
            .request = request,
            .compression_type = .None,
            .compressor = Compressor.init(allocator),
        };

        self.compression_type = self.negotiateCompression();
        if (self.compression_type != .None) {
            _ = self.addHeader("Content-Encoding", self.compression_type.toString());
        }

        if (request.getHeader("Connection")) |connection_header| {
            if (std.ascii.eqlIgnoreCase(connection_header.single, "close")) {
                _ = self.addHeader("Connection", "close");
            }
        }

        return self;
    }
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }

    fn negotiateCompression(self: *Self) CompressionType {
        if (self.request.getHeader("Accept-Encoding")) |accept_encoding| {
            // Handle the existing HeaderValue API (single or multiple)
            switch (accept_encoding) {
                .single => {
                    if (CompressionType.fromString(accept_encoding.single)) |compression_type| {
                        return compression_type;
                    }
                },
                .multiple => {
                    // Check each encoding type in the array
                    for (accept_encoding.multiple.items) |encoding| {
                        if (CompressionType.fromString(encoding)) |compression_type| {
                            return compression_type;
                        }
                    }
                },
            }
        }
        return .None;
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
        if (self.compression_type != .None) {
            const compressed_body = self.compressor.compress(body, self.compression_type) catch |err| {
                std.log.err("Compression failed: {}", .{err});
                self.compression_type = .None;
                _ = self.headers.remove("Content-Encoding");
                self.body = body;
                return self;
            };

            self.body = compressed_body;
        } else {
            self.body = body;
        }

        if (self.body) |response_body| {
            const length = std.fmt.allocPrint(self.allocator, "{d}", .{response_body.len}) catch unreachable;
            _ = self.addHeader("Content-Length", length);
        }

        return self;
    }

    pub fn build(self: *Self) []const u8 {
        var result = ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

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

        result.appendSlice("\r\n") catch unreachable;

        if (self.body) |body| {
            result.appendSlice(body) catch unreachable;
        }
        return result.toOwnedSlice() catch unreachable;
    }
};

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

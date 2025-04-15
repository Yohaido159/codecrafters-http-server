const std = @import("std");
const mem = std.mem;

pub const Httpv1 = struct {
    method: []const u8,
    path: []const u8,
    httpVersion: []const u8,
    statusCode: []const u8,
    statusMessage: []const u8,

    // allocator: mem.Allocator,

    const Self = @This();

    pub fn init() Self {
        return Httpv1{
            // .allocator = allocator,
            .method = undefined,
            .path = undefined,
            .httpVersion = "HTTP/1.1",
            .statusCode = undefined,
            .statusMessage = undefined,
        };
    }

    pub fn setMethod(self: *Self, method: []const u8) *Self {
        self.method = method;
        return self;
    }

    pub fn setPath(self: *Self, path: []const u8) *Self {
        self.path = path;
        return self;
    }

    pub fn setStatusCode(self: *Self, statusCode: []const u8) *Self {
        self.statusCode = statusCode;
        return self;
    }

    pub fn setStatusMessage(self: *Self, statusMessage: []const u8) *Self {
        self.statusMessage = statusMessage;
        return self;
    }

    pub fn build(self: *Self, allocator: mem.Allocator) []const u8 {
        const httpRequest = mem.concat(allocator, u8, &.{
            // self.method,
            // " ",
            // self.path,
            // " ",
            self.httpVersion,
            " ",
            self.statusCode,
            " ",
            self.statusMessage,
            "\r\n",
            "\r\n",
        }) catch unreachable;

        return httpRequest;
    }
};

test "should build simple http" {
    const allocator = std.testing.allocator;
    var http = Httpv1.init();

    const result = http.setMethod("GET")
        .setPath("/index.html")
        .setStatusCode("200")
        .setStatusMessage("OK")
        .build(allocator);

    defer allocator.free(result);

    const expected = "GET /index.html HTTP/1.1 200 OK\r\n\r\n";
    try std.testing.expectEqualSlices(u8, result, expected);
}

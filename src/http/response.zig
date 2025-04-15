const std = @import("std");
const mem = std.mem;

pub const Response = struct {
    httpVersion: []const u8,
    statusCode: []const u8,
    statusMessage: []const u8,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .httpVersion = "HTTP/1.1",
            .statusCode = undefined,
            .statusMessage = undefined,
        };
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
        const httpResponse = mem.concat(allocator, u8, &.{
            self.httpVersion,
            " ",
            self.statusCode,
            " ",
            self.statusMessage,
            "\r\n",
            "\r\n",
        }) catch unreachable;

        return httpResponse;
    }
};

test "simple response" {
    const allocator = std.testing.allocator;
    var http = Response.init();

    const result = http.setMethod("GET")
        .setStatusCode("200")
        .setStatusMessage("OK")
        .build(allocator);

    defer allocator.free(result);

    const expected = "GET /index.html HTTP/1.1 200 OK\r\n\r\n";
    try std.testing.expectEqualSlices(u8, result, expected);
}

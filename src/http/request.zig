const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const HttpError = @import("./http.zig").HttpError;

pub const Request = struct {
    allocator: mem.Allocator,
    method: HttpMethod,
    path: []const u8,
    query_string: ?[]const u8,
    version: []const u8,
    headers: std.ArrayList(HttpHeader),
    body: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Request{
            .allocator = allocator,
            .method = .UNKNOWN,
            .path = "",
            .query_string = null,
            .version = "",
            .headers = std.ArrayList(HttpHeader).init(allocator),
            .body = null,
        };
    }
    pub fn deinit(self: *Self) void {
        for (self.headers.items) |*header| {
            header.deinit();
        }
        self.headers.deinit();
    }

    pub fn parse(self: *Self, request_data: []const u8) !void {
        var lines = mem.splitSequence(u8, request_data, "\r\n");
        const request_line = lines.next() orelse return error.InvalidRequest;
        try self.parseRequestLine(request_line);

        var maybe_header_line = lines.next();
        while (maybe_header_line) |header_line| {
            if (header_line.len == 0) break; // Empty line indicates end of headers
            try self.parseHeader(header_line);
            maybe_header_line = lines.next();
        }

        var body_start = if (mem.indexOf(u8, request_data, "\r\n\r\n")) |idx| idx + 4 else null;

        // for the test cases that failed
        if (body_start == null) {
            body_start = if (mem.indexOf(u8, request_data, "\n\n")) |idx| idx + 2 else null;
        }

        const contentLength = self.getContentLength();

        if (body_start) |start| {
            if (contentLength) |len| {
                if (start < request_data.len) {
                    const end = start + len;
                    self.body = request_data[start..end];
                }
            }
        }
    }

    fn parseRequestLine(self: *Self, line: []const u8) !void {
        var parts = mem.splitAny(u8, line, " ");

        const method_str = parts.next() orelse return error.InvalidRequestLine;
        self.method = HttpMethod.fromString(method_str);

        const path_full = parts.next() orelse return error.InvalidRequestLine;
        if (mem.indexOf(u8, path_full, "?")) |idx| {
            self.path = path_full[0..idx];
            self.query_string = path_full[idx + 1 ..];
        } else {
            self.path = path_full;
        }

        self.version = parts.next() orelse return error.InvalidRequestLine;
    }

    fn parseHeader(self: *Self, line: []const u8) !void {
        const separator_idx = mem.indexOf(u8, line, ":") orelse return error.InvalidHeader;

        const name = mem.trim(u8, line[0..separator_idx], " ");
        const raw_value = mem.trim(u8, line[separator_idx + 1 ..], " ");

        if (mem.indexOf(u8, raw_value, ",") != null) {
            var values = std.ArrayList([]const u8).init(self.allocator);
            errdefer values.deinit();

            var value_iter = mem.splitAny(u8, raw_value, ",");
            while (value_iter.next()) |val| {
                const trimmed_val = mem.trim(u8, val, " ");
                try values.append(trimmed_val);
            }
            try self.headers.append(HttpHeader{
                .name = name,
                .value = HeaderValue{ .multiple = values },
            });
        } else {
            // Add header with single value
            try self.headers.append(HttpHeader{
                .name = name,
                .value = HeaderValue{ .single = raw_value },
            });
        }
    }

    pub fn getHeader(self: Self, name: []const u8) ?HeaderValue {
        for (self.headers.items) |header| {
            if (mem.eql(u8, header.name, name)) {
                return header.value;
            }
        }
        return null;
    }

    pub fn getContentType(self: Self) ?[]const u8 {
        return self.getHeader("Content-Type").?.single;
    }

    pub fn getContentLength(self: Self) ?usize {
        const content_length_str = self.getHeader("Content-Length") orelse return null;
        return std.fmt.parseInt(usize, content_length_str.single, 10) catch null;
    }

    pub fn debugPrint(self: Self) void {
        const stdout = std.io.getStdOut().writer();

        // Print method and path
        stdout.print("\n=== HTTP Request ===\n", .{}) catch {};
        stdout.print("Method: {s}\n", .{@tagName(self.method)}) catch {};
        stdout.print("Path: {s}\n", .{self.path}) catch {};

        // Print query string if present
        if (self.query_string) |query| {
            stdout.print("Query: {s}\n", .{query}) catch {};
        }

        stdout.print("HTTP Version: {s}\n", .{self.version}) catch {};

        // Print headers
        stdout.print("\n--- Headers ({d}) ---\n", .{self.headers.items.len}) catch {};
        for (self.headers.items) |header| {
            switch (header.value) {
                .single => |value| {
                    stdout.print("{s}: {s}\n", .{ header.name, value }) catch {};
                },
                .multiple => |list| {
                    stdout.print("{s}: [", .{header.name}) catch {};
                    for (list.items, 0..) |value, i| {
                        if (i > 0) stdout.print(", ", .{}) catch {};
                        stdout.print("{s}", .{value}) catch {};
                    }
                    stdout.print("]\n", .{}) catch {};
                },
            }
        }

        // Print body if present
        if (self.body) |body| {
            stdout.print("\n--- Body ({d} bytes) ---\n{s}\n", .{ body.len, body }) catch {};
        } else {
            stdout.print("\n--- No Body ---\n", .{}) catch {};
        }

        stdout.print("====================\n", .{}) catch {};
    }
};

pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    UNKNOWN,

    pub fn fromString(method: []const u8) HttpMethod {
        if (mem.eql(u8, method, "GET")) return .GET;
        if (mem.eql(u8, method, "POST")) return .POST;
        if (mem.eql(u8, method, "PUT")) return .PUT;
        if (mem.eql(u8, method, "DELETE")) return .DELETE;
        if (mem.eql(u8, method, "HEAD")) return .HEAD;
        if (mem.eql(u8, method, "OPTIONS")) return .OPTIONS;
        if (mem.eql(u8, method, "PATCH")) return .PATCH;
        return .UNKNOWN;
    }
};

pub const HttpHeader = struct {
    name: []const u8,
    value: HeaderValue,

    pub fn deinit(self: *HttpHeader) void {
        self.value.deinit();
    }
};

pub const HeaderValue = union(enum) {
    single: []const u8,
    multiple: std.ArrayList([]const u8),

    pub fn deinit(self: *HeaderValue) void {
        switch (self.*) {
            .single => {}, // No need to free single value as it points to request data
            .multiple => |*list| {
                // We don't free individual strings as they point to request data
                list.deinit();
            },
        }
    }
};

test "parse HTTP request" {
    const request_str =
        \\GET /path/to/resource?param1=value1&param2=value2 HTTP/1.1
        \\Host: example.com
        \\User-Agent: Mozilla/5.0
        \\Accept: text/html
        \\
        \\Some request body content
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();

    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.GET, req.method);
    try testing.expectEqualStrings("/path/to/resource", req.path);
    try testing.expectEqualStrings("param1=value1&param2=value2", req.query_string.?);
    try testing.expectEqualStrings("HTTP/1.1", req.version);
    try testing.expectEqualStrings("example.com", req.getHeader("Host").?.single);
    try testing.expectEqualStrings("Mozilla/5.0", req.getHeader("User-Agent").?.single);
    try testing.expectEqualStrings("text/html", req.getHeader("Accept").?.single);
    try testing.expectEqualStrings("Some request body content", req.body.?);
}

test "parse HTTP GET request" {
    const request_str =
        \\GET /index.html HTTP/1.1
        \\Host: example.com
        \\
        \\
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.GET, req.method);
    try testing.expectEqualStrings("/index.html", req.path);
}

test "parse HTTP POST request" {
    const request_str =
        \\POST /submit-form HTTP/1.1
        \\Host: example.com
        \\Content-Type: application/x-www-form-urlencoded
        \\Content-Length: 27
        \\
        \\username=john&password=secret
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.POST, req.method);
    try testing.expectEqualStrings("/submit-form", req.path);
    try testing.expectEqualStrings("application/x-www-form-urlencoded", req.getHeader("Content-Type").?.single);
    try testing.expectEqualStrings("27", req.getHeader("Content-Length").?.single);
    try testing.expectEqualStrings("username=john&password=secret", req.body.?);
}

test "parse HTTP PUT request" {
    const request_str =
        \\PUT /api/resources/123 HTTP/1.1
        \\Host: api.example.com
        \\Content-Type: application/json
        \\Content-Length: 25
        \\
        \\{"name":"Updated Item"}
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.PUT, req.method);
    try testing.expectEqualStrings("/api/resources/123", req.path);
    try testing.expectEqualStrings("application/json", req.getHeader("Content-Type").?.single);
    try testing.expectEqualStrings("{\"name\":\"Updated Item\"}", req.body.?);
}

test "parse HTTP DELETE request" {
    const request_str =
        \\DELETE /api/resources/123 HTTP/1.1
        \\Host: api.example.com
        \\
        \\
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.DELETE, req.method);
    try testing.expectEqualStrings("/api/resources/123", req.path);
}

test "parse HTTP PATCH request" {
    const request_str =
        \\PATCH /api/resources/123 HTTP/1.1
        \\Host: api.example.com
        \\Content-Type: application/json
        \\Content-Length: 28
        \\
        \\{"status":"in_progress"}
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.PATCH, req.method);
    try testing.expectEqualStrings("/api/resources/123", req.path);
    try testing.expectEqualStrings("application/json", req.getHeader("Content-Type").?.single);
    try testing.expectEqualStrings("{\"status\":\"in_progress\"}", req.body.?);
}

test "parse HTTP HEAD request" {
    const request_str =
        \\HEAD /index.html HTTP/1.1
        \\Host: example.com
        \\
        \\
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.HEAD, req.method);
    try testing.expectEqualStrings("/index.html", req.path);
}

test "parse HTTP OPTIONS request" {
    const request_str =
        \\OPTIONS * HTTP/1.1
        \\Host: example.com
        \\
        \\
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.OPTIONS, req.method);
    try testing.expectEqualStrings("*", req.path);
}

test "parse unknown HTTP method" {
    const request_str =
        \\CONNECT example.com:443 HTTP/1.1
        \\Host: example.com
        \\
        \\
    ;

    var req = Request.init(testing.allocator);
    defer req.deinit();
    try req.parse(request_str);

    try testing.expectEqual(HttpMethod.UNKNOWN, req.method);
    try testing.expectEqualStrings("example.com:443", req.path);
}

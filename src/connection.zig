const std = @import("std");
const net = std.net;
const log = std.log;

const http = @import("./http/http.zig");
const Request = http.Request;
const Response = http.Response;

const router = @import("./router.zig");

pub const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: net.Server.Connection,
    directory: ?[]const u8,
};

pub fn handleConnection(context: *ConnectionContext) void {
    const connection = context.connection;

    defer {
        connection.stream.close();
        context.allocator.destroy(context);
    }

    // Initialize per-connection arena allocator

    while (true) {
        var arena = std.heap.ArenaAllocator.init(context.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        // Read and parse the HTTP request
        const request_buf = arena_allocator.alloc(u8, 8192) catch |err| {
            log.err("Failed to allocate request buffer: {}", .{err});
            break;
        };

        const bytes_read = connection.stream.read(request_buf) catch |err| {
            log.err("Error reading from connection: {}", .{err});
            break;
        };

        if (bytes_read == 0) {
            log.info("Client disconnected without sending data", .{});
            break;
        }

        var request = Request.init(arena_allocator);
        request.parse(request_buf[0..bytes_read]) catch |err| {
            log.err("Failed to parse request: {}", .{err});
            sendErrorResponse(arena_allocator, connection, 400, "Bad Request", request) catch {};
            break;
        };

        // Log request information
        log.info("[{s}] {s} {s}", .{ @tagName(request.method), request.path, request.version });

        // Route and handle the request
        router.handleRequest(arena_allocator, connection, request, context.directory) catch |err| {
            log.err("Error handling request: {}", .{err});

            const status_code: u16 = switch (err) {
                error.NotFound => 404,
                error.InvalidMethod => 405,
                error.PayloadTooLarge => 413,
                error.Forbidden => 403,
                else => 500,
            };

            const status_message = switch (err) {
                error.NotFound => "Not Found",
                error.InvalidMethod => "Method Not Allowed",
                error.PayloadTooLarge => "Payload Too Large",
                error.Forbidden => "Forbidden",
                else => "Internal Server Error",
            };

            sendErrorResponse(arena_allocator, connection, status_code, status_message, request) catch {};
        };

        const connHdr = request.getHeader("Connection");
        if (connHdr) |conn| {
            if (std.ascii.eqlIgnoreCase(conn.single, "close")) {
                break;
            }
        }
    }
}

fn sendErrorResponse(allocator: std.mem.Allocator, connection: net.Server.Connection, status_code: u16, status_message: []const u8, request: Request) !void {
    var response = Response.init(allocator, request);

    const code = try std.fmt.allocPrint(allocator, "{d}", .{status_code});
    defer allocator.free(code);

    const http_response = response
        .setStatusCode(code)
        .setStatusMessage(status_message)
        .build();

    _ = try connection.stream.writeAll(http_response);
}

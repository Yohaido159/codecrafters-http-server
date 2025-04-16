const std = @import("std");
const net = std.net;
const log = std.log;

const http = @import("./http/http.zig");
const Request = http.Request;
const Response = http.Response;

const router = @import("./router.zig");

// Context structure passed to worker threads
pub const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: net.Server.Connection,
    directory: ?[]const u8,
};

// Worker function to handle HTTP connections
pub fn handleConnection(context: *ConnectionContext) void {
    defer context.allocator.destroy(context);

    const connection = context.connection;
    defer connection.stream.close();

    // Initialize per-connection arena allocator
    var arena = std.heap.ArenaAllocator.init(context.allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Read and parse the HTTP request
    const request_buf = arena_allocator.alloc(u8, 8192) catch |err| {
        log.err("Failed to allocate request buffer: {}", .{err});
        return;
    };

    const bytes_read = connection.stream.read(request_buf) catch |err| {
        log.err("Error reading from connection: {}", .{err});
        return;
    };

    if (bytes_read == 0) {
        log.info("Client disconnected without sending data", .{});
        return;
    }

    var request = Request.init(arena_allocator);
    request.parse(request_buf[0..bytes_read]) catch |err| {
        log.err("Failed to parse request: {}", .{err});
        sendErrorResponse(arena_allocator, connection, 400, "Bad Request") catch {};
        return;
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

        sendErrorResponse(arena_allocator, connection, status_code, status_message) catch {};
    };
}

fn sendErrorResponse(allocator: std.mem.Allocator, connection: net.Server.Connection, status_code: u16, status_message: []const u8) !void {
    var response = Response.init(allocator);

    const code = try std.fmt.allocPrint(allocator, "{d}", .{status_code});
    defer allocator.free(code);

    const http_response = response
        .setStatusCode(code)
        .setStatusMessage(status_message)
        .build();

    _ = try connection.stream.writeAll(http_response);
}

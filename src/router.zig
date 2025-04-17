const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const log = std.log;
const net = std.net;
const Connection = net.Server.Connection;

const http = @import("./http/http.zig");
const Request = http.Request;
const Response = http.Response;
const HttpStatus = http.HttpStatus;
const HttpMethod = http.HttpMethod;
const HttpError = http.HttpError;
const HeaderValue = http.HeaderValue;

pub fn handleRequest(allocator: mem.Allocator, connection: Connection, request: Request, directory: ?[]const u8) HttpError!void {
    log.debug("Processing request for path: {s}", .{request.path});
    request.debugPrint();

    if (mem.eql(u8, request.path, "/")) {
        try handleRoot(allocator, connection, request);
    } else if (mem.startsWith(u8, request.path, "/echo/")) {
        try handleEcho(allocator, connection, request);
    } else if (mem.eql(u8, request.path, "/user-agent")) {
        try handleUserAgent(allocator, connection, request);
    } else if (mem.startsWith(u8, request.path, "/files/")) {
        try handleFiles(allocator, connection, request, directory);
    } else {
        return HttpError.NotFound;
    }
}

fn handleRoot(allocator: mem.Allocator, connection: Connection, request: Request) HttpError!void {
    var response = Response.init(allocator, request);
    defer response.deinit();

    const http_response = response
        .setStatusCode(HttpStatus.OK)
        .setStatusMessage(HttpStatus.getMessage(HttpStatus.OK))
        .build();
    defer allocator.free(http_response);

    connection.stream.writeAll(http_response) catch {
        return HttpError.InternalServerError;
    };
}

fn handleEcho(allocator: mem.Allocator, connection: Connection, request: Request) HttpError!void {
    var response = Response.init(allocator, request);
    defer response.deinit();

    const content = request.path[6..]; // Extract content after "/echo/"

    const http_response = response
        .setStatusCode(HttpStatus.OK)
        .setStatusMessage(HttpStatus.getMessage(HttpStatus.OK))
        .setBody(content)
        .addHeader("Content-Type", "text/plain")
        .build();
    defer allocator.free(http_response);

    connection.stream.writeAll(http_response) catch {
        return HttpError.InternalServerError;
    };
}

// Handler for the user-agent endpoint
fn handleUserAgent(allocator: mem.Allocator, connection: Connection, request: Request) HttpError!void {
    var response = Response.init(allocator, request);
    defer response.deinit();

    const user_agent = request.getHeader("User-Agent") orelse HeaderValue{ .single = "Unknown User-Agent" };

    const http_response = response
        .setStatusCode(HttpStatus.OK)
        .setStatusMessage(HttpStatus.getMessage(HttpStatus.OK))
        .setBody(user_agent.single)
        .addHeader("Content-Type", "text/plain")
        .build();
    defer allocator.free(http_response);

    connection.stream.writeAll(http_response) catch {
        return HttpError.InternalServerError;
    };
}

// Handler for the files endpoint (/files/*)
fn handleFiles(allocator: mem.Allocator, connection: Connection, request: Request, directory: ?[]const u8) HttpError!void {
    // Ensure directory was provided
    const dir_path = directory orelse {
        log.err("Directory path not provided for file operations", .{});
        return HttpError.InternalServerError;
    };

    const file_name = request.path[7..]; // Extract filename after "/files/"

    // Validate filename to prevent directory traversal attacks
    if (containsDirectoryTraversal(file_name)) {
        log.warn("Attempted path traversal detected: {s}", .{file_name});
        return HttpError.Forbidden;
    }

    const full_path = fs.path.join(allocator, &.{ dir_path, file_name }) catch {
        return HttpError.InternalServerError;
    };
    defer allocator.free(full_path);

    log.debug("File operation on: {s}", .{full_path});

    switch (request.method) {
        .GET => try handleFileGet(allocator, connection, full_path, request),
        .POST => try handleFilePost(allocator, connection, request, full_path),
        else => return HttpError.InvalidMethod,
    }
}

// Handle GET requests for files
fn handleFileGet(allocator: mem.Allocator, connection: Connection, path: []const u8, request: Request) HttpError!void {
    var response = Response.init(allocator, request);
    defer response.deinit();

    // Try to open the file
    const file = fs.cwd().openFile(path, .{}) catch {
        return HttpError.NotFound;
    };
    defer file.close();

    // Get file size for proper allocation
    const file_size = file.getEndPos() catch {
        return HttpError.InternalServerError;
    };

    if (file_size > 100 * 1024 * 1024) { // 100MB limit
        return HttpError.PayloadTooLarge;
    }

    // Read file contents
    const body = file.readToEndAlloc(allocator, file_size) catch {
        return HttpError.InternalServerError;
    };

    defer allocator.free(body);

    // Determine content type based on file extension
    const content_type = getContentType(path);

    // Build and send response
    const http_response = response
        .setStatusCode(HttpStatus.OK)
        .setStatusMessage(HttpStatus.getMessage(HttpStatus.OK))
        .setBody(body)
        .addHeader("Content-Type", content_type)
        .build();
    defer allocator.free(http_response);

    connection.stream.writeAll(http_response) catch unreachable;
}

// Handle POST requests for files
fn handleFilePost(allocator: mem.Allocator, connection: Connection, request: Request, path: []const u8) HttpError!void {
    var response = Response.init(allocator, request);
    defer response.deinit();

    // Ensure we have a body
    const body = request.body orelse {
        return HttpError.BadRequest;
    };

    // Check if file size is reasonable
    if (body.len > 100 * 1024 * 1024) { // 100MB limit
        return HttpError.PayloadTooLarge;
    }

    // Create the file
    const dir_path = fs.path.dirname(path) orelse "";
    if (dir_path.len > 0) {
        fs.cwd().makePath(dir_path) catch |err| {
            log.err("Failed to create directory: {s}, error: {}", .{ dir_path, err });
            return HttpError.InternalServerError;
        };
    }

    const new_file = fs.cwd().createFile(path, .{}) catch |err| {
        log.err("Failed to create file: {s}, error: {}", .{ path, err });
        return HttpError.InternalServerError;
    };
    defer new_file.close();

    // Write the body to the file
    new_file.writeAll(body) catch unreachable;

    // Send success response
    const http_response = response
        .setStatusCode(HttpStatus.CREATED)
        .setStatusMessage(HttpStatus.getMessage(HttpStatus.CREATED))
        .build();
    defer allocator.free(http_response);

    connection.stream.writeAll(http_response) catch {
        return HttpError.InternalServerError;
    };
}

// Helper function to detect directory traversal attempts
fn containsDirectoryTraversal(path: []const u8) bool {
    // Check for relative path navigation patterns
    if (mem.indexOf(u8, path, "..") != null) return true;
    if (mem.indexOf(u8, path, "//") != null) return true;
    if (mem.indexOf(u8, path, "\\") != null) return true;

    // Other checks might be needed depending on your security requirements
    return false;
}

// Determine content type based on file extension
fn getContentType(path: []const u8) []const u8 {
    const extension = fs.path.extension(path);

    if (mem.eql(u8, extension, ".html") or mem.eql(u8, extension, ".htm")) {
        return "text/html";
    } else if (mem.eql(u8, extension, ".css")) {
        return "text/css";
    } else if (mem.eql(u8, extension, ".js")) {
        return "application/javascript";
    } else if (mem.eql(u8, extension, ".json")) {
        return "application/json";
    } else if (mem.eql(u8, extension, ".png")) {
        return "image/png";
    } else if (mem.eql(u8, extension, ".jpg") or mem.eql(u8, extension, ".jpeg")) {
        return "image/jpeg";
    } else if (mem.eql(u8, extension, ".gif")) {
        return "image/gif";
    } else if (mem.eql(u8, extension, ".txt") or mem.eql(u8, extension, ".md")) {
        return "text/plain";
    }

    // Default content type
    return "application/octet-stream";
}

const Router = struct {
    pub fn route(
        req: *http.Request,
        res: *http.Response,
        next: *fn (*http.Request, *http.Response) !void,
    ) !void {
        // Log the request
        log.info("Received request: {}", .{req.url});

        // Call the next middleware or route handler
        try next(req, res);
    }
};

const std = @import("std");
const http = @import("http.zig");
const log = @import("log.zig");

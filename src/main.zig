const std = @import("std");
const log = std.log;

const parseCommandLineArgs = @import("./args.zig").parseCommandLineArgs;
const HttpServer = @import("./server.zig").HttpServer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try parseCommandLineArgs(allocator);
    defer args.deinit();

    var server = try HttpServer.init(allocator, args);
    defer server.deinit();

    log.info("Server listening on {s}:{d}", .{ args.host, args.port });
    try server.start();
}

const std = @import("std");
const mem = std.mem;

const DEFAULT_PORT = 4221;
const DEFAULT_HOST = "127.0.0.1";
const DEFAULT_MAX_CONNECTIONS = 32;
const DEFAULT_THREAD_COUNT = 4;

pub const ServerArgs = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    directory: ?[]const u8,
    thread_count: u16,

    pub fn deinit(self: ServerArgs) void {
        if (self.directory) |dir| {
            self.allocator.free(dir);
        }
    }
};

pub fn parseCommandLineArgs(allocator: std.mem.Allocator) !ServerArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var server_args = ServerArgs{
        .allocator = allocator,
        .host = DEFAULT_HOST,
        .port = DEFAULT_PORT,
        .directory = null,
        .thread_count = DEFAULT_THREAD_COUNT,
    };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--directory") or std.mem.eql(u8, arg, "-d")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingDirectoryArgument;
            }
            server_args.directory = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--port") or std.mem.eql(u8, arg, "-p")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingPortArgument;
            }
            server_args.port = try std.fmt.parseInt(u16, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--threads") or std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingThreadsArgument;
            }
            server_args.thread_count = try std.fmt.parseInt(u16, args[i], 10);
        }
    }

    return server_args;
}

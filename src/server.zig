const std = @import("std");
const net = std.net;
const log = std.log;

const ServerArgs = @import("./args.zig").ServerArgs;
const handleConnection = @import("./connection.zig").handleConnection;
const ConnectionContext = @import("./connection.zig").ConnectionContext;
const http = @import("./http/http.zig");
const ThreadPool = @import("./thread_pool.zig").ThreadPool;

pub const HttpServer = struct {
    allocator: std.mem.Allocator,
    address: net.Address,
    listener: net.Server,
    directory: ?[]const u8,
    thread_pool: ThreadPool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, args: ServerArgs) !Self {
        const address = try net.Address.resolveIp(args.host, args.port);
        const listener = try address.listen(.{ .reuse_address = true });

        // Initialize thread pool for connection handling
        const thread_pool = try ThreadPool.init(allocator, args.thread_count);

        return Self{
            .allocator = allocator,
            .address = address,
            .listener = listener,
            .directory = args.directory,
            .thread_pool = thread_pool,
        };
    }

    pub fn deinit(self: *Self) void {
        self.thread_pool.deinit();
        self.listener.deinit();
    }

    pub fn start(self: *Self) !void {
        // Start the thread pool
        try self.thread_pool.start();
        while (true) {
            const connection = self.listener.accept() catch |err| {
                log.err("Error accepting connection: {}", .{err});
                continue;
            };
            const context = try self.allocator.create(ConnectionContext);
            context.* = ConnectionContext{
                .allocator = self.allocator,
                .connection = connection,
                .directory = self.directory,
            };
            self.thread_pool.submit(handleConnection, context) catch |err| {
                log.err("Failed to submit task: {}", .{err});
                self.allocator.destroy(context);
                connection.stream.close();
            };
        }
    }
};

const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;
const log = std.log;

/// Task represents a unit of work to be executed by the thread pool
pub const Task = struct {
    function: *const fn (data: *anyopaque) void,
    data: *anyopaque,
};

/// Thread pool for concurrent task execution
pub const ThreadPool = struct {
    allocator: std.mem.Allocator,
    threads: []Thread,
    task_queue: std.fifo.LinearFifo(Task, .Dynamic),
    mutex: Mutex,
    condition: Condition,
    shutdown: bool,

    const Self = @This();

    /// Initialize a new thread pool with the specified number of worker threads
    pub fn init(allocator: std.mem.Allocator, thread_count: u16) !Self {
        const threads = try allocator.alloc(Thread, thread_count);
        return Self{
            .allocator = allocator,
            .threads = threads,
            .task_queue = std.fifo.LinearFifo(Task, .Dynamic).init(allocator),
            .mutex = .{},
            .condition = .{},
            .shutdown = false,
        };
    }

    /// Clean up resources used by the thread pool
    pub fn deinit(self: *Self) void {
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.shutdown = true;
            self.condition.broadcast();
        }
        // Wait for all threads to complete
        for (self.threads) |thread| {
            thread.join();
        }
        self.allocator.free(self.threads);
        self.task_queue.deinit();
    }

    /// Start all worker threads in the pool
    pub fn start(self: *Self) !void {
        for (self.threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, workerFunction, .{self});
            log.debug("Started worker thread {d}", .{i});
        }
    }

    /// Submit a task to the thread pool
    pub fn submit(self: *Self, comptime function: anytype, data: anytype) !void {
        const DataPtr = @TypeOf(data);

        // Create a wrapper function that will be executed by the worker thread
        const WrapperFn = struct {
            fn wrapper(ptr: *anyopaque) void {
                const typed_ptr = @as(DataPtr, @ptrCast(@alignCast(ptr)));
                function(typed_ptr);
            }
        };

        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.shutdown) {
            return error.ThreadPoolShutdown;
        }

        // Create task with the wrapper function
        const task = Task{
            .function = &WrapperFn.wrapper,
            .data = @ptrCast(data),
        };

        try self.task_queue.writeItem(task);
        self.condition.signal();
    }

    /// Worker thread main function
    fn workerFunction(self: *Self) void {
        while (true) {
            const task = blk: {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (true) {
                    if (self.task_queue.readItem()) |item| {
                        break :blk item;
                    }

                    if (self.shutdown) {
                        return;
                    }

                    self.condition.wait(&self.mutex);
                }
            };

            // Execute the task
            task.function(task.data);
        }
    }
};

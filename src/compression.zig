const std = @import("std");
const mem = std.mem;

const gzip = std.compress.gzip;

pub const CompressionError = error{
    UnsupportedCompression,
    CompressionFailed,
};

pub const CompressionType = enum {
    None,
    Gzip,

    /// Convert string to compression type
    pub fn fromString(str: []const u8) ?CompressionType {
        if (mem.eql(u8, str, "gzip")) {
            return .Gzip;
        }
        return null;
    }

    /// Get string representation of compression type
    pub fn toString(self: CompressionType) []const u8 {
        return switch (self) {
            .None => "identity",
            .Gzip => "gzip",
        };
    }
};

pub const Compressor = struct {
    allocator: mem.Allocator,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn compress(self: Self, data: []const u8, compression_type: CompressionType) ![]const u8 {
        if (compression_type == .None) {
            return data;
        }

        var compressed = std.ArrayList(u8).init(self.allocator);
        errdefer compressed.deinit();

        switch (compression_type) {
            .None => unreachable, // Already handled above
            .Gzip => {
                var compressor = try gzip.compressor(compressed.writer(), .{});
                _ = try compressor.write(data);
                try compressor.finish();
            },
        }

        return compressed.toOwnedSlice();
    }
};

// HTTP Status codes and messages
pub const HttpStatus = struct {
    pub const OK = "200";
    pub const CREATED = "201";
    pub const NO_CONTENT = "204";
    pub const BAD_REQUEST = "400";
    pub const UNAUTHORIZED = "401";
    pub const FORBIDDEN = "403";
    pub const NOT_FOUND = "404";
    pub const METHOD_NOT_ALLOWED = "405";
    pub const PAYLOAD_TOO_LARGE = "413";
    pub const INTERNAL_SERVER_ERROR = "500";
    pub const NOT_IMPLEMENTED = "501";
    pub const SERVICE_UNAVAILABLE = "503";

    // Status messages corresponding to status codes
    pub fn getMessage(code: []const u8) []const u8 {
        const std = @import("std");

        if (std.mem.eql(u8, code, OK)) return "OK";
        if (std.mem.eql(u8, code, CREATED)) return "Created";
        if (std.mem.eql(u8, code, NO_CONTENT)) return "No Content";
        if (std.mem.eql(u8, code, BAD_REQUEST)) return "Bad Request";
        if (std.mem.eql(u8, code, UNAUTHORIZED)) return "Unauthorized";
        if (std.mem.eql(u8, code, FORBIDDEN)) return "Forbidden";
        if (std.mem.eql(u8, code, NOT_FOUND)) return "Not Found";
        if (std.mem.eql(u8, code, METHOD_NOT_ALLOWED)) return "Method Not Allowed";
        if (std.mem.eql(u8, code, PAYLOAD_TOO_LARGE)) return "Payload Too Large";
        if (std.mem.eql(u8, code, INTERNAL_SERVER_ERROR)) return "Internal Server Error";
        if (std.mem.eql(u8, code, NOT_IMPLEMENTED)) return "Not Implemented";
        if (std.mem.eql(u8, code, SERVICE_UNAVAILABLE)) return "Service Unavailable";

        return "Unknown Status";
    }
};

// Main module file to re-export HTTP components
pub const Request = @import("request.zig").Request;
pub const Response = @import("response.zig").Response;
pub const HttpMethod = @import("request.zig").HttpMethod;
pub const HttpHeader = @import("request.zig").HttpHeader;
pub const HttpStatus = @import("status.zig").HttpStatus;
pub const HeaderValue = @import("request.zig").HeaderValue;

// Common HTTP error set
pub const HttpError = error{
    InvalidRequest,
    InvalidMethod,
    InvalidHeader,
    NotFound,
    Forbidden,
    PayloadTooLarge,
    UnsupportedMediaType,
    InternalServerError,
    BadRequest,
};

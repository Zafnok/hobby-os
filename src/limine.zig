// src/limine.zig
pub const Uuid = [16]u8;
const LIMINE_COMMON_MAGIC = .{ 0xc7b1dd30df4c8b88, 0x0a82e883a194fcf1 };

pub const FramebufferRequest = extern struct {
    id: [4]u64 = LIMINE_COMMON_MAGIC ++ .{ 0x9d5827dcd881dd75, 0xa77e8b6979cf5778 },
    revision: u64 = 0,
    response: ?*FramebufferResponse = null,
};

pub const FramebufferResponse = extern struct {
    revision: u64,
    framebuffer_count: u64,
    framebuffers: [*]*Framebuffer,
};

pub const Framebuffer = extern struct {
    address: *anyopaque,
    width: u64,
    height: u64,
    pitch: u64,
    bpp: u16,
    memory_model: u8,
    red_mask_size: u8,
    red_mask_shift: u8,
    green_mask_size: u8,
    green_mask_shift: u8,
    blue_mask_size: u8,
    blue_mask_shift: u8,
    unused: [7]u8,
    edid_size: u64,
    edid: ?*anyopaque,
};

pub const BaseRevision = extern struct {
    id: [2]u64 = .{ 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc },
    revision: u64,
};

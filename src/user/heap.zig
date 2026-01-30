/// Userspace Heap Allocator
///
/// This module provides a memory allocator for userspace programs that adapts
/// the kernel's slab allocator design for use in SASOS userspace.
///
/// **Key Architectural Differences from Kernel Allocator:**
/// - Uses `lib.allocPages()` via kernel table instead of direct PMM access
/// - All free list data structures live in userspace memory (no PKS protection issues)
/// - No HHDM offset translation needed (pages come as virtual addresses)
/// - Cannot free pages back to kernel (no kernel API yet)
///
/// **Algorithm: Segregated Free List (Slab-like)**
///
/// This allocator maintains an array of linked lists (`free_lists`), where each list holds
/// free blocks of a specific power-of-two size (32B, 64B, ... 2048B).
///
/// *   **Small Allocations (<= 2KB)**: Served from these lists. If a list is empty,
///     a new 4KB page is requested from the kernel, "chopped" into fixed-size blocks (Slab),
///     and added to the list. O(1) complexity.
/// *   **Large Allocations (> 2KB)**: Served directly by allocating contiguous pages from the kernel.
///
/// This provides high performance and low fragmentation for small objects, while relying on the
/// kernel for large buffers.
const std = @import("std");

// In test mode, we use kernel PMM directly since we don't have a kernel table set up
const builtin = @import("builtin");
const lib = if (!builtin.is_test) @import("lib.zig") else struct {
    // Mock lib for testing - use kernel PMM directly
    const main = @import("../main.zig");
    const vmm = @import("../kernel/memory/vmm.zig");

    pub fn allocPages(count: usize) ?[*]u8 {
        const phys = main.pmm.allocatePages(count) orelse return null;
        const virt = phys + vmm.getHhdmOffset();
        return @ptrFromInt(virt);
    }

    pub fn log(msg: []const u8) void {
        _ = msg;
        // Silent in tests
    }
};

// Constants
const PAGE_SIZE: usize = 4096;
const MIN_BLOCK_SIZE: usize = 32;
// The largest block size we handle in the free lists.
// Anything larger will be rounded up to whole pages and allocated directly from kernel.
const MAX_BLOCK_SIZE: usize = 2048; // Half a page

/// A Node in a free list.
/// Because these nodes live INSIDE the free memory blocks themselves,
/// they take up 0 extra overhead.
const FreeBlock = struct {
    next: ?*FreeBlock,
};

/// The Userspace Allocator state.
///
/// **Algorithm: Segregated Free List (Slab-like)**
///
/// This allocator maintains an array of linked lists (`free_lists`), where each list holds
/// free blocks of a specific power-of-two size (32B, 64B, ... 2048B).
///
/// *   **Small Allocations (<= 2KB)**: Served from these lists. If a list is empty,
///     a new 4KB page is requested from the kernel, "chopped" into fixed-size blocks (Slab),
///     and added to the list. $O(1)$ complexity.
/// *   **Large Allocations (> 2KB)**: Served directly by allocating contiguous pages from the kernel.
///
/// This provides high performance and low fragmentation for small objects, while relying on the
/// kernel for large buffers.
pub const UserspaceAllocator = struct {
    // Array of free lists.
    // Index 0: 32 bytes
    // Index 1: 64 bytes
    // ...
    // Index 6: 2048 bytes
    // (We map size to index: log2(size) - log2(32))
    free_lists: [7]?*FreeBlock = .{null} ** 7,

    /// Initializes the allocator state (clears lists).
    pub fn init(self: *UserspaceAllocator) void {
        @memset(&self.free_lists, null);
        lib.log("Heap: UserspaceAllocator initialized.\n");
    }

    /// The main allocation function implementing std.mem.Allocator interface.
    pub fn allocator(self: *UserspaceAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    /// Allocates memory of at least `len` bytes.
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *UserspaceAllocator = @ptrCast(@alignCast(ctx));

        // 1. Calculate actual size needed (including alignment overhead/padding if complex)
        // For simple power-of-two slab, strict alignment > block size is tricky.
        // We assume standard alignments (<= size) for now.
        const size = @max(len, MIN_BLOCK_SIZE);
        const aligned_size = std.math.ceilPowerOfTwo(usize, size) catch return null;

        // 2. Big Allocation? (> 2KB) -> Go straight to kernel
        if (aligned_size > MAX_BLOCK_SIZE) {
            return self.allocLarge(aligned_size, ptr_align);
        }

        // 3. Small Allocation -> Use Free Lists
        const index = getListIndex(aligned_size);

        // Check if we have a free block
        if (self.free_lists[index]) |node| {
            // Pop from list
            self.free_lists[index] = node.next;
            // Zero the memory before giving it out? (Optional security/safety)
            @memset(@as([*]u8, @ptrCast(node))[0..aligned_size], 0);
            return @ptrCast(node);
        }

        // No free block? Allocate a new PAGE from kernel and chop it up.
        return self.refillSlab(index, aligned_size);
    }

    /// Resizing memory.
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        // Simplified: We don't support in-place resizing for now.
        // Std lib will fallback to alloc + copy + free if this returns false.
        return false;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    /// Frees memory.
    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = buf_align;
        _ = ret_addr;
        const self: *UserspaceAllocator = @ptrCast(@alignCast(ctx));

        const len = buf.len;
        const size = @max(len, MIN_BLOCK_SIZE);
        const aligned_size = std.math.ceilPowerOfTwo(usize, size) catch return;

        // 1. Big Allocation? Return to kernel (but we can't - no free API yet)
        if (aligned_size > MAX_BLOCK_SIZE) {
            self.freeLarge(buf);
            return;
        }

        // 2. Small Allocation? Push back to Free List
        const index = getListIndex(aligned_size);
        const node: *FreeBlock = @ptrCast(@alignCast(buf.ptr));

        node.next = self.free_lists[index];
        self.free_lists[index] = node;
    }

    // --- Helpers ---

    /// Gets the index into free_lists for a given power-of-two size.
    /// Size MUST be power of two and >= MIN_BLOCK_SIZE.
    fn getListIndex(size: usize) usize {
        // defined: log2(size) - log2(32)
        // 32 -> 0
        // 64 -> 1
        return std.math.log2_int(usize, size) - std.math.log2_int(usize, MIN_BLOCK_SIZE);
    }

    /// Allocates a large chunk (pages) directly from kernel.
    fn allocLarge(self: *UserspaceAllocator, size: usize, ptr_align: std.mem.Alignment) ?[*]u8 {
        _ = self;
        _ = ptr_align;
        // Calculate number of pages needed
        const pages_needed = (size + PAGE_SIZE - 1) / PAGE_SIZE;

        // Request pages from kernel via kernel table
        const ptr = lib.allocPages(pages_needed) orelse return null;
        return ptr;
    }

    /// Frees a large chunk (pages) back to kernel.
    /// NOTE: Currently stubbed - no kernel API to free pages yet.
    fn freeLarge(self: *UserspaceAllocator, buf: []u8) void {
        _ = self;
        _ = buf;
        // TODO: When kernel provides a free_pages() function in the kernel table,
        // call it here to return pages to the kernel.
        // For now, memory is leaked on large allocation frees.
    }

    /// Replenishes a specific size-class list by chopping up a new page.
    fn refillSlab(self: *UserspaceAllocator, index: usize, block_size: usize) ?[*]u8 {
        // 1. Get a new page from kernel
        const page_ptr = lib.allocPages(1) orelse return null;

        // 2. Page already comes as virtual address - no HHDM offset needed!
        // This is a key difference from kernel allocator.

        // 3. Chop it up
        // We have 4096 bytes.
        // block_size is e.g. 32.
        // We can fit 4096 / 32 = 128 blocks.
        const block_count = PAGE_SIZE / block_size;

        // Link them all together
        var i: usize = 0;
        while (i < block_count - 1) : (i += 1) {
            const curr_offset = i * block_size;
            const next_offset = (i + 1) * block_size;

            const curr_node: *FreeBlock = @ptrCast(@alignCast(&page_ptr[curr_offset]));
            const next_node: *FreeBlock = @ptrCast(@alignCast(&page_ptr[next_offset]));

            curr_node.next = next_node;
        }

        // The last block points to existing free list (null usually)
        const last_offset = (block_count - 1) * block_size;
        const last_node: *FreeBlock = @ptrCast(@alignCast(&page_ptr[last_offset]));
        last_node.next = self.free_lists[index];

        // 4. Update the free list head (skip the first one, we are returning it!)
        const first_node: *FreeBlock = @ptrCast(@alignCast(&page_ptr[0]));
        self.free_lists[index] = first_node.next;

        return @ptrCast(first_node);
    }
};

// Global allocator instance
var state = UserspaceAllocator{};

/// Returns the global userspace allocator.
pub fn getAllocator() std.mem.Allocator {
    return state.allocator();
}

/// Initializes the global userspace allocator.
pub fn init() void {
    state.init();
}

// ============================================================================
// Unit Tests
// ============================================================================

test "UserspaceAllocator: Basic Alloc" {
    const allocator = getAllocator();
    const ptr = try allocator.create(u32);
    ptr.* = 0xDEADBEEF;
    try std.testing.expect(ptr.* == 0xDEADBEEF);
    allocator.destroy(ptr);
}

test "UserspaceAllocator: Large Alloc (Single Page)" {
    const allocator = getAllocator();
    // Request 3000 bytes. This is > MAX_BLOCK_SIZE (2048) but < PAGE_SIZE (4096).
    // It should trigger the Large Alloc path but only request 1 page.
    const buf = try allocator.alloc(u8, 3000);
    try std.testing.expect(buf.len == 3000);
    @memset(buf, 0xBB);
    try std.testing.expect(buf[0] == 0xBB);
    try std.testing.expect(buf[2999] == 0xBB);
    allocator.free(buf);
}

test "UserspaceAllocator: Large Alloc (Multi Page)" {
    const allocator = getAllocator();
    // 5000 bytes -> 2 Pages (8192 bytes). Requires contiguous allocation.
    const large_buf = try allocator.alloc(u8, 5000);
    try std.testing.expect(large_buf.len == 5000);
    @memset(large_buf, 0xAA);
    try std.testing.expect(large_buf[4999] == 0xAA);
    // Verify first byte of second page (offset 4096) works
    try std.testing.expect(large_buf[4096] == 0xAA);
    allocator.free(large_buf);
}

test "UserspaceAllocator: Slab Exhaustion" {
    const allocator = getAllocator();
    // 32-byte blocks. 1 Page = 128 blocks.
    // We alloc 200 blocks to force a second page.
    var pointers: [200]*u32 = undefined;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        pointers[i] = try allocator.create(u32);
        pointers[i].* = @as(u32, @intCast(i));
    }

    // Verify
    i = 0;
    while (i < 200) : (i += 1) {
        try std.testing.expect(pointers[i].* == @as(u32, @intCast(i)));
    }

    // Cleanup
    i = 0;
    while (i < 200) : (i += 1) {
        allocator.destroy(pointers[i]);
    }
}

test "UserspaceAllocator: Memory Reuse" {
    const allocator = getAllocator();
    var pointers: [200]*u32 = undefined;

    // Fill first 100
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        pointers[i] = try allocator.create(u32);
    }

    // Free first 100
    i = 0;
    while (i < 100) : (i += 1) {
        allocator.destroy(pointers[i]);
    }

    // Re-alloc 100. Should ideally reuse the spots (LIFO or FIFO depends on impl, but shouldn't fail)
    i = 0;
    while (i < 100) : (i += 1) {
        pointers[i] = try allocator.create(u32);
        pointers[i].* = 0xFF;
    }

    // Cleanup
    i = 0;
    while (i < 100) : (i += 1) {
        allocator.destroy(pointers[i]);
    }
}

test "ArrayList usage" {
    const allocator = getAllocator();
    var list = std.ArrayList(u32).initCapacity(allocator, 4) catch unreachable;
    defer list.deinit(allocator);

    try list.append(allocator, 10);
    try list.append(allocator, 20);
    try list.append(allocator, 30);

    try std.testing.expect(list.items[0] == 10);
    try std.testing.expect(list.items[1] == 20);
    try std.testing.expect(list.items[2] == 30);
}

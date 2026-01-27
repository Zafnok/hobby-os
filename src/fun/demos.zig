const std = @import("std");
const limine = @import("../limine_import.zig").C;
const framebuffer = @import("../drivers/framebuffer.zig");

/// Draws a yellow smiley face on the framebuffer.
/// Clears the screen to white first, then draws the face, eyes, and mouth.
pub fn drawSmileyFace(fb: *limine.struct_limine_framebuffer) void {
    // White background
    framebuffer.fill(fb, 0xFFFFFFFF);

    // Center coordinates
    const cx = fb.width / 2;
    const cy = fb.height / 2;
    const radius = 100;

    // Yellow Face
    framebuffer.fillCircle(fb, cx, cy, radius, 0xFFFFFF00);

    // Black Eyes
    // Left eye
    framebuffer.fillCircle(fb, cx - 35, cy - 30, 10, 0xFF000000);
    // Right eye
    framebuffer.fillCircle(fb, cx + 35, cy - 30, 10, 0xFF000000);

    // Mouth (Smile)
    // We draw a "smile" by iterating a semi-circle area
    const mouth_r = 60;
    const mouth_thickness = 5;

    var my: u64 = cy;
    while (my <= cy + mouth_r) : (my += 1) {
        var mx: u64 = cx - mouth_r;
        while (mx <= cx + mouth_r) : (mx += 1) {
            const dx: i64 = @as(i64, @intCast(mx)) - @as(i64, @intCast(cx));
            const dy: i64 = @as(i64, @intCast(my)) - @as(i64, @intCast(cy));
            const dist2 = dx * dx + dy * dy;

            // Check if within the ring of the mouth
            if (dist2 <= mouth_r * mouth_r and dist2 >= (mouth_r - mouth_thickness) * (mouth_r - mouth_thickness)) {
                // Only draw lower half (already ensured by loop, but slightly lower looks better)
                if (my > cy + 15) {
                    framebuffer.putPixel(fb, mx, my, 0xFF000000);
                }
            }
        }
    }
}

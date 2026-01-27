#include "limine.h"
#include <stddef.h>

// The requests can be placed anywhere in the executable sections
// provided they are loaded by the bootloader.
// We use a dedicated section to be safe and clean.
// We export these variables so Zig can access them (extern var).

// Start Marker
__attribute__((used, section(".limine_reqs"))) static volatile uint64_t
    limine_reqs_start_marker[4] = LIMINE_REQUESTS_START_MARKER;

// Base Revision (Version 3) - Optimistic
__attribute__((used,
               section(".limine_reqs"))) volatile uint64_t base_revision[3] =
    LIMINE_BASE_REVISION(3);

// Framebuffer Request (Revision 1)
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_framebuffer_request
    framebuffer_request = {
        .id = LIMINE_FRAMEBUFFER_REQUEST_ID, .revision = 1, .response = NULL};

// HHDM Request (Revision 1)
__attribute__((
    used,
    section(
        ".limine_reqs"))) volatile struct limine_hhdm_request hhdm_request = {
    .id = LIMINE_HHDM_REQUEST_ID, .revision = 1, .response = NULL};

// End Marker
__attribute__((used, section(".limine_reqs"))) static volatile uint64_t
    limine_reqs_end_marker[2] = LIMINE_REQUESTS_END_MARKER;

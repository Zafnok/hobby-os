#include <stdint.h>

// Limine Header
#define LIMINE_COMMON_MAGIC 0xc7b1dd30df4c8b88, 0x0a82e883a194fcf1

struct limine_base_revision {
  uint64_t id[2];
  uint64_t revision;
};

struct limine_framebuffer_response;

struct limine_framebuffer_request {
  uint64_t id[4];
  uint64_t revision;
  struct limine_framebuffer_response *response;
};

struct limine_hhdm_request {
  uint64_t id[4];
  uint64_t revision;
  void *response;
};

// Requests
// Must be exported so Zig can access them
// Must be in .limine_reqs section
// Must be 'used' to prevent GC

__attribute__((
    used, aligned(8),
    section(
        ".limine_reqs"))) volatile struct limine_base_revision base_revision = {
    .id = {0xf9562b2d5c95a6c8, 0x6a7b384944536bdc}, .revision = 0};

__attribute__((
    used, aligned(8),
    section(".limine_reqs"))) volatile struct limine_framebuffer_request
    framebuffer_request = {
        .id = {LIMINE_COMMON_MAGIC, 0x9d5827dcd881dd75, 0xa77e8b6979cf5778},
        .revision = 0,
        .response = 0 // Explicitly NULL
};

// HHDM temporarily disabled/commented out to isolate FB
__attribute__((
    used, aligned(8),
    section(
        ".limine_reqs"))) volatile struct limine_hhdm_request hhdm_request = {
    .id = {LIMINE_COMMON_MAGIC, 0x48dcf1cb8ad2b852, 0x63984e959a98244b},
    .revision = 0,
    .response = 0};

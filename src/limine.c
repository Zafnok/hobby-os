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

// Bootloader Info Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_bootloader_info_request
    bootloader_info_request = {.id = LIMINE_BOOTLOADER_INFO_REQUEST_ID,
                               .revision = 0,
                               .response = NULL};

// Executable Cmdline Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_executable_cmdline_request
    executable_cmdline_request = {.id = LIMINE_EXECUTABLE_CMDLINE_REQUEST_ID,
                                  .revision = 0,
                                  .response = NULL};

// Firmware Type Request
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_firmware_type_request
    firmware_type_request = {
        .id = LIMINE_FIRMWARE_TYPE_REQUEST_ID, .revision = 0, .response = NULL};

// Stack Size Request
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_stack_size_request
    stack_size_request = {.id = LIMINE_STACK_SIZE_REQUEST_ID,
                          .revision = 0,
                          .response = NULL,
                          .stack_size = 0};

// HHDM Request (Revision 1)
__attribute__((
    used,
    section(
        ".limine_reqs"))) volatile struct limine_hhdm_request hhdm_request = {
    .id = LIMINE_HHDM_REQUEST_ID, .revision = 1, .response = NULL};

// Framebuffer Request (Revision 1)
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_framebuffer_request
    framebuffer_request = {
        .id = LIMINE_FRAMEBUFFER_REQUEST_ID, .revision = 1, .response = NULL};

// Paging Mode Request
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_paging_mode_request
    paging_mode_request = {.id = LIMINE_PAGING_MODE_REQUEST_ID,
                           .revision = 0,
                           .response = NULL,
                           .mode = 0,
                           .max_mode = 0,
                           .min_mode = 0};

// MP Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_mp_request mp_request = {
    .id = LIMINE_MP_REQUEST_ID, .revision = 0, .response = NULL, .flags = 0};

// Memory Map Request
__attribute__((used,
               section(".limine_reqs"))) volatile struct limine_memmap_request
    memmap_request = {
        .id = LIMINE_MEMMAP_REQUEST_ID, .revision = 0, .response = NULL};

// Executable File Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_executable_file_request
    executable_file_request = {.id = LIMINE_EXECUTABLE_FILE_REQUEST_ID,
                               .revision = 0,
                               .response = NULL};

// Module Request (Revision 1)
__attribute__((used,
               section(".limine_reqs"))) volatile struct limine_module_request
    module_request = {.id = LIMINE_MODULE_REQUEST_ID,
                      .revision = 1,
                      .response = NULL,
                      .internal_module_count = 0,
                      .internal_modules = NULL};

// RSDP Request
__attribute__((
    used,
    section(
        ".limine_reqs"))) volatile struct limine_rsdp_request rsdp_request = {
    .id = LIMINE_RSDP_REQUEST_ID, .revision = 0, .response = NULL};

// SMBIOS Request
__attribute__((used,
               section(".limine_reqs"))) volatile struct limine_smbios_request
    smbios_request = {
        .id = LIMINE_SMBIOS_REQUEST_ID, .revision = 0, .response = NULL};

// EFI System Table Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_efi_system_table_request
    efi_system_table_request = {.id = LIMINE_EFI_SYSTEM_TABLE_REQUEST_ID,
                                .revision = 0,
                                .response = NULL};

// EFI Memory Map Request
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_efi_memmap_request
    efi_memmap_request = {
        .id = LIMINE_EFI_MEMMAP_REQUEST_ID, .revision = 0, .response = NULL};

// Date at Boot Request
__attribute__((
    used, section(".limine_reqs"))) volatile struct limine_date_at_boot_request
    date_at_boot_request = {
        .id = LIMINE_DATE_AT_BOOT_REQUEST_ID, .revision = 0, .response = NULL};

// Executable Address Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_executable_address_request
    executable_address_request = {.id = LIMINE_EXECUTABLE_ADDRESS_REQUEST_ID,
                                  .revision = 0,
                                  .response = NULL};

// Device Tree Blob Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_dtb_request dtb_request = {
    .id = LIMINE_DTB_REQUEST_ID, .revision = 0, .response = NULL};

// RISC-V BSP Hart ID Request
__attribute__((
    used,
    section(".limine_reqs"))) volatile struct limine_riscv_bsp_hartid_request
    riscv_bsp_hartid_request = {.id = LIMINE_RISCV_BSP_HARTID_REQUEST_ID,
                                .revision = 0,
                                .response = NULL};

// Bootloader Performance Request
__attribute__((
    used,
    section(
        ".limine_reqs"))) volatile struct limine_bootloader_performance_request
    bootloader_performance_request = {
        .id = LIMINE_BOOTLOADER_PERFORMANCE_REQUEST_ID,
        .revision = 0,
        .response = NULL};

// End Marker
__attribute__((used, section(".limine_reqs"))) static volatile uint64_t
    limine_reqs_end_marker[2] = LIMINE_REQUESTS_END_MARKER;

/* Bootloader window: sectors 0-3 (64 KiB). Include this instead of the
   runtime common-ROM.ld (gprbuild -XLOADER=USER). The link fails if the
   image grows out of the window.

   Paths are relative to the link cwd, which gprbuild sets to obj/boot. */
INCLUDE ../../ld/layout_symbols.ld

/* The light runtime uses this as the only stack (the vector table's SP).
   Sector buffers live in .bss, so 2 KiB is the call chain. */
__stack_size = 2 * 1024;

MEMORY
{
  flash  (rx)  : ORIGIN = __boot_origin, LENGTH = __boot_length
  sram12 (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
  ccm    (rw)  : ORIGIN = 0x10000000, LENGTH = 64K
}

REGION_ALIAS("sram_tx", sram12)
REGION_ALIAS("sram_ro", sram12)
REGION_ALIAS("sram_bs", sram12)
REGION_ALIAS("sram_da", sram12)
REGION_ALIAS("ccm_da", ccm)

INCLUDE ../../ld/sections.ld

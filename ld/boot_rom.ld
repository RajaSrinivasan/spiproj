/* Bootloader window: sectors 0-6. Include this instead of the runtime
   common-ROM.ld (gprbuild -XLOADER=USER). The link fails if the image
   grows out of the window. */

/* Paths are relative to the link cwd, which gprbuild sets to the object
   directory (obj/boot). Same convention as the -T argument. */
INCLUDE ../../ld/layout_symbols.ld

/* Environment-task stack. The runtime uses __stack_start .. __stack_end.
   FAT plus the program buffer wants more than the 4 KiB default. */
__stack_size = 16 * 1024;

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

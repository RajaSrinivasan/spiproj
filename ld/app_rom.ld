/* Application window: sectors 4-11. The vector table is at __app_origin.
   The bootloader sets MSP and VTOR from that table and branches to the
   reset handler. Include this instead of the runtime common-ROM.ld
   (gprbuild -XLOADER=USER). */

/* Paths are relative to the link cwd, which gprbuild sets to the object
   directory (obj/app). Same convention as the -T argument. */
INCLUDE ../../ld/layout_symbols.ld

MEMORY
{
  flash  (rx)  : ORIGIN = __app_origin, LENGTH = __app_length
  sram12 (rwx) : ORIGIN = 0x20000000, LENGTH = 128K
  ccm    (rw)  : ORIGIN = 0x10000000, LENGTH = 64K
}

REGION_ALIAS("sram_tx", sram12)
REGION_ALIAS("sram_ro", sram12)
REGION_ALIAS("sram_bs", sram12)
REGION_ALIAS("sram_da", sram12)
REGION_ALIAS("ccm_da", ccm)

INCLUDE ../../ld/sections.ld

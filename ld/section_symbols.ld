/* Bounds of the flash images checked by Flash_CRC.
   Passed to ld along with ld/app_rom.ld or ld/boot_rom.ld.
   ADDR, SIZEOF, and LOADADDR refer to the output sections those scripts
   define (.text, .rodata, and .data). __data_lma_* is the flash load
   image of .data, not the RAM copy.

   For the application image the addresses sit in the upper window
   (ld/layout_symbols.ld), not at 0x08000000. The bootloader occupies
   the low window and is not part of this check. */

__text_start     = ADDR(.text);
__text_end       = ADDR(.text) + SIZEOF(.text);
__rodata_start   = ADDR(.rodata);
__rodata_end     = ADDR(.rodata) + SIZEOF(.rodata);
__data_lma_start = LOADADDR(.data);
__data_lma_end   = LOADADDR(.data) + SIZEOF(.data);

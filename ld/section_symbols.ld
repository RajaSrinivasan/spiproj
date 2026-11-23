/* Bounds of the flash images checked by Flash_CRC.
   Passed to ld along with the embedded-stm32f4 common-ROM.ld script.
   ADDR, SIZEOF, and LOADADDR refer to the output sections that script
   defines (.text, .rodata, and .data). __data_lma_* is the flash load
   image of .data, not the RAM copy. */

__text_start     = ADDR(.text);
__text_end       = ADDR(.text) + SIZEOF(.text);
__rodata_start   = ADDR(.rodata);
__rodata_end     = ADDR(.rodata) + SIZEOF(.rodata);
__data_lma_start = LOADADDR(.data);
__data_lma_end   = LOADADDR(.data) + SIZEOF(.data);

/* STM32F407VG flash split. tools/bootstrap_image.py must use the same
   numbers; CI rejects an ELF whose load addresses disagree.

   Sectors 0-6 are the bootloader (16+16+16+16+64+128+128 = 384 KiB).
   Sectors 7-11 are the application (5 * 128 = 640 KiB).
   The application starts on a sector boundary so the bootloader can erase
   it without touching its own sectors. */

__boot_origin = 0x08000000;
__boot_length = 0x00060000;
__app_origin  = 0x08060000;
__app_length  = 0x000A0000;

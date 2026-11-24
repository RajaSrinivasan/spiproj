/* STM32F407VG flash split. tools/bootstrap_image.py must use the same
   numbers; CI rejects an ELF whose load addresses disagree.

   Sectors 0-3 are the bootloader (4 * 16 KiB = 64 KiB).
   Sectors 4-11 are the application (64 KiB + 7 * 128 KiB = 960 KiB).
   The application starts on a sector boundary so the bootloader can erase
   it without touching its own sectors. */

__boot_origin = 0x08000000;
__boot_length = 0x00010000;
__app_origin  = 0x08010000;
__app_length  = 0x000F0000;

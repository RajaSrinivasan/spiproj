------------------------------------------------------------------------------
--  Flash windows for the STM32F407VG (1 MiB).
--
--  The numbers live in ld/layout_symbols.ld. This package reads those
--  absolute linker symbols (the same trick as Flash_CRC and the section
--  marks). Sectors 0-6 are the bootloader. Sectors 7-11 are the application.
--  Both windows start on a sector boundary.
--
--  SRAM_Origin / SRAM_Limit describe the 128 KiB main SRAM. The limit is
--  one past the last byte, so a descending stack may sit exactly on it.
------------------------------------------------------------------------------

with HAL; use HAL;

package Flash_Layout is

   function Boot_Origin return UInt32;
   function Boot_Length return UInt32;
   function App_Origin return UInt32;
   function App_Length return UInt32;

   SRAM_Origin : constant UInt32 := 16#2000_0000#;
   SRAM_Limit  : constant UInt32 := 16#2002_0000#;

end Flash_Layout;

------------------------------------------------------------------------------
--  Program the STM32F407 internal flash, application window only.
--
--  Erase and program refuse any range that is not entirely inside the
--  application window from Flash_Layout. The bootloader's own sectors are
--  never erased. Programming uses 32-bit stores (FLASH_CR.PSIZE = x32),
--  which is the parallelism required at 2.7 V to 3.6 V. The Discovery
--  board runs at 3.3 V.
--
--  A word is programmed once after its sector has been erased. The caller
--  erases first. A 1..3 byte tail is padded with 16#FF# so the last store
--  is still a 32-bit write into the erased word.
------------------------------------------------------------------------------

with HAL; use HAL;

package Internal_Flash is

   type Status is
     (OK,
      Timeout,
      Misaligned,
      Protected_Region,
      Operation_Error,
      Locked);

   procedure Invalidate_Caches;
   --  Drop the flash instruction and data caches so the next load reads
   --  the array. Call this after programming and before a compare.

   function Word_At (Address : UInt32) return UInt32;
   function Byte_At (Address : UInt32) return UInt8;

   procedure Erase
     (From    : UInt32;
      Length  : UInt32;
      Outcome : out Status);
   --  Erase every sector that overlaps [From, From + Length). Nothing is
   --  erased if any of those sectors would touch the bootloader, or if
   --  the range is not inside the application window.

   procedure Begin_Program (Outcome : out Status);
   --  Unlock the flash. Pair with End_Program. Program_Block requires it.

   procedure Program_Block
     (Address : UInt32;
      Data    : UInt8_Array;
      Outcome : out Status);
   --  Program Data at Address. Address is 4-byte aligned. The last partial
   --  word is padded with 16#FF#. The padded range must stay inside the
   --  application window.

   procedure End_Program;
   --  Lock the flash. Safe to call if Begin_Program did not succeed.

end Internal_Flash;

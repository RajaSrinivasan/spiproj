------------------------------------------------------------------------------
--  STM32F4 CRC unit, shared by Flash_CRC and the bootloader.
--
--  Polynomial 16#04C11DB7#, initial value 16#FFFF_FFFF#, no reflection,
--  no final XOR. Each 32-bit word is a little-endian load. A 1..3 byte
--  tail is packed into the low bytes of a zero-padded word. This matches
--  tools/elf_hashes.py and tools/bootstrap_image.py. It is a corruption
--  check, not a cryptographic hash.
------------------------------------------------------------------------------

with HAL; use HAL;
with System;

package STM32_CRC is

   type Accumulator is private;

   procedure Start (Acc : out Accumulator);
   --  Enable the CRC clock, reset the unit, and clear Acc.

   procedure Append (Acc : in out Accumulator; Data : UInt8_Array);
   --  Feed Data in order. Chunks may split a 32-bit word; the leftover
   --  bytes stay in Acc until the next Append or Finish.

   function Finish (Acc : in out Accumulator) return UInt32;
   --  Feed a partial trailing word, if Acc is holding 1..3 bytes, and
   --  return the unit's value. An empty stream returns 16#FFFF_FFFF#.

   function Digest (First : System.Address; Length : UInt32) return UInt32;
   --  Start, feed Length bytes at First, Finish. Length 0 is the
   --  initial value.

private

   type Accumulator is record
      Partial : UInt32 := 0;
      Filled  : Natural := 0;
   end record;

end STM32_CRC;

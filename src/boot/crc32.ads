------------------------------------------------------------------------------
--  STM32 CRC-32 in software: polynomial 16#04C11DB7#, init 16#FFFF_FFFF#,
--  no reflection, no final XOR. Same byte order as tools/elf_hashes.py.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

with Bytes;

package CRC32 is

   type Accumulator is record
      Value   : Unsigned_32 := 16#FFFF_FFFF#;
      Partial : Unsigned_32 := 0;
      Filled  : Natural := 0;
   end record;

   procedure Reset (Acc : out Accumulator);
   procedure Append (Acc : in out Accumulator; Data : Bytes.Arr);
   function Finish (Acc : in out Accumulator) return Unsigned_32;

end CRC32;

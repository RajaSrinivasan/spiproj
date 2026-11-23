------------------------------------------------------------------------------
--  CRC-32 of the flash images the loader placed for this program.
--
--  The STM32F4 CRC unit (STM32.CRC) is a corruption check, not a
--  cryptographic hash. It is the hardware CRC-32/MPEG-2 parameters:
--  polynomial 16#04C11DB7#, initial value 16#FFFF_FFFF#, no reflection,
--  no final XOR. Each 32-bit word is a little-endian load from flash.
--
--  Ranges come from ld/section_symbols.ld:
--    __text_start / __text_end           .text
--    __rodata_start / __rodata_end       .rodata
--    __data_lma_start / __data_lma_end   .data load image in flash
--  The RAM copy of .data is not hashed: it changes as the program runs.
--  .bss, .ARM.extab, and .ARM.exidx are not covered.
------------------------------------------------------------------------------

with HAL; use HAL;

package Flash_CRC is

   Check_Period_Seconds : constant Positive := 60;
   --  How often Weather_Logger recomputes the three digests.

   type Segment_Id is (Text, Rodata, Data_LMA);

   type Digest is record
      Start  : UInt32;
      Length : UInt32;
      CRC    : UInt32;
   end record;

   procedure Capture_References;
   --  Enable the CRC clock and store one digest per segment. Call once
   --  at startup, before Recheck.

   function Reference (Id : Segment_Id) return Digest;

   function Segment_Image (Id : Segment_Id) return String;

   procedure Recheck
     (Id      : Segment_Id;
      Current : out Digest;
      Match   : out Boolean);
   --  Recompute Id and compare it to the digest stored by Capture_References.
   --  Match is True when start, length, and CRC all agree.

end Flash_CRC;

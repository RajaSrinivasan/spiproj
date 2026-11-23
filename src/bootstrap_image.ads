------------------------------------------------------------------------------
--  SD-card bootstrap image, version 1.
--
--  The file on the card is named "bootstrap" (no extension) at the root of
--  the FAT volume. The on-disk layout is little-endian, 32-byte header
--  then the raw application image produced by arm-eabi-objcopy -O binary:
--
--    offset  size  field
--    0       4     magic ASCII "SPB1"
--    4       4     header length, must be 32
--    8       4     payload length, in bytes
--    12      4     load address, must be the application origin
--    16      4     STM32 CRC-32 of the payload bytes
--    20      4     STM32 CRC-32 of bytes 0 .. 19
--    24      4     reserved, must be 0
--    28      4     reserved, must be 0
--    32      N     payload (vector table at offset 0 of the payload)
--
--  tools/bootstrap_image.py writes this file. The CRC is the STM32 unit
--  (see STM32_CRC), a corruption check and not a signature: anyone who can
--  write the card can supply an image.
------------------------------------------------------------------------------

with System;

with HAL; use HAL;

package Bootstrap_Image is

   Header_Bytes     : constant := 32;
   Header_CRC_Bytes : constant := 20;
   Path             : constant String := "/sd/bootstrap";

   type Magic_Bytes is array (1 .. 4) of Character;

   type Header is record
      Magic         : Magic_Bytes;
      Header_Bytes  : UInt32;
      Payload_Bytes : UInt32;
      Load_Address  : UInt32;
      Payload_CRC   : UInt32;
      Header_CRC    : UInt32;
      Reserved_0    : UInt32;
      Reserved_1    : UInt32;
   end record
     with Size => 32 * 8, Bit_Order => System.Low_Order_First;

   for Header use record
      Magic         at 0 range 0 .. 31;
      Header_Bytes  at 4 range 0 .. 31;
      Payload_Bytes at 8 range 0 .. 31;
      Load_Address  at 12 range 0 .. 31;
      Payload_CRC   at 16 range 0 .. 31;
      Header_CRC    at 20 range 0 .. 31;
      Reserved_0    at 24 range 0 .. 31;
      Reserved_1    at 28 range 0 .. 31;
   end record;

   pragma Compile_Time_Error
     (Header'Size /= 256, "bootstrap header is not 32 bytes");

   type Failure is
     (None,
      Bad_Magic,
      Bad_Header,
      Bad_Length,
      Bad_Address,
      Bad_Vector,
      Bad_CRC);

   function Check_Fields
     (Item                 : Header;
      File_Bytes           : UInt64;
      Computed_Header_CRC  : UInt32;
      App_Origin           : UInt32;
      App_Length           : UInt32) return Failure;
   --  Magic, header length, reserved words, header CRC, load address, and
   --  payload length against the file size and the application window.
   --  Does not look at the payload bytes.

   function Valid_Vector
     (SP, Reset, Origin, Limit : UInt32) return Boolean;
   --  SP is 8-byte aligned and lies in main SRAM. A full descending stack
   --  may sit on the byte just past SRAM, so that address is accepted.
   --  Reset has the Thumb bit set. The handler address lies in
   --  [Origin, Limit).

end Bootstrap_Image;

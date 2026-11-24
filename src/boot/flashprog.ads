------------------------------------------------------------------------------
--  Erase and program the application window only. 32-bit stores, which is
--  the STM32F407 parallelism at 3.3 V. Sectors that touch the bootloader
--  are refused.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

with Bytes;

package FlashProg is

   type Status is (OK, Failed, Rejected);

   function App_Origin return Unsigned_32;
   function App_Length return Unsigned_32;
   function Boot_Origin return Unsigned_32;
   function Boot_Length return Unsigned_32;

   procedure Invalidate_Caches;

   function Word_At (Address : Unsigned_32) return Unsigned_32;
   function Byte_At (Address : Unsigned_32) return Unsigned_8;

   procedure Erase
     (From    : Unsigned_32;
      Length  : Unsigned_32;
      Outcome : out Status);

   procedure Begin_Program (Outcome : out Status);

   procedure Program
     (Address : Unsigned_32;
      Data    : Bytes.Arr;
      Outcome : out Status);

   procedure End_Program;

end FlashProg;

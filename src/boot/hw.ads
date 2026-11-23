------------------------------------------------------------------------------
--  Pins, LEDs, cycle counter, and USART2 for the light-runtime bootloader.
--  No Ada_Drivers_Library. USART2 is PA2/PA3, 115200 8N1. LEDs are the
--  Discovery's PD12-PD15, active high.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

package HW is

   procedure Initialize;

   procedure Put (Text : String);
   procedure Put_Line (Text : String);

   procedure Leds_Off;
   procedure Blue (On : Boolean);
   procedure Red (On : Boolean);
   procedure Orange (On : Boolean);

   procedure Wait_Ms (Ms : Unsigned_32);
   function Cycles return Unsigned_32;

end HW;

------------------------------------------------------------------------------
--  Text log on USART2 of an STM32F407 Discovery board.
--
--  PA2 is USART2_TX and PA3 is USART2_RX, alternate function AF7
--  (GPIO_AF_USART2_7), 115200 baud, 8 data bits, no parity, one stop bit,
--  no flow control. Lines written by Put_Line end with CR LF.
--
--  Those pins are free on the Discovery: the user button is PA0, the LEDs
--  are PD12 .. PD15, the LIS3DSH accelerometer takes SPI1 (PA5 .. PA7, PE3),
--  the audio codec takes PA4 / PB6 / PB9 / PC7 / PC10 / PC12 / PD4, USB
--  takes PA9 / PA11 / PA12, and the microphone takes PB10 / PC3. USART1 TX
--  would be PA9 (USB VBUS) and USART6 shares PC7 with the audio clock, so
--  USART2 is the port that does not collide with the board.
------------------------------------------------------------------------------

package Serial_Log is

   procedure Initialize;
   --  Enable the GPIO and USART2 clocks, configure PA2 and PA3, and bring
   --  USART2 up at 115200 8N1. Call this before Put or Put_Line.

   procedure Put (Text : String);
   --  Block until the transmitter accepts every character of Text.

   procedure Put_Line (Text : String);
   --  Put Text followed by CR then LF.

end Serial_Log;

------------------------------------------------------------------------------
--  SPI2 shared bus for an STM32F4 Discovery (STM32F407VG) board:
--    PB13 = SCK, PB14 = MISO, PB15 = MOSI  (GPIO_AF_SPI2_5)
--    PB12 = GPIO chip-select for a microSD reader  (idle high)
--    PB11 = GPIO chip-select for a BME280 in SPI mode (idle high)
--
--  Names and types are those of AdaCore Ada_Drivers_Library
--  (github.com/AdaCore/Ada_Drivers_Library): STM32.Device (stm32f40x),
--  STM32.GPIO, STM32.SPI.
------------------------------------------------------------------------------

with STM32.SPI;

package SPI_Bus is

   procedure Initialize;
   --  Enable clocks, configure the SPI2 pins as AF5, configure PB12 and
   --  PB11 as push-pull outputs and drive them high, then bring SPI2 up as
   --  a Mode-0 master, 8-bit, MSB first, software-managed NSS, with
   --  Baud_Rate_Prescaler BRP_128 (a modest rate suitable for SD card
   --  initialization: about 328 kHz when APB1 is 42 MHz).

   procedure Set_Prescaler (Prescaler : STM32.SPI.SPI_Baud_Rate_Prescaler);
   --  Change only the SPI2 baud prescaler. STM32.SPI has no dedicated
   --  baud-change primitive, so this disables the port, calls
   --  STM32.SPI.Configure with the existing Mode-0 master settings and the
   --  new prescaler, then re-enables the port.

   procedure Select_SD;
   --  Assert the microSD chip-select (PB12 low). The BME280 is deselected.

   procedure Deselect_SD;
   --  Release the microSD chip-select (PB12 high).

   procedure Select_BME;
   --  Assert the BME280 chip-select (PB11 low). The microSD is deselected.

   procedure Deselect_BME;
   --  Release the BME280 chip-select (PB11 high).

end SPI_Bus;

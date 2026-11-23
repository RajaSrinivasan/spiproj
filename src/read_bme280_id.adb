------------------------------------------------------------------------------
--  Read the BME280 chip-ID register over SPI2.
--
--  The BME280 treats a transaction as a read when bit 7 of the first byte
--  is set, so register 16#D0# is sent as 16#D0# itself (the read bit is
--  already that bit). A dummy byte is clocked out to shift the ID back;
--  a genuine BME280 returns 16#60#.
--
--  The onboard LEDs are used as a simple result: green if the ID matches,
--  red otherwise. This main does not print, because the Discovery board
--  has no console unless you add USART or semihosting yourself.
------------------------------------------------------------------------------

with HAL;          use HAL;

with STM32.Board;  use STM32.Board;
with STM32.Device; use STM32.Device;
with STM32.SPI;    use STM32.SPI;

with SPI_Bus;

procedure Read_BME280_ID is
   --  First byte: register 16#D0# with the read bit already set.
   --  Second byte: dummy 16#00# that clocks the chip-ID back on MISO.
   Outgoing : constant UInt8_Buffer := (16#D0#, 16#00#);
   Incoming : UInt8_Buffer (Outgoing'Range);
   Chip_ID  : UInt8;
begin
   Initialize_LEDs;
   All_LEDs_Off;
   SPI_Bus.Initialize;

   SPI_Bus.Select_BME;
   Transmit_Receive (SPI_2, Outgoing, Incoming, Size => Outgoing'Length);
   SPI_Bus.Deselect_BME;

   --  Incoming (Incoming'First) is the dummy byte sampled while the
   --  register address was shifted out; the chip-ID follows it.
   Chip_ID := Incoming (Incoming'First + 1);

   if Chip_ID = 16#60# then
      Turn_On (Green_LED);
   else
      Turn_On (Red_LED);
   end if;

   loop
      null;
   end loop;
end Read_BME280_ID;

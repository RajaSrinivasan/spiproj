with HAL.SPI;

with STM32.Device; use STM32.Device;
with STM32.GPIO;   use STM32.GPIO;
with STM32.SPI;    use STM32.SPI;

package body SPI_Bus is

   SPI_Pins : constant GPIO_Points := (PB13, PB14, PB15);
   --  SCK, MISO, MOSI on SPI2, alternate function GPIO_AF_SPI2_5.

   SD_CS  : GPIO_Point renames PB12;
   BME_CS : GPIO_Point renames PB11;

   SPI_Conf : SPI_Configuration :=
     (Direction           => D2Lines_FullDuplex,
      Mode                => Master,
      Data_Size           => HAL.SPI.Data_Size_8b,
      Clock_Polarity      => Low,     --  SPI Mode 0: CPOL = 0
      Clock_Phase         => P1Edge,  --  SPI Mode 0: CPHA = 0
      Slave_Management    => Software_Managed,  --  CS is a GPIO, not NSS
      Baud_Rate_Prescaler => BRP_128, --  modest rate for SD initialization
      First_Bit           => MSB,
      CRC_Poly            => 7);

   CS_Conf : constant GPIO_Port_Configuration :=
     (Mode        => Mode_Out,
      Resistors   => Pull_Up,
      Output_Type => Push_Pull,
      Speed       => Speed_25MHz);

   SPI_Pin_Conf : constant GPIO_Port_Configuration :=
     (Mode           => Mode_AF,
      Resistors      => Floating,
      AF_Output_Type => Push_Pull,
      AF_Speed       => Speed_50MHz,
      AF             => GPIO_AF_SPI2_5);

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      Enable_Clock (SPI_Pins);
      Enable_Clock (SD_CS);
      Enable_Clock (BME_CS);
      Enable_Clock (SPI_2);

      Configure_IO (SPI_Pins, SPI_Pin_Conf);

      Configure_IO (SD_CS,  CS_Conf);
      Configure_IO (BME_CS, CS_Conf);
      SD_CS.Set;   --  idle high
      BME_CS.Set;

      SPI_Conf.Baud_Rate_Prescaler := BRP_128;
      Disable (SPI_2);
      Configure (SPI_2, SPI_Conf);
      Enable (SPI_2);
   end Initialize;

   -------------------
   -- Set_Prescaler --
   -------------------

   procedure Set_Prescaler (Prescaler : SPI_Baud_Rate_Prescaler) is
   begin
      SPI_Conf.Baud_Rate_Prescaler := Prescaler;
      Disable (SPI_2);
      Configure (SPI_2, SPI_Conf);
      Enable (SPI_2);
   end Set_Prescaler;

   ---------------
   -- Select_SD --
   ---------------

   procedure Select_SD is
   begin
      BME_CS.Set;
      SD_CS.Clear;
   end Select_SD;

   -----------------
   -- Deselect_SD --
   -----------------

   procedure Deselect_SD is
   begin
      SD_CS.Set;
   end Deselect_SD;

   ----------------
   -- Select_BME --
   ----------------

   procedure Select_BME is
   begin
      SD_CS.Set;
      BME_CS.Clear;
   end Select_BME;

   ------------------
   -- Deselect_BME --
   ------------------

   procedure Deselect_BME is
   begin
      BME_CS.Set;
   end Deselect_BME;

end SPI_Bus;

------------------------------------------------------------------------------
--  Combined demo: initialize the BME280 and the microSD card on the shared
--  SPI2 bus, read temperature / pressure / humidity, then write one
--  512-byte block to the card and read it back. The original contents of
--  that block are restored afterwards. The block used is the last one
--  reported by the CSD, so the card's partition table is left alone.
--
--  Green LED: all steps succeeded. Red LED: a step failed.
------------------------------------------------------------------------------

with Ada.Real_Time; use Ada.Real_Time;

with HAL;               use HAL;
with HAL.Block_Drivers; use HAL.Block_Drivers;

with STM32.Board; use STM32.Board;

with SPI_Bus;
with BME280; use BME280;
with SD_SPI; use SD_SPI;

procedure Demo_SPI2 is

   procedure Fail with No_Return;
   --  Light the red LED and wait forever.

   procedure Fail is
   begin
      All_LEDs_Off;
      Turn_On (Red_LED);
      loop
         null;
      end loop;
   end Fail;

   Sensor     : BME280_Sensor;
   Card       : SD_Card;
   BME_Error  : Boolean;
   SD_Status  : SD_SPI.SD_Status;
   T          : Temperature;
   P          : Pressure;
   H          : Humidity;
   Test_Block : UInt64;
   Original   : Block (1 .. Block_Size);
   Pattern    : Block (1 .. Block_Size);
   Check      : Block (1 .. Block_Size);
   Restored   : Boolean;
   pragma Unreferenced (Restored);

begin
   Initialize_LEDs;
   All_LEDs_Off;
   SPI_Bus.Initialize;

   Initialize (Sensor, BME_Error);
   if BME_Error or else Get_Chip_ID (Sensor) /= Chip_ID (Expected_Chip_ID) then
      Fail;
   end if;

   --  ctrl_hum must be written before the ctrl_meas write that applies it.
   Set_Hum_Precision (Sensor, Standard_Resolution);
   Set_Temp_Precision (Sensor, Standard_Resolution);
   Set_Press_Precision (Sensor, Standard_Resolution);
   Set_Time_Standby (Sensor, 125.0);
   Set_Power_Mode (Sensor, Normal);

   delay until Clock + Milliseconds (200);

   T := Get_Temperature (Sensor);
   P := Get_Pressure (Sensor);
   H := Get_Humidity (Sensor);
   --  The fixed-point types already constrain the legal range. If a
   --  compensation result were wildly out of range, Constraint_Error
   --  would land in the handler below.
   if T < Temperature'First or else P < Pressure'First
     or else H < Humidity'First
   then
      Fail;
   end if;

   Initialize (Card, SD_Status);
   if SD_Status /= OK or else Block_Count (Card) < 2 then
      Fail;
   end if;

   Test_Block := Block_Count (Card) - 1;

   if not Read (Card, Test_Block, Original) then
      Fail;
   end if;

   for I in Pattern'Range loop
      Pattern (I) := UInt8 ((I - Pattern'First) mod 256);
   end loop;
   Pattern (1) := 16#BE#;
   Pattern (2) := 16#28#;
   Pattern (3) := 16#0D#;

   if not Write (Card, Test_Block, Pattern) then
      Restored := Write (Card, Test_Block, Original);
      Fail;
   end if;

   if not Read (Card, Test_Block, Check)
     or else Check /= Pattern
   then
      Restored := Write (Card, Test_Block, Original);
      Fail;
   end if;

   if not Write (Card, Test_Block, Original) then
      Fail;
   end if;

   All_LEDs_Off;
   Turn_On (Green_LED);
   loop
      null;
   end loop;

exception
   when others =>
      All_LEDs_Off;
      Turn_On (Red_LED);
      loop
         null;
      end loop;
end Demo_SPI2;

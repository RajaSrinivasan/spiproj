------------------------------------------------------------------------------
--  Log BME280 readings to WEATHER.CSV on a FAT filesystem on the microSD
--  card, once every 10 seconds.
--
--  Mounting uses the library helpers: Filesystem.MBR.Read / Valid /
--  Get_Type / LBA to find the first FAT partition, then
--  Filesystem.FAT.Open at that LBA (or LBA 0 if there is no MBR, i.e. a
--  superfloppy card), then File_IO.Mount_Volume. File_IO.Mount_Drive does
--  a similar MBR walk but has no superfloppy fallback and only accepts
--  partition types 6 and 11 .. 12, so this main does the walk itself.
--
--  File_IO has no append mode. Filesystem.FAT.Files.Open with Write_Only
--  truncates the file (Set_Size to 0). This logger opens the file
--  Read_Write (which creates it if it is missing), writes the header only
--  when Size is 0, otherwise Seeks From_End by 0, then writes one line
--  and Closes. Close flushes the data and the directory entry, so a
--  power cut loses at most the in-progress line.
--
--  Numbers are formatted by hand: embedded-stm32f4 ships Ada.Text_IO
--  (a-textio) but not Ada.Text_IO.Float_IO / Integer_IO (no a-tiflio or
--  a-tiinio in the runtime).
--
--  Green LED blinks after each successful write. Solid red means a mount
--  or write failure (logging stops).
------------------------------------------------------------------------------

with Ada.Real_Time; use Ada.Real_Time;

with HAL.Block_Drivers;
with HAL.Filesystem; use type HAL.Filesystem.Status_Code;

with File_IO;         use File_IO;
with Filesystem;      use Filesystem;
with Filesystem.FAT;
with Filesystem.MBR;  use Filesystem.MBR;

with STM32.Board; use STM32.Board;

with SPI_Bus;
with BME280; use BME280;
with SD_SPI; use SD_SPI;

procedure Weather_Logger is

   Header : constant String :=
     "seconds,temp_c,pressure_pa,humidity_pct" & ASCII.LF;
   Path   : constant String := "/sd/WEATHER.CSV";

   procedure Fail with No_Return;
   --  Solid red LED, then wait forever.

   function Is_FAT (T : Partition_Type) return Boolean;
   --  FAT12/16/32 partition types from the Partitions package constants.

   function Mount_Card
     (Device : not null HAL.Block_Drivers.Any_Block_Driver;
      FS     : in out Filesystem.FAT.FAT_Filesystem)
      return Status_Code;

   procedure Append (Buf  : in out String;
                     Last : in out Natural;
                     S    : String);

   procedure Append_Unsigned
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Natural);

   procedure Append_Integer
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Integer);

   procedure Append_Fixed_2
     (Buf        : in out String;
      Last       : in out Natural;
      Hundredths : Integer);
   --  Format Hundredths / 100 with a sign and exactly two decimal places.

   function Write_All
     (File : File_Descriptor; Text : String) return Boolean;

   function Append_Reading
     (Seconds : Integer;
      T       : Temperature;
      P       : Pressure;
      H       : Humidity) return Boolean;

   ----------
   -- Fail --
   ----------

   procedure Fail is
   begin
      All_LEDs_Off;
      Turn_On (Red_LED);
      loop
         null;
      end loop;
   end Fail;

   ------------
   -- Is_FAT --
   ------------

   function Is_FAT (T : Partition_Type) return Boolean is
   begin
      --  Values match Partitions.Fat12_Parition, Fat16_Parition,
      --  Fat16B_Parition, Fat32_CHS_Parition, Fat32_LBA_Parition,
      --  Fat16B_LBA_Parition (note the library's "Parition" spelling).
      return T in 16#01# | 16#04# | 16#06# | 16#0B# | 16#0C# | 16#0E#;
   end Is_FAT;

   ----------------
   -- Mount_Card --
   ----------------

   function Mount_Card
     (Device : not null HAL.Block_Drivers.Any_Block_Driver;
      FS     : in out Filesystem.FAT.FAT_Filesystem)
      return Status_Code
   is
      MBR     : Master_Boot_Record;
      MBR_St  : Status_Code;
      FAT_St  : HAL.Filesystem.Status_Code;
      LBA     : Block_Number := 0;
      Found   : Boolean := False;
   begin
      MBR_St := Read (Device, MBR);

      if MBR_St = OK then
         for P in Partition_Number'Range loop
            if Valid (MBR, P) and then Is_FAT (Get_Type (MBR, P)) then
               LBA := Filesystem.MBR.LBA (MBR, P);
               Found := True;
               exit;
            end if;
         end loop;

         --  Valid MBR but no FAT entry: still try LBA 0 as a last resort.
         if not Found then
            LBA := 0;
         end if;

      elsif MBR_St = No_MBR_Found then
         --  Superfloppy: the volume starts at the first block.
         LBA := 0;

      else
         return MBR_St;
      end if;

      FAT_St := Filesystem.FAT.Open (Device, LBA, FS);
      if FAT_St /= HAL.Filesystem.OK then
         return No_Filesystem;
      end if;

      return Mount_Volume ("sd", FS'Unchecked_Access);
   end Mount_Card;

   ------------
   -- Append --
   ------------

   procedure Append
     (Buf  : in out String;
      Last : in out Natural;
      S    : String)
   is
   begin
      for C of S loop
         if Last < Buf'Last then
            Last := Last + 1;
            Buf (Last) := C;
         end if;
      end loop;
   end Append;

   ---------------------
   -- Append_Unsigned --
   ---------------------

   procedure Append_Unsigned
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Natural)
   is
      Digits_C : constant String := "0123456789";
      N        : Natural := Value;
      Stack    : String (1 .. 10);
      Top      : Natural := 0;
   begin
      if N = 0 then
         Append (Buf, Last, "0");
         return;
      end if;

      while N > 0 and then Top < Stack'Last loop
         Top := Top + 1;
         Stack (Top) := Digits_C (Digits_C'First + (N mod 10));
         N := N / 10;
      end loop;

      for I in reverse 1 .. Top loop
         Append (Buf, Last, Stack (I .. I));
      end loop;
   end Append_Unsigned;

   --------------------
   -- Append_Integer --
   --------------------

   procedure Append_Integer
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Integer)
   is
   begin
      if Value < 0 then
         Append (Buf, Last, "-");
         Append_Unsigned (Buf, Last, Natural (-Value));
      else
         Append_Unsigned (Buf, Last, Natural (Value));
      end if;
   end Append_Integer;

   --------------------
   -- Append_Fixed_2 --
   --------------------

   procedure Append_Fixed_2
     (Buf        : in out String;
      Last       : in out Natural;
      Hundredths : Integer)
   is
      Negative : constant Boolean := Hundredths < 0;
      Mag      : constant Natural :=
        (if Negative then Natural (-Hundredths) else Natural (Hundredths));
      Whole    : constant Natural := Mag / 100;
      Frac     : constant Natural := Mag mod 100;
   begin
      if Negative then
         Append (Buf, Last, "-");
      end if;
      Append_Unsigned (Buf, Last, Whole);
      Append (Buf, Last, ".");
      if Frac < 10 then
         Append (Buf, Last, "0");
      end if;
      Append_Unsigned (Buf, Last, Frac);
   end Append_Fixed_2;

   ---------------
   -- Write_All --
   ---------------

   function Write_All
     (File : File_Descriptor; Text : String) return Boolean
   is
      Written : File_Size;
   begin
      Written := Write (File, Text'Address, File_Size (Text'Length));
      return Written = File_Size (Text'Length);
   end Write_All;

   --------------------
   -- Append_Reading --
   --------------------

   function Append_Reading
     (Seconds : Integer;
      T       : Temperature;
      P       : Pressure;
      H       : Humidity) return Boolean
   is
      File    : File_Descriptor;
      Status  : Status_Code;
      Amount  : File_Size := 0;
      Buf     : String (1 .. 80);
      Last    : Natural := 0;
      --  Pressure is stored in hPa; the CSV column is pascals.
      Pa      : constant Integer := Integer (P * 100.0);
      T_100   : constant Integer := Integer (T / 0.01);
      H_100   : constant Integer := Integer (H / 0.01);
   begin
      Status := Open (File, Path, Read_Write);
      if Status /= OK then
         return False;
      end if;

      if Size (File) = 0 then
         if not Write_All (File, Header) then
            Close (File);
            return False;
         end if;
      else
         Status := Seek (File, From_End, Amount);
         if Status /= OK then
            Close (File);
            return False;
         end if;
      end if;

      Append_Integer (Buf, Last, Seconds);
      Append (Buf, Last, ",");
      Append_Fixed_2 (Buf, Last, T_100);
      Append (Buf, Last, ",");
      Append_Integer (Buf, Last, Pa);
      Append (Buf, Last, ",");
      Append_Fixed_2 (Buf, Last, H_100);
      Append (Buf, Last, String'(1 => ASCII.LF));

      if not Write_All (File, Buf (1 .. Last)) then
         Close (File);
         return False;
      end if;

      --  Close calls the FAT handle Close, which Flushes the dirty
      --  buffer and updates the directory entry, then frees the handle.
      Close (File);
      return True;
   end Append_Reading;

   Sensor    : BME280_Sensor;
   Card      : aliased SD_Card;
   FAT_FS    : aliased Filesystem.FAT.FAT_Filesystem;
   BME_Error : Boolean;
   SD_Status : SD_SPI.SD_Status;
   Status    : File_IO.Status_Code;
   T         : Temperature;
   P         : Pressure;
   H         : Humidity;
   Start     : Time;
   Next      : Time;
   Elapsed   : Integer;

begin
   Initialize_LEDs;
   All_LEDs_Off;
   SPI_Bus.Initialize;

   Initialize (Sensor, BME_Error);
   if BME_Error or else Get_Chip_ID (Sensor) /= Chip_ID (Expected_Chip_ID) then
      Fail;
   end if;

   Set_Hum_Precision (Sensor, Standard_Resolution);
   Set_Temp_Precision (Sensor, Standard_Resolution);
   Set_Press_Precision (Sensor, Standard_Resolution);
   Set_Time_Standby (Sensor, 125.0);
   Set_Power_Mode (Sensor, Normal);

   delay until Clock + Milliseconds (200);

   Initialize (Card, SD_Status);
   if SD_Status /= OK then
      Fail;
   end if;

   Status := Mount_Card (Card'Unchecked_Access, FAT_FS);
   if Status /= OK then
      Fail;
   end if;

   Start := Clock;
   Next  := Start;

   loop
      T := Get_Temperature (Sensor);
      P := Get_Pressure (Sensor);
      H := Get_Humidity (Sensor);

      Elapsed := Integer ((Clock - Start) / Seconds (1));

      if not Append_Reading (Elapsed, T, P, H) then
         Fail;
      end if;

      Turn_On (Green_LED);
      delay until Clock + Milliseconds (80);
      Turn_Off (Green_LED);

      Next := Next + Seconds (10);
      delay until Next;
   end loop;

exception
   when others =>
      All_LEDs_Off;
      Turn_On (Red_LED);
      loop
         null;
      end loop;
end Weather_Logger;

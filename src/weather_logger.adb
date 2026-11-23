------------------------------------------------------------------------------
--  Log BME280 readings to WEATHER.CSV on a FAT filesystem on the microSD
--  card, once every 10 seconds.
--
--  Mounting is SD_Volume.Mount: the first FAT partition, or LBA 0 when
--  the card has no MBR (a superfloppy), then File_IO.Mount_Volume. The
--  bootloader uses the same walk so both programs see one volume.
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
--  a-tiinio in the runtime). The same helpers format the USART2 line.
--
--  Every reading is also written to USART2 (PA2 TX, PA3 RX, 115200 8N1).
--  Lines are colon-separated and end with CR LF. One sample counter,
--  starting at 1, is shared by DATA, HASH, ERR, and INFO lines. The header
--  that names the columns is not counted. DATA lines carry the CSV columns.
--  HASH lines are the STM32 CRC-32 of .text, .rodata, and the .data flash
--  image (see Flash_CRC). A mismatch also prints ERR and latches the red LED.
--
--  Green LED blinks after each successful SD write. A solid red LED means
--  the card failed to initialize, the volume failed to mount, a write
--  failed, or a flash CRC no longer matches the boot reference. Serial
--  logging continues in those cases. The red LED stays on after a CRC
--  mismatch. A missing or unread BME280 is still fatal.
------------------------------------------------------------------------------

with Ada.Real_Time; use Ada.Real_Time;

with File_IO; use File_IO;
with Filesystem.FAT;

with HAL; use HAL;

with STM32.Board; use STM32.Board;

with SPI_Bus;
with BME280; use BME280;
with SD_SPI; use SD_SPI;
with SD_Volume;
with Serial_Log;
with Flash_CRC;

procedure Weather_Logger is

   Header : constant String :=
     "seconds,temp_c,pressure_pa,humidity_pct" & ASCII.LF;
   Path   : constant String := "/sd/WEATHER.CSV";

   Serial_Header : constant String := "sample:type:payload";

   --  Shared by every DATA, HASH, ERR, and INFO line. The header is not
   --  a sample. CRC_Fault latches so a later SD write cannot clear the LED.
   Sample    : Natural := 0;
   CRC_Fault : Boolean := False;

   procedure Fail with No_Return;
   --  Solid red LED, then wait forever.

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

   procedure Emit (Kind : String; Rest : String);
   --  One USART line: sample:Kind:Rest. Increments the shared counter.

   procedure Emit_Sample
     (Seconds : Integer;
      T       : Temperature;
      P       : Pressure;
      H       : Humidity);
   --  DATA line. Same fixed-point scaling as the CSV row.

   procedure Append_Hex
     (Buf   : in out String;
      Last  : in out Natural;
      Value : UInt32);
   --  Eight uppercase hex digits.

   procedure Emit_Hash
     (Id     : Flash_CRC.Segment_Id;
      Item   : Flash_CRC.Digest;
      Status : String);

   procedure Log_References;
   procedure Log_Recheck;

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

   ----------
   -- Emit --
   ----------

   procedure Emit (Kind : String; Rest : String) is
      Buf  : String (1 .. 128);
      Last : Natural := 0;
   begin
      Sample := Sample + 1;
      Append_Unsigned (Buf, Last, Sample);
      Append (Buf, Last, ":");
      Append (Buf, Last, Kind);
      Append (Buf, Last, ":");
      Append (Buf, Last, Rest);
      Serial_Log.Put_Line (Buf (1 .. Last));
   end Emit;

   -----------------
   -- Emit_Sample --
   -----------------

   procedure Emit_Sample
     (Seconds : Integer;
      T       : Temperature;
      P       : Pressure;
      H       : Humidity)
   is
      Buf   : String (1 .. 80);
      Last  : Natural := 0;
      --  Pressure is stored in hPa; the log column is pascals, as in the CSV.
      Pa    : constant Integer := Integer (P * 100.0);
      T_100 : constant Integer := Integer (T / 0.01);
      H_100 : constant Integer := Integer (H / 0.01);
   begin
      Append_Integer (Buf, Last, Seconds);
      Append (Buf, Last, ":");
      Append_Fixed_2 (Buf, Last, T_100);
      Append (Buf, Last, ":");
      Append_Integer (Buf, Last, Pa);
      Append (Buf, Last, ":");
      Append_Fixed_2 (Buf, Last, H_100);
      Emit ("DATA", Buf (1 .. Last));
   end Emit_Sample;

   ----------------
   -- Append_Hex --
   ----------------

   procedure Append_Hex
     (Buf   : in out String;
      Last  : in out Natural;
      Value : UInt32)
   is
      Hex_Digits : constant String := "0123456789ABCDEF";
      V          : UInt32 := Value;
      Stack      : String (1 .. 8);
   begin
      for I in reverse Stack'Range loop
         Stack (I) := Hex_Digits (Hex_Digits'First + Natural (V mod 16));
         V := V / 16;
      end loop;
      Append (Buf, Last, Stack);
   end Append_Hex;

   ---------------
   -- Emit_Hash --
   ---------------

   procedure Emit_Hash
     (Id     : Flash_CRC.Segment_Id;
      Item   : Flash_CRC.Digest;
      Status : String)
   is
      Buf  : String (1 .. 80);
      Last : Natural := 0;
   begin
      Append (Buf, Last, Flash_CRC.Segment_Image (Id));
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, Item.Start);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, Item.Length);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, Item.CRC);
      Append (Buf, Last, ":");
      Append (Buf, Last, Status);
      Emit ("HASH", Buf (1 .. Last));
   end Emit_Hash;

   ---------------------
   -- Log_References --
   ---------------------

   procedure Log_References is
      Buf  : String (1 .. 32);
      Last : Natural := 0;
   begin
      Append (Buf, Last, "crc_period_s:");
      Append_Unsigned (Buf, Last, Flash_CRC.Check_Period_Seconds);
      Emit ("INFO", Buf (1 .. Last));
      for Id in Flash_CRC.Segment_Id loop
         Emit_Hash (Id, Flash_CRC.Reference (Id), "REF");
      end loop;
   end Log_References;

   -----------------
   -- Log_Recheck --
   -----------------

   procedure Log_Recheck is
      Current : Flash_CRC.Digest;
      Match   : Boolean;
   begin
      --  One pass over the three segments, between samples. Each segment
      --  is a straight word walk of flash into the CRC unit, short next
      --  to the 10 s sample period, so the delay-until below still hits
      --  the original Next deadline.
      for Id in Flash_CRC.Segment_Id loop
         Flash_CRC.Recheck (Id, Current, Match);
         if Match then
            Emit_Hash (Id, Current, "OK");
         else
            CRC_Fault := True;
            Turn_On (Red_LED);
            Emit_Hash (Id, Current, "MISMATCH");
            Emit ("ERR", "crc_mismatch:" & Flash_CRC.Segment_Image (Id));
         end if;
      end loop;
   end Log_Recheck;

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
   Next_Hash : Time;
   Elapsed   : Integer;
   SD_Ready  : Boolean := False;

begin
   Initialize_LEDs;
   All_LEDs_Off;
   Serial_Log.Initialize;
   Serial_Log.Put_Line (Serial_Header);
   Flash_CRC.Capture_References;
   Log_References;

   SPI_Bus.Initialize;

   Initialize (Sensor, BME_Error);
   if BME_Error or else Get_Chip_ID (Sensor) /= Chip_ID (Expected_Chip_ID) then
      Emit ("ERR", "bme280_init_failed");
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
      Emit ("ERR", "sd_init_failed");
      Turn_On (Red_LED);
   else
      Status := SD_Volume.Mount (Card'Unchecked_Access, FAT_FS);
      if Status /= OK then
         Emit ("ERR", "sd_mount_failed");
         Turn_On (Red_LED);
      else
         SD_Ready := True;
      end if;
   end if;

   Start     := Clock;
   Next      := Start;
   Next_Hash := Start + Seconds (Flash_CRC.Check_Period_Seconds);

   loop
      T := Get_Temperature (Sensor);
      P := Get_Pressure (Sensor);
      H := Get_Humidity (Sensor);

      Elapsed := Integer ((Clock - Start) / Seconds (1));

      Emit_Sample (Elapsed, T, P, H);

      if SD_Ready then
         if Append_Reading (Elapsed, T, P, H) then
            if not CRC_Fault then
               Turn_Off (Red_LED);
            end if;
            Turn_On (Green_LED);
            delay until Clock + Milliseconds (80);
            Turn_Off (Green_LED);
         else
            Emit ("ERR", "sd_write_failed");
            Turn_On (Red_LED);
         end if;
      end if;

      if Clock >= Next_Hash then
         Log_Recheck;
         Next_Hash := Next_Hash + Seconds (Flash_CRC.Check_Period_Seconds);
      end if;

      Next := Next + Seconds (10);
      delay until Next;
   end loop;

exception
   when others =>
      Emit ("ERR", "exception");
      All_LEDs_Off;
      Turn_On (Red_LED);
      loop
         null;
      end loop;
end Weather_Logger;

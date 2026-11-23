------------------------------------------------------------------------------
--  SD-card bootstrap for the STM32F407 Discovery.
--
--  This image occupies flash sectors 0-6. The application image occupies
--  sectors 7-11 and is entered only by a branch; it is not linked at the
--  reset address. On every reset:
--
--    1. Bring up USART2 and look for /sd/bootstrap.
--    2. If the file is missing, unreadable, or fails validation, leave it
--       alone and branch to the application when that image's vector table
--       looks sane. Never erase in this case.
--    3. When the file is valid, compare it with the application window. A
--       match skips erase (so a delete that failed on the previous boot
--       does not wear the flash). Otherwise erase the application sectors,
--       program the payload, and read it back.
--    4. Delete the file only after the programmed bytes and their STM32
--       CRC-32 match the file. Then branch.
--
--  A failure after erase has destroyed the old application. The file is
--  kept, the bootloader halts, and the next reset tries again. The
--  bootloader's own sectors are not erased.
--
--  Lines on USART2 use the same sample:type:payload form as Weather_Logger.
--  This program's counter is its own; the application starts again at 1.
------------------------------------------------------------------------------

with System.Storage_Elements;

with File_IO; use File_IO;
with Filesystem.FAT;

with HAL; use HAL;

with STM32.Board; use STM32.Board;

with SPI_Bus;
with SD_SPI; use SD_SPI;
with SD_Volume;
with Serial_Log;
with Flash_Layout;
with Bootstrap_Image;
with STM32_CRC;
with Internal_Flash;
with App_Jump;

use type Bootstrap_Image.Failure;
use type Internal_Flash.Status;

procedure Bootloader is

   Sample : Natural := 0;

   procedure Halt with No_Return;
   procedure Start_Application with No_Return;

   procedure Append
     (Buf  : in out String;
      Last : in out Natural;
      S    : String);

   procedure Append_Unsigned
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Natural);

   procedure Append_Hex
     (Buf   : in out String;
      Last  : in out Natural;
      Value : UInt32);

   procedure Emit (Kind : String; Rest : String);

   function Failure_Token (Reason : Bootstrap_Image.Failure) return String;

   function Seek_To
     (File : in out File_Descriptor;
      Pos  : File_Size) return Boolean;

   function Read_Exact
     (File : File_Descriptor;
      Buf  : in out UInt8_Array) return Boolean;

   type Image_View is record
      IO_Error : Boolean := False;
      File_CRC : UInt32 := 0;
      Match    : Boolean := False;
      SP       : UInt32 := 0;
      Reset    : UInt32 := 0;
   end record;

   function Inspect
     (File    : in out File_Descriptor;
      Payload : UInt32) return Image_View;
   --  Seek to the payload, hash it, and compare it with the application
   --  window. Match is meaningful only when IO_Error is False and the
   --  caller has already accepted the file CRC.

   function Remove_Bootstrap return Boolean;

   procedure Log_Layout;
   procedure Log_Bootstrap_OK (Payload : UInt32; CRC : UInt32);

   ----------
   -- Halt --
   ----------

   procedure Halt is
   begin
      Turn_On (Red_LED);
      loop
         null;
      end loop;
   end Halt;

   -----------------------
   -- Start_Application --
   -----------------------

   procedure Start_Application is
      Buf      : String (1 .. 24);
      Last     : Natural := 0;
      Switched : Boolean;
   begin
      if not App_Jump.Installed_OK then
         Emit ("ERR", "app_invalid");
         Halt;
      end if;

      Append (Buf, Last, "jump_app:");
      Append_Hex (Buf, Last, Flash_Layout.App_Origin);
      Emit ("INFO", Buf (1 .. Last));

      --  The baud rate is about to change with the clock. This line is the
      --  last one that a terminal set to 115200 can read.
      All_LEDs_Off;
      SPI_Bus.Deselect_SD;
      SPI_Bus.Deselect_BME;

      App_Jump.Jump (Flash_Layout.App_Origin, Switched);
      if not Switched then
         Turn_On (Blue_LED);
         Turn_On (Red_LED);
         Emit ("ERR", "clock_switch_failed");
      end if;
      Halt;
   end Start_Application;

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

   ----------
   -- Emit --
   ----------

   procedure Emit (Kind : String; Rest : String) is
      Buf  : String (1 .. 96);
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

   -------------------
   -- Failure_Token --
   -------------------

   function Failure_Token (Reason : Bootstrap_Image.Failure) return String is
     (case Reason is
         when Bootstrap_Image.None        => "bootstrap_ok",
         when Bootstrap_Image.Bad_Magic   => "bootstrap_bad_magic",
         when Bootstrap_Image.Bad_Header  => "bootstrap_bad_header",
         when Bootstrap_Image.Bad_Length  => "bootstrap_bad_length",
         when Bootstrap_Image.Bad_Address => "bootstrap_bad_address",
         when Bootstrap_Image.Bad_Vector  => "bootstrap_bad_vector",
         when Bootstrap_Image.Bad_CRC     => "bootstrap_bad_crc");

   -------------
   -- Seek_To --
   -------------

   function Seek_To
     (File : in out File_Descriptor;
      Pos  : File_Size) return Boolean
   is
      Amount : File_Size := Pos;
   begin
      return Seek (File, From_Start, Amount) = OK and then Amount = Pos;
   end Seek_To;

   ----------------
   -- Read_Exact --
   ----------------

   function Read_Exact
     (File : File_Descriptor;
      Buf  : in out UInt8_Array) return Boolean
   is
      Got : File_Size;
   begin
      Got := Read (File, Buf'Address, File_Size (Buf'Length));
      return Got = File_Size (Buf'Length);
   end Read_Exact;

   -------------
   -- Inspect --
   -------------

   function Inspect
     (File    : in out File_Descriptor;
      Payload : UInt32) return Image_View
   is
      use System.Storage_Elements;
      View      : Image_View;
      Acc       : STM32_CRC.Accumulator;
      Remaining : UInt32 := Payload;
      Offset    : UInt32 := 0;
      Chunk     : UInt8_Array (1 .. 512) := (others => 0);
      Head      : UInt8_Array (1 .. 8) := (others => 0);
   begin
      Internal_Flash.Invalidate_Caches;

      if not Seek_To (File, File_Size (Bootstrap_Image.Header_Bytes)) then
         View.IO_Error := True;
         return View;
      end if;

      STM32_CRC.Start (Acc);
      View.Match := True;

      while Remaining > 0 loop
         declare
            Want : Natural := 512;
         begin
            if UInt32 (Want) > Remaining then
               Want := Natural (Remaining);
            end if;

            if not Read_Exact (File, Chunk (1 .. Want)) then
               View.IO_Error := True;
               View.Match := False;
               return View;
            end if;

            STM32_CRC.Append (Acc, Chunk (1 .. Want));

            for I in 1 .. Want loop
               if Offset < 8 then
                  Head (Natural (Offset) + 1) := Chunk (I);
               end if;
               if View.Match
                 and then Chunk (I) /=
                   Internal_Flash.Byte_At (Flash_Layout.App_Origin + Offset)
               then
                  View.Match := False;
               end if;
               Offset := Offset + 1;
            end loop;

            Remaining := Remaining - UInt32 (Want);
         end;
      end loop;

      View.File_CRC := STM32_CRC.Finish (Acc);

      declare
         function Word (From : Natural) return UInt32 is
            W     : UInt32 := 0;
            Piece : UInt32;
         begin
            for I in 0 .. 3 loop
               Piece := UInt32 (Head (From + I));
               for S in 1 .. I loop
                  Piece := Piece * 256;
               end loop;
               W := W or Piece;
            end loop;
            return W;
         end Word;
      begin
         View.SP := Word (1);
         View.Reset := Word (5);
      end;

      if View.Match then
         declare
            Flash_CRC : constant UInt32 :=
              STM32_CRC.Digest
                (To_Address (Integer_Address (Flash_Layout.App_Origin)),
                 Payload);
         begin
            View.Match := Flash_CRC = View.File_CRC;
         end;
      end if;

      return View;
   end Inspect;

   ----------------------
   -- Remove_Bootstrap --
   ----------------------

   function Remove_Bootstrap return Boolean is
      Status : Status_Code;
      Probe  : File_Descriptor;
   begin
      Status := Unlink (Bootstrap_Image.Path);
      if Status /= OK then
         return False;
      end if;

      Status := Open (Probe, Bootstrap_Image.Path, Read_Only);
      if Status = OK then
         Close (Probe);
         return False;
      end if;
      return Status = No_Such_File;
   end Remove_Bootstrap;

   ----------------
   -- Log_Layout --
   ----------------

   procedure Log_Layout is
      Buf  : String (1 .. 64);
      Last : Natural := 0;
   begin
      Append (Buf, Last, "layout:boot:");
      Append_Hex (Buf, Last, Flash_Layout.Boot_Origin);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, Flash_Layout.Boot_Length);
      Append (Buf, Last, ":app:");
      Append_Hex (Buf, Last, Flash_Layout.App_Origin);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, Flash_Layout.App_Length);
      Emit ("INFO", Buf (1 .. Last));
   end Log_Layout;

   ----------------------
   -- Log_Bootstrap_OK --
   ----------------------

   procedure Log_Bootstrap_OK (Payload : UInt32; CRC : UInt32) is
      Buf  : String (1 .. 40);
      Last : Natural := 0;
   begin
      Append (Buf, Last, "bootstrap_ok:");
      Append_Hex (Buf, Last, Payload);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, CRC);
      Emit ("INFO", Buf (1 .. Last));
   end Log_Bootstrap_OK;

   Card      : aliased SD_Card;
   FAT_FS    : aliased Filesystem.FAT.FAT_Filesystem;
   SD_Status : SD_SPI.SD_Status;
   Status    : File_IO.Status_Code;
   File      : File_Descriptor;
   Hdr       : Bootstrap_Image.Header;
   Got       : File_Size;
   Reason    : Bootstrap_Image.Failure;
   View      : Image_View;
   Flash_St  : Internal_Flash.Status;

begin
   Initialize_LEDs;
   All_LEDs_Off;
   Turn_On (Blue_LED);
   Serial_Log.Initialize;
   Serial_Log.Put_Line ("sample:type:payload");
   Emit ("INFO", "bootloader");
   Log_Layout;

   SPI_Bus.Initialize;
   Initialize (Card, SD_Status);
   if SD_Status /= OK then
      Emit ("ERR", "sd_init_failed");
      Start_Application;
   end if;

   Status := SD_Volume.Mount (Card'Unchecked_Access, FAT_FS);
   if Status /= OK then
      Emit ("ERR", "sd_mount_failed");
      Start_Application;
   end if;

   Status := Open (File, Bootstrap_Image.Path, Read_Only);
   if Status = No_Such_File then
      Emit ("INFO", "no_bootstrap");
      Start_Application;
   elsif Status /= OK then
      Emit ("ERR", "bootstrap_open_failed");
      Start_Application;
   end if;

   Got := Read (File, Hdr'Address, File_Size (Bootstrap_Image.Header_Bytes));
   if Got /= File_Size (Bootstrap_Image.Header_Bytes) then
      Close (File);
      Emit ("ERR", "bootstrap_short");
      Start_Application;
   end if;

   Reason :=
     Bootstrap_Image.Check_Fields
       (Item                => Hdr,
        File_Bytes          => UInt64 (Size (File)),
        Computed_Header_CRC =>
          STM32_CRC.Digest
            (Hdr'Address, UInt32 (Bootstrap_Image.Header_CRC_Bytes)),
        App_Origin          => Flash_Layout.App_Origin,
        App_Length          => Flash_Layout.App_Length);

   if Reason /= Bootstrap_Image.None then
      Close (File);
      Emit ("ERR", Failure_Token (Reason));
      Start_Application;
   end if;

   View := Inspect (File, Hdr.Payload_Bytes);
   if View.IO_Error then
      Close (File);
      Emit ("ERR", "bootstrap_io");
      Start_Application;
   end if;

   if View.File_CRC /= Hdr.Payload_CRC then
      Close (File);
      Emit ("ERR", "bootstrap_bad_crc");
      Start_Application;
   end if;

   if not Bootstrap_Image.Valid_Vector
     (SP     => View.SP,
      Reset  => View.Reset,
      Origin => Flash_Layout.App_Origin,
      Limit  => Flash_Layout.App_Origin + Hdr.Payload_Bytes)
   then
      Close (File);
      Emit ("ERR", "bootstrap_bad_vector");
      Start_Application;
   end if;

   Log_Bootstrap_OK (Hdr.Payload_Bytes, View.File_CRC);

   if View.Match then
      Close (File);
      Emit ("INFO", "already_programmed");
      if Remove_Bootstrap then
         Emit ("INFO", "bootstrap_deleted");
      else
         Emit ("ERR", "delete_failed");
      end if;
      Start_Application;
   end if;

   --  The file is valid and the flash does not already hold it. Erasing
   --  the application sectors destroys the old image. From here on a
   --  failure halts with the file still on the card; the next reset
   --  retries. The branch below is not taken.
   Turn_On (Orange_LED);
   Emit ("INFO", "erase");
   Internal_Flash.Erase
     (Flash_Layout.App_Origin, Hdr.Payload_Bytes, Flash_St);
   if Flash_St /= Internal_Flash.OK then
      Close (File);
      Emit ("ERR", "erase_failed");
      Halt;
   end if;

   Emit ("INFO", "program");
   Internal_Flash.Begin_Program (Flash_St);
   if Flash_St /= Internal_Flash.OK then
      Close (File);
      Emit ("ERR", "program_failed");
      Halt;
   end if;

   if not Seek_To (File, File_Size (Bootstrap_Image.Header_Bytes)) then
      Internal_Flash.End_Program;
      Close (File);
      Emit ("ERR", "program_failed");
      Halt;
   end if;

   declare
      Remaining : UInt32 := Hdr.Payload_Bytes;
      Offset    : UInt32 := 0;
      Chunk     : UInt8_Array (1 .. 512) := (others => 0);
   begin
      while Remaining > 0 loop
         declare
            Want : Natural := 512;
         begin
            if UInt32 (Want) > Remaining then
               Want := Natural (Remaining);
            end if;

            if not Read_Exact (File, Chunk (1 .. Want)) then
               Internal_Flash.End_Program;
               Close (File);
               Emit ("ERR", "program_failed");
               Halt;
            end if;

            Internal_Flash.Program_Block
              (Flash_Layout.App_Origin + Offset,
               Chunk (1 .. Want),
               Flash_St);
            if Flash_St /= Internal_Flash.OK then
               Internal_Flash.End_Program;
               Close (File);
               Emit ("ERR", "program_failed");
               Halt;
            end if;

            Offset := Offset + UInt32 (Want);
            Remaining := Remaining - UInt32 (Want);
         end;
      end loop;
   end;

   Internal_Flash.End_Program;

   View := Inspect (File, Hdr.Payload_Bytes);
   if View.IO_Error
     or else not View.Match
     or else View.File_CRC /= Hdr.Payload_CRC
   then
      Close (File);
      Emit ("ERR", "verify_failed");
      Halt;
   end if;

   Emit ("INFO", "verify_ok");
   Close (File);
   Turn_Off (Orange_LED);

   if Remove_Bootstrap then
      Emit ("INFO", "bootstrap_deleted");
   else
      --  The image is in flash and checked. Starting it is safe. The file
      --  is still there, so the next reset takes the already_programmed
      --  path and tries the delete again without erasing.
      Emit ("ERR", "delete_failed");
   end if;

   Start_Application;

exception
   when others =>
      Emit ("ERR", "exception");
      Halt;
end Bootloader;

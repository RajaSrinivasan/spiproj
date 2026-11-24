------------------------------------------------------------------------------
--  SD-card bootstrap, built on the light runtime so it fits in 64 KiB.
--
--  Validate the file completely before erasing. Program, read the flash
--  back, and delete "bootstrap" only after the bytes and the CRC match.
--  A missing or invalid file leaves the card alone and branches to the
--  application when its vector table looks sane. A failure after erase
--  keeps the file and halts, so the next reset can retry.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

with Bytes;
with HW;
with SDCard;
with FAT;
with CRC32;
with FlashProg;
with StartApp;

use type Bytes.Arr;
use type FlashProg.Status;

procedure Bootloader is

   Sample : Natural := 0;

   procedure Halt;
   procedure Start_Application;
   procedure Append
     (Buf  : in out String;
      Last : in out Natural;
      S    : String);
   procedure Append_Hex
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Unsigned_32);
   procedure Append_Dec
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Natural);
   procedure Emit (Kind : String; Rest : String);

   procedure Halt is
   begin
      HW.Red (True);
      loop
         null;
      end loop;
   end Halt;

   procedure Start_Application is
      Buf      : String (1 .. 24);
      Last     : Natural := 0;
      Switched : Boolean;
   begin
      if not StartApp.Installed then
         Emit ("ERR", "app_invalid");
         Halt;
      end if;
      Append (Buf, Last, "jump_app:");
      Append_Hex (Buf, Last, FlashProg.App_Origin);
      Emit ("INFO", Buf (1 .. Last));
      HW.Leds_Off;
      StartApp.Jump (FlashProg.App_Origin, Switched);
      if not Switched then
         HW.Blue (True);
         HW.Red (True);
         Emit ("ERR", "clock_switch_failed");
      end if;
      Halt;
   end Start_Application;

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

   procedure Append_Dec
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Natural)
   is
      Figures : constant String := "0123456789";
      N      : Natural := Value;
      Stack  : String (1 .. 10);
      Top    : Natural := 0;
   begin
      if N = 0 then
         Append (Buf, Last, "0");
         return;
      end if;
      while N > 0 and then Top < Stack'Last loop
         Top := Top + 1;
         Stack (Top) := Figures (Figures'First + (N mod 10));
         N := N / 10;
      end loop;
      for I in reverse 1 .. Top loop
         Append (Buf, Last, Stack (I .. I));
      end loop;
   end Append_Dec;

   procedure Append_Hex
     (Buf   : in out String;
      Last  : in out Natural;
      Value : Unsigned_32)
   is
      Figures : constant String := "0123456789ABCDEF";
      V      : Unsigned_32 := Value;
      Stack  : String (1 .. 8);
   begin
      for I in reverse Stack'Range loop
         Stack (I) := Figures (Figures'First + Natural (V mod 16));
         V := V / 16;
      end loop;
      Append (Buf, Last, Stack);
   end Append_Hex;

   procedure Emit (Kind : String; Rest : String) is
      Buf  : String (1 .. 80);
      Last : Natural := 0;
   begin
      Sample := Sample + 1;
      Append_Dec (Buf, Last, Sample);
      Append (Buf, Last, ":");
      Append (Buf, Last, Kind);
      Append (Buf, Last, ":");
      Append (Buf, Last, Rest);
      HW.Put_Line (Buf (1 .. Last));
   end Emit;

   function Word_Of (B : Bytes.Arr; From : Natural) return Unsigned_32 is
      W : Unsigned_32 := 0;
   begin
      for I in 0 .. 3 loop
         W := W or Shift_Left (Unsigned_32 (B (From + I)), I * 8);
      end loop;
      return W;
   end Word_Of;

   procedure Log_Layout is
      Buf  : String (1 .. 64);
      Last : Natural := 0;
   begin
      Append (Buf, Last, "layout:boot:");
      Append_Hex (Buf, Last, FlashProg.Boot_Origin);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, FlashProg.Boot_Length);
      Append (Buf, Last, ":app:");
      Append_Hex (Buf, Last, FlashProg.App_Origin);
      Append (Buf, Last, ":");
      Append_Hex (Buf, Last, FlashProg.App_Length);
      Emit ("INFO", Buf (1 .. Last));
   end Log_Layout;

   type View is record
      IO     : Boolean := False;
      CRC    : Unsigned_32 := 0;
      Match  : Boolean := False;
      SP     : Unsigned_32 := 0;
      Reset  : Unsigned_32 := 0;
   end record;

   function Inspect (Payload : Unsigned_32) return View is
      Result  : View;
      Acc     : CRC32.Accumulator;
      Chunk   : Bytes.Arr (1 .. 512);
      Head    : Bytes.Arr (1 .. 8) := (others => 0);
      Remain  : Unsigned_32 := Payload;
      Offset  : Unsigned_32 := 0;
      Got     : Natural;
      OK      : Boolean;
      Want    : Natural;
   begin
      FlashProg.Invalidate_Caches;
      FAT.Rewind;
      declare
         Skip : Bytes.Arr (0 .. 31);
      begin
         FAT.Read (Skip, Got, OK);
         if not OK or else Got /= 32 then
            Result.IO := True;
            Result.Match := False;
            return Result;
         end if;
      end;
      CRC32.Reset (Acc);
      Result.Match := True;
      while Remain > 0 loop
         Want := 512;
         if Unsigned_32 (Want) > Remain then
            Want := Natural (Remain);
         end if;
         FAT.Read (Chunk (1 .. Want), Got, OK);
         if not OK or else Got /= Want then
            Result.IO := True;
            Result.Match := False;
            return Result;
         end if;
         CRC32.Append (Acc, Chunk (1 .. Want));
         for I in 1 .. Want loop
            if Offset < 8 then
               Head (Natural (Offset) + 1) := Chunk (I);
            end if;
            if Result.Match
              and then Chunk (I) /=
                FlashProg.Byte_At (FlashProg.App_Origin + Offset)
            then
               Result.Match := False;
            end if;
            Offset := Offset + 1;
         end loop;
         Remain := Remain - Unsigned_32 (Want);
      end loop;
      Result.CRC := CRC32.Finish (Acc);
      Result.SP := Word_Of (Head, 1);
      Result.Reset := Word_Of (Head, 5);
      if Result.Match then
         declare
            Flash_CRC : CRC32.Accumulator;
            Addr      : Unsigned_32 := FlashProg.App_Origin;
            Left      : Unsigned_32 := Payload;
         begin
            CRC32.Reset (Flash_CRC);
            while Left > 0 loop
               declare
                  One : Bytes.Arr (1 .. 1);
               begin
                  One (1) := FlashProg.Byte_At (Addr);
                  CRC32.Append (Flash_CRC, One);
               end;
               Addr := Addr + 1;
               Left := Left - 1;
            end loop;
            Result.Match := CRC32.Finish (Flash_CRC) = Result.CRC;
         end;
      end if;
      return Result;
   end Inspect;

   Hdr     : Bytes.Arr (0 .. 31);
   Got     : Natural;
   OK      : Boolean;
   Payload : Unsigned_32;
   Load_At : Unsigned_32;
   P_CRC   : Unsigned_32;
   H_CRC   : Unsigned_32;
   Acc     : CRC32.Accumulator;
   Seen    : View;
   FStat   : FlashProg.Status;
   Buf     : String (1 .. 40);
   Last    : Natural;

begin
   HW.Initialize;
   HW.Blue (True);
   HW.Put_Line ("sample:type:payload");
   Emit ("INFO", "bootloader");
   Log_Layout;

   if not SDCard.Init then
      Emit ("ERR", "sd_init_failed");
      Start_Application;
   end if;
   if not FAT.Mount then
      Emit ("ERR", "sd_mount_failed");
      Start_Application;
   end if;
   if not FAT.Open ("bootstrap") then
      Emit ("INFO", "no_bootstrap");
      Start_Application;
   end if;

   FAT.Read (Hdr, Got, OK);
   if not OK or else Got /= Hdr'Length then
      Emit ("ERR", "bootstrap_short");
      Start_Application;
   end if;

   CRC32.Reset (Acc);
   CRC32.Append (Acc, Hdr (0 .. 19));
   H_CRC := CRC32.Finish (Acc);

   if Hdr (0 .. 3) /= (Character'Pos ('S'), Character'Pos ('P'),
                       Character'Pos ('B'), Character'Pos ('1'))
   then
      Emit ("ERR", "bootstrap_bad_magic");
      Start_Application;
   end if;

   if Word_Of (Hdr, 4) /= 32
     or else Word_Of (Hdr, 24) /= 0
     or else Word_Of (Hdr, 28) /= 0
     or else H_CRC /= Word_Of (Hdr, 20)
   then
      Emit ("ERR", "bootstrap_bad_header");
      Start_Application;
   end if;

   Load_At := Word_Of (Hdr, 12);
   Payload := Word_Of (Hdr, 8);
   P_CRC := Word_Of (Hdr, 16);

   if Load_At /= FlashProg.App_Origin then
      Emit ("ERR", "bootstrap_bad_address");
      Start_Application;
   end if;
   if Payload < 8 or else Payload > FlashProg.App_Length
     or else FAT.Size /= 32 + Payload
   then
      Emit ("ERR", "bootstrap_bad_length");
      Start_Application;
   end if;

   Seen := Inspect (Payload);
   if Seen.IO then
      Emit ("ERR", "bootstrap_io");
      Start_Application;
   end if;
   if Seen.CRC /= P_CRC then
      Emit ("ERR", "bootstrap_bad_crc");
      Start_Application;
   end if;

   declare
      Target : constant Unsigned_32 := Seen.Reset and 16#FFFF_FFFE#;
   begin
      if Seen.SP < 16#2000_0008# or else Seen.SP > 16#2002_0000#
        or else Seen.SP mod 8 /= 0 or else Seen.Reset mod 2 = 0
        or else Target < FlashProg.App_Origin
        or else Target >= FlashProg.App_Origin + Payload
      then
         Emit ("ERR", "bootstrap_bad_vector");
         Start_Application;
      end if;
   end;

   Last := 0;
   Append (Buf, Last, "bootstrap_ok:");
   Append_Hex (Buf, Last, Payload);
   Append (Buf, Last, ":");
   Append_Hex (Buf, Last, Seen.CRC);
   Emit ("INFO", Buf (1 .. Last));

   if Seen.Match then
      Emit ("INFO", "already_programmed");
      if FAT.Delete then
         Emit ("INFO", "bootstrap_deleted");
      else
         Emit ("ERR", "delete_failed");
      end if;
      Start_Application;
   end if;

   --  The file is valid and flash does not already hold it. Erasing from
   --  here destroys the old application. Failures halt and keep the file.
   HW.Orange (True);
   Emit ("INFO", "erase");
   FlashProg.Erase (FlashProg.App_Origin, Payload, FStat);
   if FStat /= FlashProg.OK then
      Emit ("ERR", "erase_failed");
      Halt;
   end if;

   Emit ("INFO", "program");
   FlashProg.Begin_Program (FStat);
   if FStat /= FlashProg.OK then
      Emit ("ERR", "program_failed");
      Halt;
   end if;

   FAT.Rewind;
   declare
      Skip  : Bytes.Arr (0 .. 31);
      Chunk : Bytes.Arr (1 .. 512);
      Off   : Unsigned_32 := 0;
      Left  : Unsigned_32 := Payload;
      Want  : Natural;
   begin
      FAT.Read (Skip, Got, OK);
      if not OK or else Got /= 32 then
         FlashProg.End_Program;
         Emit ("ERR", "program_failed");
         Halt;
      end if;
      while Left > 0 loop
         Want := 512;
         if Unsigned_32 (Want) > Left then
            Want := Natural (Left);
         end if;
         FAT.Read (Chunk (1 .. Want), Got, OK);
         if not OK or else Got /= Want then
            FlashProg.End_Program;
            Emit ("ERR", "program_failed");
            Halt;
         end if;
         FlashProg.Program (FlashProg.App_Origin + Off, Chunk (1 .. Want), FStat);
         if FStat /= FlashProg.OK then
            FlashProg.End_Program;
            Emit ("ERR", "program_failed");
            Halt;
         end if;
         Off := Off + Unsigned_32 (Want);
         Left := Left - Unsigned_32 (Want);
      end loop;
   end;
   FlashProg.End_Program;

   Seen := Inspect (Payload);
   if Seen.IO or else not Seen.Match or else Seen.CRC /= P_CRC then
      Emit ("ERR", "verify_failed");
      Halt;
   end if;
   Emit ("INFO", "verify_ok");
   HW.Orange (False);

   if FAT.Delete then
      Emit ("INFO", "bootstrap_deleted");
   else
      Emit ("ERR", "delete_failed");
   end if;
   Start_Application;
end Bootloader;

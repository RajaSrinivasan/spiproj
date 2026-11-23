with Ada.Real_Time; use Ada.Real_Time;

with STM32.Device; use STM32.Device;
with STM32.SPI;    use STM32.SPI;

with SPI_Bus;

package body SD_SPI is

   R1_Idle            : constant UInt8 := 16#01#;
   R1_Illegal_Command : constant UInt8 := 16#04#;
   R1_CRC_Error       : constant UInt8 := 16#08#;
   Start_Block_Token  : constant UInt8 := 16#FE#;
   Data_Accepted_Mask : constant UInt8 := 16#1F#;
   Data_Accepted      : constant UInt8 := 16#05#;

   CMD0   : constant UInt8 := 0;
   CMD8   : constant UInt8 := 8;
   CMD9   : constant UInt8 := 9;
   CMD16  : constant UInt8 := 16;
   CMD17  : constant UInt8 := 17;
   CMD24  : constant UInt8 := 24;
   CMD55  : constant UInt8 := 55;
   CMD58  : constant UInt8 := 58;
   ACMD41 : constant UInt8 := 41;

   HCS_Arg      : constant UInt32 := 16#4000_0000#;
   CMD8_Arg     : constant UInt32 := 16#0000_01AA#;
   CMD8_Pattern : constant UInt32 := 16#0000_01AA#;

   procedure Delay_Ms (Ms : Natural);
   function Transfer (Outgoing : UInt8) return UInt8;
   procedure Dummy_Clocks (Count : Positive);
   procedure Release_Bus;
   function CRC7 (Data : UInt8_Array) return UInt8;
   function Send_Command (Cmd : UInt8; Arg : UInt32) return UInt8;
   function Read_UInt32 return UInt32;
   function Wait_For_Token
     (Token : UInt8; Budget : Time_Span) return Boolean;
   function Wait_Until_Not_Busy (Budget : Time_Span) return Boolean;
   function Command_Address
     (This : SD_Card; Block_Number : UInt64) return UInt32;
   procedure Read_CSD (This : in out SD_Card);
   function R1_To_Status (R1 : UInt8) return SD_Status;

   --------------
   -- Delay_Ms --
   --------------

   procedure Delay_Ms (Ms : Natural) is
      Deadline : constant Time := Clock + Milliseconds (Ms);
   begin
      while Clock < Deadline loop
         null;
      end loop;
   end Delay_Ms;

   --------------
   -- Transfer --
   --------------

   function Transfer (Outgoing : UInt8) return UInt8 is
      Incoming : UInt8;
   begin
      Transmit_Receive (SPI_2, Outgoing, Incoming);
      return Incoming;
   end Transfer;

   ------------------
   -- Dummy_Clocks --
   ------------------

   procedure Dummy_Clocks (Count : Positive) is
      Dummy : UInt8;
      pragma Unreferenced (Dummy);
   begin
      for I in 1 .. Count loop
         Dummy := Transfer (16#FF#);
      end loop;
   end Dummy_Clocks;

   -----------------
   -- Release_Bus --
   -----------------

   procedure Release_Bus is
   begin
      SPI_Bus.Deselect_SD;
      Dummy_Clocks (1);
   end Release_Bus;

   ----------
   -- CRC7 --
   ----------

   function CRC7 (Data : UInt8_Array) return UInt8 is
      CRC : UInt8 := 0;
   begin
      --  CRC-7 with polynomial x^7 + x^3 + 1. The value returned is the
      --  7-bit CRC left-shifted by one with the stop bit set, which is
      --  the last command byte (CMD0 -> 16#95#, CMD8 -> 16#87#).
      for B of Data loop
         for I in reverse Natural range 0 .. 7 loop
            declare
               Bit : constant Boolean :=
                 (Shift_Right (B, I) and 1) /=
                 (Shift_Right (CRC, 6) and 1);
            begin
               CRC := Shift_Left (CRC, 1) and 16#7F#;
               if Bit then
                  CRC := CRC xor 16#09#;
               end if;
            end;
         end loop;
      end loop;
      return Shift_Left (CRC, 1) or 1;
   end CRC7;

   ------------------
   -- Send_Command --
   ------------------

   function Send_Command (Cmd : UInt8; Arg : UInt32) return UInt8 is
      Frame : UInt8_Array (1 .. 6);
      R1    : UInt8;
   begin
      Frame (1) := 16#40# or Cmd;
      Frame (2) := UInt8 (Shift_Right (Arg, 24));
      Frame (3) := UInt8 (Shift_Right (Arg, 16) and 16#FF#);
      Frame (4) := UInt8 (Shift_Right (Arg, 8) and 16#FF#);
      Frame (5) := UInt8 (Arg and 16#FF#);
      Frame (6) := CRC7 (Frame (1 .. 5));

      SPI_Bus.Select_SD;
      Dummy_Clocks (1);
      for I in Frame'Range loop
         declare
            Ignored : constant UInt8 := Transfer (Frame (I));
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end loop;

      for Try in 1 .. 64 loop
         R1 := Transfer (16#FF#);
         if (R1 and 16#80#) = 0 then
            return R1;
         end if;
      end loop;

      return 16#FF#;
   end Send_Command;

   ----------------
   -- Read_UInt32 --
   ----------------

   function Read_UInt32 return UInt32 is
      Value : UInt32 := 0;
   begin
      for I in 1 .. 4 loop
         Value := Shift_Left (Value, 8) or UInt32 (Transfer (16#FF#));
      end loop;
      return Value;
   end Read_UInt32;

   --------------------
   -- Wait_For_Token --
   --------------------

   function Wait_For_Token
     (Token : UInt8; Budget : Time_Span) return Boolean
   is
      Deadline : constant Time := Clock + Budget;
      Byte     : UInt8;
   begin
      while Clock < Deadline loop
         Byte := Transfer (16#FF#);
         if Byte = Token then
            return True;
         end if;
         --  A data-error token is 0000xxxx (CRC / ECC / range). Treat
         --  any non-0xFF value other than the start token as a failure
         --  rather than spinning out the timeout.
         if Byte /= 16#FF# then
            return False;
         end if;
      end loop;
      return False;
   end Wait_For_Token;

   -------------------------
   -- Wait_Until_Not_Busy --
   -------------------------

   function Wait_Until_Not_Busy (Budget : Time_Span) return Boolean is
      Deadline : constant Time := Clock + Budget;
   begin
      while Clock < Deadline loop
         if Transfer (16#FF#) = 16#FF# then
            return True;
         end if;
      end loop;
      return False;
   end Wait_Until_Not_Busy;

   ----------------------
   -- Command_Address --
   ----------------------

   function Command_Address
     (This : SD_Card; Block_Number : UInt64) return UInt32
   is
   begin
      if This.Block_Addr then
         return UInt32 (Block_Number);
      else
         return UInt32 (Block_Number * 512);
      end if;
   end Command_Address;

   ------------------
   -- R1_To_Status --
   ------------------

   function R1_To_Status (R1 : UInt8) return SD_Status is
   begin
      if R1 = 16#FF# then
         return Timeout;
      elsif (R1 and R1_CRC_Error) /= 0 then
         return CRC_Error;
      elsif (R1 and R1_Illegal_Command) /= 0 then
         return Illegal_Command;
      elsif R1 = 0 then
         return OK;
      else
         return Unexpected_Response;
      end if;
   end R1_To_Status;

   --------------
   -- Read_CSD --
   --------------

   procedure Read_CSD (This : in out SD_Card) is
      R1   : UInt8;
      CSD  : UInt8_Array (0 .. 15);
      Dummy : UInt8;
      pragma Unreferenced (Dummy);
   begin
      This.Blocks := 0;
      R1 := Send_Command (CMD9, 0);
      if R1 /= 0 then
         Release_Bus;
         return;
      end if;

      if not Wait_For_Token (Start_Block_Token, Milliseconds (100)) then
         Release_Bus;
         return;
      end if;

      for I in CSD'Range loop
         CSD (I) := Transfer (16#FF#);
      end loop;
      Dummy := Transfer (16#FF#);  --  CRC16
      Dummy := Transfer (16#FF#);
      Release_Bus;

      --  CSD bit 127 is the first bit of CSD (0). Structure version is
      --  bits 127:126, the top two bits of CSD (0).
      if (Shift_Right (CSD (0), 6) and 2#11#) = 1 then
         --  CSD v2 (SDHC/SDXC): C_SIZE is bits 69:48.
         declare
            C_Size : constant UInt32 :=
              Shift_Left (UInt32 (CSD (7) and 16#3F#), 16)
              or Shift_Left (UInt32 (CSD (8)), 8)
              or UInt32 (CSD (9));
         begin
            This.Blocks := (UInt64 (C_Size) + 1) * 1024;
         end;
      else
         --  CSD v1 (SDSC).
         declare
            Read_Bl_Len : constant Natural :=
              Natural (CSD (5) and 16#0F#);
            C_Size      : constant UInt32 :=
              Shift_Left (UInt32 (CSD (6) and 16#03#), 10)
              or Shift_Left (UInt32 (CSD (7)), 2)
              or Shift_Right (UInt32 (CSD (8)), 6);
            C_Size_Mult : constant Natural :=
              Natural (Shift_Left (CSD (9) and 16#03#, 1)
                       or Shift_Right (CSD (10), 7));
            Capacity    : constant UInt64 :=
              (UInt64 (C_Size) + 1)
              * UInt64 (2 ** (C_Size_Mult + 2))
              * UInt64 (2 ** Read_Bl_Len);
         begin
            This.Blocks := Capacity / 512;
         end;
      end if;
   end Read_CSD;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (This : in out SD_Card; Status : out SD_Status) is
      R1      : UInt8;
      OCR     : UInt32;
      Version : Natural := 2;
      Arg     : UInt32;
   begin
      This.Ready      := False;
      This.Block_Addr := False;
      This.Blocks     := 0;

      --  Start (or return) at the slow init rate.
      SPI_Bus.Set_Prescaler (BRP_128);
      SPI_Bus.Deselect_SD;

      Delay_Ms (2);

      --  At least 74 clocks with CS high and DI held high (0xFF).
      Dummy_Clocks (10);

      R1 := 16#FF#;
      for Attempt in 1 .. 10 loop
         R1 := Send_Command (CMD0, 0);
         Release_Bus;
         exit when R1 = R1_Idle;
         Delay_Ms (10);
      end loop;

      if R1 /= R1_Idle then
         Status := R1_To_Status (R1);
         if Status = OK then
            Status := Unexpected_Response;
         end if;
         This.Last := Status;
         return;
      end if;

      R1 := Send_Command (CMD8, CMD8_Arg);
      if R1 = 16#FF# then
         Release_Bus;
         Status := Timeout;
         This.Last := Status;
         return;
      elsif (R1 and R1_Illegal_Command) /= 0 then
         --  SDv1 / standard-capacity card that does not implement CMD8.
         Release_Bus;
         Version := 1;
      else
         OCR := Read_UInt32;
         Release_Bus;
         if (OCR and 16#0FFF#) /= CMD8_Pattern then
            Status := Unexpected_Response;
            This.Last := Status;
            return;
         end if;
         Version := 2;
      end if;

      if Version = 2 then
         Arg := HCS_Arg;
      else
         Arg := 0;
      end if;

      declare
         Deadline : constant Time := Clock + Milliseconds (1000);
         Ready    : Boolean := False;
      begin
         while Clock < Deadline loop
            R1 := Send_Command (CMD55, 0);
            Release_Bus;
            if R1 = 16#FF# then
               Status := Timeout;
               This.Last := Status;
               return;
            end if;

            R1 := Send_Command (ACMD41, Arg);
            Release_Bus;
            if R1 = 0 then
               Ready := True;
               exit;
            elsif R1 = 16#FF# then
               Status := Timeout;
               This.Last := Status;
               return;
            elsif (R1 and R1_Illegal_Command) /= 0 then
               Status := Unsupported_Card;
               This.Last := Status;
               return;
            end if;
            Delay_Ms (10);
         end loop;

         if not Ready then
            Status := Timeout;
            This.Last := Status;
            return;
         end if;
      end;

      R1 := Send_Command (CMD58, 0);
      if R1 = 16#FF# then
         Release_Bus;
         Status := Timeout;
         This.Last := Status;
         return;
      elsif R1 /= 0 then
         Release_Bus;
         Status := R1_To_Status (R1);
         This.Last := Status;
         return;
      end if;

      OCR := Read_UInt32;
      Release_Bus;

      --  CCS is bit 30 of OCR; set means SDHC/SDXC block addressing.
      This.Block_Addr := Version = 2 and then (OCR and HCS_Arg) /= 0;

      if not This.Block_Addr then
         R1 := Send_Command (CMD16, 512);
         Release_Bus;
         if R1 /= 0 then
            Status := R1_To_Status (R1);
            This.Last := Status;
            return;
         end if;
      end if;

      This.Ready := True;
      Read_CSD (This);

      --  Raise the bus clock now that the card is in transfer state.
      SPI_Bus.Set_Prescaler (BRP_4);

      Status := OK;
      This.Last := Status;
   end Initialize;

   -----------------
   -- Last_Status --
   -----------------

   function Last_Status (This : SD_Card) return SD_Status is
   begin
      return This.Last;
   end Last_Status;

   ----------------------------
   -- Uses_Block_Addressing --
   ----------------------------

   function Uses_Block_Addressing (This : SD_Card) return Boolean is
   begin
      return This.Block_Addr;
   end Uses_Block_Addressing;

   -----------------
   -- Block_Count --
   -----------------

   function Block_Count (This : SD_Card) return UInt64 is
   begin
      return This.Blocks;
   end Block_Count;

   -----------------
   -- Read_Single --
   -----------------

   function Read_Single
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : out UInt8_Array)
      return SD_Status
   is
      R1     : UInt8;
      Dummy  : UInt8;
      Status : SD_Status;
      pragma Unreferenced (Dummy);
   begin
      if not This.Ready then
         This.Last := Not_Initialized;
         return Not_Initialized;
      end if;

      R1 := Send_Command (CMD17, Command_Address (This, Block_Number));
      if R1 /= 0 then
         Release_Bus;
         Status := R1_To_Status (R1);
         This.Last := Status;
         return Status;
      end if;

      if not Wait_For_Token (Start_Block_Token, Milliseconds (200)) then
         Release_Bus;
         This.Last := Token_Error;
         return Token_Error;
      end if;

      for I in Data'Range loop
         Data (I) := Transfer (16#FF#);
      end loop;
      Dummy := Transfer (16#FF#);  --  CRC16, not checked (CRC is off)
      Dummy := Transfer (16#FF#);
      Release_Bus;

      This.Last := OK;
      return OK;
   end Read_Single;

   ------------------
   -- Write_Single --
   ------------------

   function Write_Single
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : UInt8_Array)
      return SD_Status
   is
      R1     : UInt8;
      Token  : UInt8;
      Status : SD_Status;
   begin
      if not This.Ready then
         This.Last := Not_Initialized;
         return Not_Initialized;
      end if;

      R1 := Send_Command (CMD24, Command_Address (This, Block_Number));
      if R1 /= 0 then
         Release_Bus;
         Status := R1_To_Status (R1);
         This.Last := Status;
         return Status;
      end if;

      Dummy_Clocks (1);
      declare
         Ignored : constant UInt8 := Transfer (Start_Block_Token);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
      for I in Data'Range loop
         declare
            Ignored : constant UInt8 := Transfer (Data (I));
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end loop;
      --  Dummy CRC16; the card is not asked to check it (CMD59 off).
      Dummy_Clocks (2);

      Token := 16#FF#;
      for Try in 1 .. 16 loop
         Token := Transfer (16#FF#);
         exit when Token /= 16#FF#;
      end loop;

      if (Token and Data_Accepted_Mask) /= Data_Accepted then
         Release_Bus;
         This.Last := Write_Rejected;
         return Write_Rejected;
      end if;

      if not Wait_Until_Not_Busy (Milliseconds (500)) then
         Release_Bus;
         This.Last := Timeout;
         return Timeout;
      end if;

      Release_Bus;
      This.Last := OK;
      return OK;
   end Write_Single;

   ----------
   -- Read --
   ----------

   function Read
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : out Block)
      return Boolean
   is
      Offset : Natural := Data'First;
      Index  : UInt64 := Block_Number;
   begin
      while Offset <= Data'Last loop
         if Read_Single
           (This, Index, Data (Offset .. Offset + Block_Size - 1)) /= OK
         then
            return False;
         end if;
         Offset := Offset + Block_Size;
         Index  := Index + 1;
      end loop;
      return True;
   end Read;

   -----------
   -- Write --
   -----------

   function Write
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : Block)
      return Boolean
   is
      Offset : Natural := Data'First;
      Index  : UInt64 := Block_Number;
   begin
      while Offset <= Data'Last loop
         if Write_Single
           (This, Index, Data (Offset .. Offset + Block_Size - 1)) /= OK
         then
            return False;
         end if;
         Offset := Offset + Block_Size;
         Index  := Index + 1;
      end loop;
      return True;
   end Write;

end SD_SPI;

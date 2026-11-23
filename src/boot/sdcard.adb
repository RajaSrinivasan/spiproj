with System;

with HW;

package body SDCard is

   SPI2  : constant Unsigned_32 := 16#4000_3800#;
   GPIOB : constant Unsigned_32 := 16#4002_0400#;

   Block_Addr : Boolean := False;

   function R32 (Addr : Unsigned_32) return Unsigned_32 is
      V : Unsigned_32 with Volatile, Import, Address =>
        System'To_Address (Addr);
   begin
      return V;
   end R32;

   procedure W32 (Addr, Value : Unsigned_32) is
      V : Unsigned_32 with Volatile, Import, Address =>
        System'To_Address (Addr);
   begin
      V := Value;
   end W32;

   function DR return Unsigned_8 is
      V : Unsigned_8 with Volatile, Import, Address =>
        System'To_Address (SPI2 + 12);
   begin
      return V;
   end DR;

   procedure Set_DR (Value : Unsigned_8) is
      V : Unsigned_8 with Volatile, Import, Address =>
        System'To_Address (SPI2 + 12);
   begin
      V := Value;
   end Set_DR;

   procedure CS (Asserted : Boolean) is
   begin
      if Asserted then
         W32 (GPIOB + 16#18#, Shift_Left (1, 28));
      else
         W32 (GPIOB + 16#18#, Shift_Left (1, 12));
      end if;
   end CS;

   procedure Prescale (Div_Code : Unsigned_32) is
      CR1 : Unsigned_32 := R32 (SPI2) and not 16#40#;
   begin
      W32 (SPI2, CR1);
      CR1 := (CR1 and not 16#38#) or Shift_Left (Div_Code, 3) or 16#40#;
      W32 (SPI2, CR1);
   end Prescale;

   function Transfer (Outgoing : Unsigned_8) return Unsigned_8 is
      Spins : Natural := 0;
   begin
      while (R32 (SPI2 + 8) and 2) = 0 loop
         Spins := Spins + 1;
         if Spins > 100_000 then
            return 16#FF#;
         end if;
      end loop;
      Set_DR (Outgoing);
      Spins := 0;
      while (R32 (SPI2 + 8) and 1) = 0 loop
         Spins := Spins + 1;
         if Spins > 100_000 then
            return 16#FF#;
         end if;
      end loop;
      return DR;
   end Transfer;

   procedure Clocks (Count : Natural) is
      Ignore : Unsigned_8;
   begin
      for I in 1 .. Count loop
         Ignore := Transfer (16#FF#);
      end loop;
   end Clocks;

   procedure Release is
   begin
      CS (False);
      Clocks (1);
   end Release;

   function CRC7 (Cmd : Unsigned_8; Arg : Unsigned_32) return Unsigned_8 is
      Frame : array (0 .. 4) of Unsigned_8;
      CRC   : Unsigned_8 := 0;
   begin
      Frame (0) := 16#40# or Cmd;
      Frame (1) := Unsigned_8 (Shift_Right (Arg, 24));
      Frame (2) := Unsigned_8 (Shift_Right (Arg, 16) and 16#FF#);
      Frame (3) := Unsigned_8 (Shift_Right (Arg, 8) and 16#FF#);
      Frame (4) := Unsigned_8 (Arg and 16#FF#);
      for B of Frame loop
         for Bit in reverse 0 .. 7 loop
            declare
               Hi : constant Unsigned_8 :=
                 Shift_Right (B, Bit) xor Shift_Right (CRC, 6);
            begin
               CRC := Shift_Left (CRC, 1) and 16#7F#;
               if (Hi and 1) /= 0 then
                  CRC := CRC xor 16#09#;
               end if;
            end;
         end loop;
      end loop;
      return Shift_Left (CRC, 1) or 1;
   end CRC7;

   function Command (Cmd : Unsigned_8; Arg : Unsigned_32) return Unsigned_8 is
      R1 : Unsigned_8;
   begin
      CS (True);
      Clocks (1);
      R1 := Transfer (16#40# or Cmd);
      R1 := Transfer (Unsigned_8 (Shift_Right (Arg, 24)));
      R1 := Transfer (Unsigned_8 (Shift_Right (Arg, 16) and 16#FF#));
      R1 := Transfer (Unsigned_8 (Shift_Right (Arg, 8) and 16#FF#));
      R1 := Transfer (Unsigned_8 (Arg and 16#FF#));
      R1 := Transfer (CRC7 (Cmd, Arg));
      for Try in 1 .. 64 loop
         R1 := Transfer (16#FF#);
         if (R1 and 16#80#) = 0 then
            return R1;
         end if;
      end loop;
      return 16#FF#;
   end Command;

   function Read_Word return Unsigned_32 is
      V : Unsigned_32 := 0;
   begin
      for I in 1 .. 4 loop
         V := Shift_Left (V, 8) or Unsigned_32 (Transfer (16#FF#));
      end loop;
      return V;
   end Read_Word;

   function Wait_Token (Limit : Natural) return Boolean is
      B : Unsigned_8;
   begin
      for I in 1 .. Limit loop
         B := Transfer (16#FF#);
         if B = 16#FE# then
            return True;
         end if;
         if B /= 16#FF# then
            return False;
         end if;
      end loop;
      return False;
   end Wait_Token;

   function Wait_Ready (Limit : Natural) return Boolean is
   begin
      for I in 1 .. Limit loop
         if Transfer (16#FF#) = 16#FF# then
            return True;
         end if;
      end loop;
      return False;
   end Wait_Ready;

   function Address_Of (LBA : Unsigned_32) return Unsigned_32 is
   begin
      if Block_Addr then
         return LBA;
      else
         return LBA * 512;
      end if;
   end Address_Of;

   ----------
   -- Init --
   ----------

   function Init return Boolean is
      R1  : Unsigned_8;
      OCR : Unsigned_32;
      V2  : Boolean := True;
   begin
      Block_Addr := False;
      Prescale (6);
      CS (False);
      HW.Wait_Ms (2);
      Clocks (10);

      R1 := 16#FF#;
      for Attempt in 1 .. 10 loop
         R1 := Command (0, 0);
         Release;
         exit when R1 = 1;
         HW.Wait_Ms (10);
      end loop;
      if R1 /= 1 then
         return False;
      end if;

      R1 := Command (8, 16#1AA#);
      if R1 = 16#FF# then
         Release;
         return False;
      elsif (R1 and 4) /= 0 then
         Release;
         V2 := False;
      else
         OCR := Read_Word;
         Release;
         if (OCR and 16#0FFF#) /= 16#1AA# then
            return False;
         end if;
      end if;

      if V2 then
         OCR := 16#4000_0000#;
      else
         OCR := 0;
      end if;

      for Attempt in 1 .. 100 loop
         R1 := Command (55, 0);
         Release;
         if R1 = 16#FF# then
            return False;
         end if;
         R1 := Command (41, OCR);
         Release;
         exit when R1 = 0;
         if R1 = 16#FF# or else (R1 and 4) /= 0 then
            return False;
         end if;
         HW.Wait_Ms (10);
      end loop;
      if R1 /= 0 then
         return False;
      end if;

      R1 := Command (58, 0);
      if R1 /= 0 then
         Release;
         return False;
      end if;
      OCR := Read_Word;
      Release;
      Block_Addr := V2 and then (OCR and 16#4000_0000#) /= 0;

      if not Block_Addr then
         R1 := Command (16, 512);
         Release;
         if R1 /= 0 then
            return False;
         end if;
      end if;

      Prescale (1);
      return True;
   end Init;

   ----------
   -- Read --
   ----------

   function Read (LBA : Unsigned_32; Data : out Block) return Boolean is
      R1 : Unsigned_8;
   begin
      R1 := Command (17, Address_Of (LBA));
      if R1 /= 0 or else not Wait_Token (400_000) then
         Release;
         return False;
      end if;
      for I in Data'Range loop
         Data (I) := Transfer (16#FF#);
      end loop;
      Clocks (2);
      Release;
      return True;
   end Read;

   -----------
   -- Write --
   -----------

   function Write (LBA : Unsigned_32; Data : Block) return Boolean is
      R1    : Unsigned_8;
      Token : Unsigned_8 := 16#FF#;
   begin
      R1 := Command (24, Address_Of (LBA));
      if R1 /= 0 then
         Release;
         return False;
      end if;
      Clocks (1);
      R1 := Transfer (16#FE#);
      for I in Data'Range loop
         R1 := Transfer (Data (I));
      end loop;
      Clocks (2);
      for Try in 1 .. 16 loop
         Token := Transfer (16#FF#);
         exit when Token /= 16#FF#;
      end loop;
      if (Token and 16#1F#) /= 16#05# or else not Wait_Ready (1_000_000) then
         Release;
         return False;
      end if;
      Release;
      return True;
   end Write;

end SDCard;

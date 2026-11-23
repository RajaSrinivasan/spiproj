with Bytes;

with System;
with System.Machine_Code; use System.Machine_Code;
with System.Storage_Elements;

with HW;

package body FlashProg is

   FLASH : constant Unsigned_32 := 16#4002_3C00#;

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

   Boot_Origin_Mark : Unsigned_8
     with Import, Convention => C, External_Name => "__boot_origin";
   Boot_Length_Mark : Unsigned_8
     with Import, Convention => C, External_Name => "__boot_length";
   App_Origin_Mark : Unsigned_8
     with Import, Convention => C, External_Name => "__app_origin";
   App_Length_Mark : Unsigned_8
     with Import, Convention => C, External_Name => "__app_length";

   function Addr_Of (Mark : Unsigned_8) return Unsigned_32 is
     (Unsigned_32 (System.Storage_Elements.To_Integer (Mark'Address)));

   function App_Origin return Unsigned_32 is (Addr_Of (App_Origin_Mark));
   function App_Length return Unsigned_32 is (Addr_Of (App_Length_Mark));
   function Boot_Origin return Unsigned_32 is (Addr_Of (Boot_Origin_Mark));
   function Boot_Length return Unsigned_32 is (Addr_Of (Boot_Length_Mark));

   type Sector is record
      Index : Unsigned_32;
      Start : Unsigned_32;
      Size  : Unsigned_32;
   end record;

   Sectors : constant array (0 .. 11) of Sector :=
     ((0,  16#0800_0000#, 16 * 1024),
      (1,  16#0800_4000#, 16 * 1024),
      (2,  16#0800_8000#, 16 * 1024),
      (3,  16#0800_C000#, 16 * 1024),
      (4,  16#0801_0000#, 64 * 1024),
      (5,  16#0802_0000#, 128 * 1024),
      (6,  16#0804_0000#, 128 * 1024),
      (7,  16#0806_0000#, 128 * 1024),
      (8,  16#0808_0000#, 128 * 1024),
      (9,  16#080A_0000#, 128 * 1024),
      (10, 16#080C_0000#, 128 * 1024),
      (11, 16#080E_0000#, 128 * 1024));

   function In_App (From, Length : Unsigned_32) return Boolean is
      Origin : constant Unsigned_32 := App_Origin;
      Limit  : constant Unsigned_32 := Origin + App_Length;
   begin
      return Length > 0 and then From >= Origin and then From < Limit
        and then Length <= Limit - From;
   end In_App;

   function Hits_Boot (Start, Size : Unsigned_32) return Boolean is
      Boot_End : constant Unsigned_32 := Boot_Origin + Boot_Length;
   begin
      return Size > 0 and then Start < Boot_End
        and then Start + Size > Boot_Origin;
   end Hits_Boot;

   function Overlaps
     (Start, Size, From, To : Unsigned_32) return Boolean
   is
   begin
      return Size > 0 and then Start < To and then Start + Size > From;
   end Overlaps;

   function Unlock return Boolean is
   begin
      if (R32 (FLASH + 16#10#) and 16#8000_0000#) = 0 then
         return True;
      end if;
      W32 (FLASH + 4, 16#4567_0123#);
      W32 (FLASH + 4, 16#CDEF_89AB#);
      return (R32 (FLASH + 16#10#) and 16#8000_0000#) = 0;
   end Unlock;

   procedure Lock is
   begin
      W32 (FLASH + 16#10#, 16#8000_0000#);
   end Lock;

   procedure Clear_Status is
   begin
      W32 (FLASH + 16#0C#, 16#0000_00F3#);
   end Clear_Status;

   function Fault return Boolean is
     ((R32 (FLASH + 16#0C#) and 16#0000_00F2#) /= 0);

   function Wait (Cycles : Unsigned_32) return Boolean is
      Start : constant Unsigned_32 := HW.Cycles;
   begin
      loop
         if (R32 (FLASH + 16#0C#) and 16#0001_0000#) = 0 then
            return not Fault;
         end if;
         exit when HW.Cycles - Start >= Cycles;
      end loop;
      return False;
   end Wait;

   procedure Store (Address, Value : Unsigned_32) is
   begin
      Asm ("str %0, [%1]",
           Inputs   =>
             (Unsigned_32'Asm_Input ("r", Value),
              System.Address'Asm_Input
                ("r", System'To_Address (Address))),
           Volatile => True);
   end Store;

   ------------------------
   -- Invalidate_Caches --
   ------------------------

   procedure Invalidate_Caches is
      ACR : Unsigned_32 := R32 (FLASH);
   begin
      ACR := ACR and not 16#0600#;
      W32 (FLASH, ACR);
      W32 (FLASH, ACR or 16#1800#);
   end Invalidate_Caches;

   function Word_At (Address : Unsigned_32) return Unsigned_32 is
      V : Unsigned_32 with Volatile, Import, Address =>
        System'To_Address (Address);
   begin
      return V;
   end Word_At;

   function Byte_At (Address : Unsigned_32) return Unsigned_8 is
      V : Unsigned_8 with Volatile, Import, Address =>
        System'To_Address (Address);
   begin
      return V;
   end Byte_At;

   -----------
   -- Erase --
   -----------

   procedure Erase
     (From    : Unsigned_32;
      Length  : Unsigned_32;
      Outcome : out Status)
   is
      To : Unsigned_32;
   begin
      Outcome := OK;
      if not In_App (From, Length) then
         Outcome := Rejected;
         return;
      end if;
      To := From + Length;
      for S of Sectors loop
         if Overlaps (S.Start, S.Size, From, To)
           and then Hits_Boot (S.Start, S.Size)
         then
            Outcome := Rejected;
            return;
         end if;
      end loop;

      Clear_Status;
      if not Wait (16_800_000) or else not Unlock then
         Outcome := Failed;
         return;
      end if;

      for S of Sectors loop
         if Overlaps (S.Start, S.Size, From, To) then
            Clear_Status;
            --  PSIZE x32, SER, SNB, STRT. LOCK stays clear.
            W32 (FLASH + 16#10#,
                 16#0001_0002# or Shift_Left (S.Index, 3) or
                 Shift_Left (Unsigned_32'(2), 8));
            if not Wait (840_000_000) then
               Lock;
               Outcome := Failed;
               return;
            end if;
         end if;
      end loop;
      Lock;
   end Erase;

   -------------------
   -- Begin_Program --
   -------------------

   procedure Begin_Program (Outcome : out Status) is
   begin
      Clear_Status;
      if not Wait (16_800_000) or else not Unlock then
         Outcome := Failed;
         return;
      end if;
      Outcome := OK;
   end Begin_Program;

   -------------
   -- Program --
   -------------

   procedure Program
     (Address : Unsigned_32;
      Data    : Bytes.Arr;
      Outcome : out Status)
   is
      Padded : constant Natural := ((Data'Length + 3) / 4) * 4;
      Cursor : Natural := Data'First;
      Addr   : Unsigned_32 := Address;
      Word   : Unsigned_32;
   begin
      Outcome := OK;
      if Data'Length = 0 then
         return;
      end if;
      if Address mod 4 /= 0
        or else not In_App (Address, Unsigned_32 (Padded))
      then
         Lock;
         Outcome := Rejected;
         return;
      end if;

      while Cursor <= Data'Last loop
         Word := 16#FFFF_FFFF#;
         for I in 0 .. 3 loop
            exit when Cursor > Data'Last;
            declare
               Piece : Unsigned_32 := Unsigned_32 (Data (Cursor));
               Mask  : Unsigned_32 := 16#FF#;
            begin
               for S in 1 .. I loop
                  Piece := Piece * 256;
                  Mask := Mask * 256;
               end loop;
               Word := (Word and not Mask) or Piece;
            end;
            Cursor := Cursor + 1;
         end loop;

         Clear_Status;
         W32 (FLASH + 16#10#, 16#0000_0201#);
         Store (Addr, Word);
         if not Wait (16_800_000) then
            Lock;
            Outcome := Failed;
            return;
         end if;
         Addr := Addr + 4;
      end loop;
   end Program;

   -----------------
   -- End_Program --
   -----------------

   procedure End_Program is
   begin
      Lock;
   end End_Program;

end FlashProg;

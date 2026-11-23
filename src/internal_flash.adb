with Ada.Real_Time; use Ada.Real_Time;

with System.Machine_Code; use System.Machine_Code;
with System.Storage_Elements;

with STM32_SVD.FLASH;

with Flash_Layout;

package body Internal_Flash is

   FLASH : STM32_SVD.FLASH.FLASH_Peripheral
     renames STM32_SVD.FLASH.FLASH_Periph;

   Key_1 : constant UInt32 := 16#4567_0123#;
   Key_2 : constant UInt32 := 16#CDEF_89AB#;

   --  x32 parallelism. RM0090 requires this at VDD 2.7 V .. 3.6 V.
   PSIZE_Word : constant STM32_SVD.FLASH.CR_PSIZE_Field := 2;

   Sector_Erase_Budget : constant Time_Span := Seconds (5);
   Word_Budget         : constant Time_Span := Milliseconds (100);

   type Sector is record
      Index : STM32_SVD.FLASH.CR_SNB_Field;
      Start : UInt32;
      Size  : UInt32;
   end record;

   --  STM32F407VG single-bank map. Sizes are the erase granularity.
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

   function To_Address (Address : UInt32) return System.Address is
     (System.Storage_Elements.To_Address
        (System.Storage_Elements.Integer_Address (Address)));

   function In_Application (From : UInt32; Length : UInt32) return Boolean;
   function Hits_Bootloader (Start : UInt32; Size : UInt32) return Boolean;
   function Overlaps
     (Start : UInt32;
      Size  : UInt32;
      From  : UInt32;
      To    : UInt32) return Boolean;

   function Unlock return Boolean;
   procedure Lock;
   procedure Clear_Status;
   function Fault return Boolean;
   function Wait_Ready (Budget : Time_Span) return Boolean;
   procedure Store (Address : UInt32; Value : UInt32);

   ---------------------
   -- In_Application --
   ---------------------

   function In_Application (From : UInt32; Length : UInt32) return Boolean is
      Origin : constant UInt32 := Flash_Layout.App_Origin;
      Limit  : constant UInt32 := Origin + Flash_Layout.App_Length;
   begin
      return Length > 0
        and then From >= Origin
        and then From < Limit
        and then Length <= Limit - From;
   end In_Application;

   ----------------------
   -- Hits_Bootloader --
   ----------------------

   function Hits_Bootloader (Start : UInt32; Size : UInt32) return Boolean is
      Boot_End : constant UInt32 :=
        Flash_Layout.Boot_Origin + Flash_Layout.Boot_Length;
   begin
      return Size > 0
        and then Start < Boot_End
        and then Start + Size > Flash_Layout.Boot_Origin;
   end Hits_Bootloader;

   --------------
   -- Overlaps --
   --------------

   function Overlaps
     (Start : UInt32;
      Size  : UInt32;
      From  : UInt32;
      To    : UInt32) return Boolean
   is
   begin
      return Size > 0
        and then Start < To
        and then Start + Size > From;
   end Overlaps;

   ------------
   -- Unlock --
   ------------

   function Unlock return Boolean is
   begin
      if not FLASH.CR.LOCK then
         return True;
      end if;
      FLASH.KEYR := Key_1;
      FLASH.KEYR := Key_2;
      return not FLASH.CR.LOCK;
   end Unlock;

   ----------
   -- Lock --
   ----------

   procedure Lock is
      CR : STM32_SVD.FLASH.CR_Register := (others => <>);
   begin
      CR.LOCK := True;
      FLASH.CR := CR;
   end Lock;

   ------------------
   -- Clear_Status --
   ------------------

   procedure Clear_Status is
      SR : STM32_SVD.FLASH.SR_Register := (others => <>);
   begin
      --  Writing 1 clears the flag. BSY is read-only.
      SR.EOP := True;
      SR.OPERR := True;
      SR.WRPERR := True;
      SR.PGAERR := True;
      SR.PGPERR := True;
      SR.PGSERR := True;
      FLASH.SR := SR;
   end Clear_Status;

   -----------
   -- Fault --
   -----------

   function Fault return Boolean is
      SR : constant STM32_SVD.FLASH.SR_Register := FLASH.SR;
   begin
      return SR.OPERR or SR.WRPERR or SR.PGAERR or SR.PGPERR or SR.PGSERR;
   end Fault;

   ----------------
   -- Wait_Ready --
   ----------------

   function Wait_Ready (Budget : Time_Span) return Boolean is
      Deadline : constant Time := Clock + Budget;
   begin
      loop
         if not FLASH.SR.BSY then
            return not Fault;
         end if;
         exit when Clock >= Deadline;
      end loop;
      return False;
   end Wait_Ready;

   -----------
   -- Store --
   -----------

   procedure Store (Address : UInt32; Value : UInt32) is
   begin
      --  A single 32-bit store. PSIZE is x32, so a byte or halfword store
      --  would set a programming error and leave the word unchanged.
      Asm ("str %0, [%1]",
           Inputs   =>
             (UInt32'Asm_Input ("r", Value),
              System.Address'Asm_Input ("r", To_Address (Address))),
           Volatile => True);
   end Store;

   ------------------------
   -- Invalidate_Caches --
   ------------------------

   procedure Invalidate_Caches is
      ACR : STM32_SVD.FLASH.ACR_Register;
   begin
      ACR := FLASH.ACR;
      ACR.DCEN := False;
      ACR.ICEN := False;
      FLASH.ACR := ACR;
      ACR.DCRST := True;
      ACR.ICRST := True;
      FLASH.ACR := ACR;
   end Invalidate_Caches;

   -------------
   -- Word_At --
   -------------

   function Word_At (Address : UInt32) return UInt32 is
      W : UInt32 with Volatile, Import, Address => To_Address (Address);
   begin
      return W;
   end Word_At;

   -------------
   -- Byte_At --
   -------------

   function Byte_At (Address : UInt32) return UInt8 is
      B : UInt8 with Volatile, Import, Address => To_Address (Address);
   begin
      return B;
   end Byte_At;

   -----------
   -- Erase --
   -----------

   procedure Erase
     (From    : UInt32;
      Length  : UInt32;
      Outcome : out Status)
   is
      To : UInt32;
   begin
      Outcome := OK;

      if not In_Application (From, Length) then
         Outcome := Protected_Region;
         return;
      end if;

      To := From + Length;

      Clear_Status;

      for S of Sectors loop
         if Overlaps (S.Start, S.Size, From, To)
           and then Hits_Bootloader (S.Start, S.Size)
         then
            Outcome := Protected_Region;
            return;
         end if;
      end loop;

      if not Wait_Ready (Word_Budget) then
         Outcome := (if Fault then Operation_Error else Timeout);
         return;
      end if;

      if not Unlock then
         Outcome := Locked;
         return;
      end if;

      for S of Sectors loop
         if Overlaps (S.Start, S.Size, From, To) then
            Clear_Status;
            declare
               CR : STM32_SVD.FLASH.CR_Register := (others => <>);
            begin
               CR.LOCK := False;
               CR.PSIZE := PSIZE_Word;
               CR.SER := True;
               CR.SNB := S.Index;
               CR.STRT := True;
               FLASH.CR := CR;
            end;

            if not Wait_Ready (Sector_Erase_Budget) then
               Lock;
               Outcome := (if Fault then Operation_Error else Timeout);
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

      if not Wait_Ready (Word_Budget) then
         Outcome := (if Fault then Operation_Error else Timeout);
         return;
      end if;

      if not Unlock then
         Outcome := Locked;
         return;
      end if;

      Outcome := OK;
   end Begin_Program;

   ------------------
   -- Program_Block --
   ------------------

   procedure Program_Block
     (Address : UInt32;
      Data    : UInt8_Array;
      Outcome : out Status)
   is
      Padded : constant Natural := ((Data'Length + 3) / 4) * 4;
      Cursor : Natural := Data'First;
      Addr   : UInt32 := Address;
   begin
      Outcome := OK;

      if Data'Length = 0 then
         return;
      end if;

      if Address mod 4 /= 0 then
         Outcome := Misaligned;
         Lock;
         return;
      end if;

      if not In_Application (Address, UInt32 (Padded)) then
         Outcome := Protected_Region;
         Lock;
         return;
      end if;

      while Cursor <= Data'Last loop
         declare
            Word : UInt32 := 16#FFFF_FFFF#;
         begin
            for I in 0 .. 3 loop
               exit when Cursor > Data'Last;
               declare
                  Piece : UInt32 := UInt32 (Data (Cursor));
                  Mask  : UInt32 := 16#0000_00FF#;
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
            declare
               CR : STM32_SVD.FLASH.CR_Register := (others => <>);
            begin
               CR.LOCK := False;
               CR.PSIZE := PSIZE_Word;
               CR.PG := True;
               FLASH.CR := CR;
            end;

            Store (Addr, Word);

            if not Wait_Ready (Word_Budget) then
               Lock;
               Outcome := (if Fault then Operation_Error else Timeout);
               return;
            end if;
         end;
         Addr := Addr + 4;
      end loop;
   end Program_Block;

   -----------------
   -- End_Program --
   -----------------

   procedure End_Program is
   begin
      Lock;
   end End_Program;

end Internal_Flash;

with System;
with System.Machine_Code; use System.Machine_Code;

with FlashProg;
with HW;

package body StartApp is

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

   function Switch_To_HSI return Boolean is
      RCC   : constant Unsigned_32 := 16#4002_3800#;
      Spins : Natural := 0;

      function Stuck return Boolean is
      begin
         Spins := Spins + 1;
         return Spins > 1_000_000;
      end Stuck;

   begin
      W32 (RCC, R32 (RCC) or 1);
      while (R32 (RCC) and 2) = 0 loop
         if Stuck then
            return False;
         end if;
      end loop;

      W32 (RCC + 8, R32 (RCC + 8) and not 3);
      Spins := 0;
      while (R32 (RCC + 8) and 16#0C#) /= 0 loop
         if Stuck then
            return False;
         end if;
      end loop;

      W32 (16#4002_3C00#, R32 (16#4002_3C00#) and not 7);
      W32 (RCC, R32 (RCC) and not 16#0100_0000#);
      Spins := 0;
      while (R32 (RCC) and 16#0200_0000#) /= 0 loop
         if Stuck then
            return False;
         end if;
      end loop;
      return True;
   end Switch_To_HSI;

   procedure Quiet is
   begin
      W32 (16#E000_E010#, 0);
      W32 (16#E000_ED04#, 16#0A00_0000#);
      for I in 0 .. 7 loop
         W32 (16#E000_E180# + Unsigned_32 (I) * 4, 16#FFFF_FFFF#);
         W32 (16#E000_E280# + Unsigned_32 (I) * 4, 16#FFFF_FFFF#);
      end loop;
   end Quiet;

   procedure Branch (Stack, Entry_Point : Unsigned_32) is
   begin
      Asm
        ("cpsid i" & ASCII.LF &
         "cpsid f" & ASCII.LF &
         "dsb" & ASCII.LF &
         "isb" & ASCII.LF &
         "mrs r2, control" & ASCII.LF &
         "bic r2, r2, #2" & ASCII.LF &
         "msr control, r2" & ASCII.LF &
         "isb" & ASCII.LF &
         "msr msp, %0" & ASCII.LF &
         "dsb" & ASCII.LF &
         "isb" & ASCII.LF &
         "bx %1",
         Inputs   =>
           (Unsigned_32'Asm_Input ("r", Stack),
            Unsigned_32'Asm_Input ("r", Entry_Point)),
         Clobber  => "r2",
         Volatile => True);
      loop
         null;
      end loop;
   end Branch;

   ---------------
   -- Installed --
   ---------------

   function Installed return Boolean is
      Origin : constant Unsigned_32 := FlashProg.App_Origin;
      Limit  : constant Unsigned_32 := Origin + FlashProg.App_Length;
      SP     : Unsigned_32;
      Reset  : Unsigned_32;
      Target : Unsigned_32;
   begin
      FlashProg.Invalidate_Caches;
      SP := FlashProg.Word_At (Origin);
      Reset := FlashProg.Word_At (Origin + 4);
      if SP < 16#2000_0008# or else SP > 16#2002_0000#
        or else SP mod 8 /= 0 or else Reset mod 2 = 0
      then
         return False;
      end if;
      Target := Reset and 16#FFFF_FFFE#;
      return Target >= Origin and then Target < Limit;
   end Installed;

   ----------
   -- Jump --
   ----------

   procedure Jump (Origin : Unsigned_32; Switched : out Boolean) is
   begin
      Quiet;
      Switched := Switch_To_HSI;
      if not Switched then
         return;
      end if;
      FlashProg.Invalidate_Caches;
      W32 (16#E000_ED08#, Origin);
      Branch
        (FlashProg.Word_At (Origin), FlashProg.Word_At (Origin + 4));
   end Jump;

end StartApp;

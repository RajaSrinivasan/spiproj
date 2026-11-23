with System.Machine_Code; use System.Machine_Code;

with Cortex_M.SysTick;
with Cortex_M_SVD.NVIC;
with Cortex_M_SVD.SCB;
with STM32_SVD.FLASH;
with STM32_SVD.RCC;

with Bootstrap_Image;
with Flash_Layout;
with Internal_Flash;

package body App_Jump is

   function Switch_To_HSI return Boolean;
   procedure Quiet_Interrupts;
   procedure Branch (Stack : UInt32; Entry_Point : UInt32);

   -------------------
   -- Switch_To_HSI --
   -------------------

   function Switch_To_HSI return Boolean is
      RCC   : STM32_SVD.RCC.RCC_Peripheral renames STM32_SVD.RCC.RCC_Periph;
      Spins : Natural := 0;

      function Stuck return Boolean is
      begin
         Spins := Spins + 1;
         return Spins > 1_000_000;
      end Stuck;

   begin
      --  Latency stays at the PLL setting until SYSCLK is HSI. Extra wait
      --  states at 16 MHz are legal; too few wait states at 168 MHz are not.
      RCC.CR.HSION := True;
      while not RCC.CR.HSIRDY loop
         if Stuck then
            return False;
         end if;
      end loop;

      RCC.CFGR.SW := 0;
      Spins := 0;
      while RCC.CFGR.SWS /= 0 loop
         if Stuck then
            return False;
         end if;
      end loop;

      STM32_SVD.FLASH.FLASH_Periph.ACR.LATENCY := 0;

      RCC.CR.PLLON := False;
      Spins := 0;
      while RCC.CR.PLLRDY loop
         if Stuck then
            return False;
         end if;
      end loop;

      return True;
   end Switch_To_HSI;

   -----------------------
   -- Quiet_Interrupts --
   -----------------------

   procedure Quiet_Interrupts is
      ICSR : Cortex_M_SVD.SCB.ICSR_Register;
   begin
      Cortex_M.SysTick.Disable;

      ICSR := Cortex_M_SVD.SCB.SCB_Periph.ICSR;
      ICSR.PENDSTCLR := True;
      ICSR.PENDSVCLR := True;
      ICSR.PENDSTSET := False;
      ICSR.PENDSVSET := False;
      ICSR.NMIPENDSET := False;
      Cortex_M_SVD.SCB.SCB_Periph.ICSR := ICSR;

      for I in Cortex_M_SVD.NVIC.NVIC_Periph.NVIC_ICER'Range loop
         Cortex_M_SVD.NVIC.NVIC_Periph.NVIC_ICER (I) := 16#FFFF_FFFF#;
         Cortex_M_SVD.NVIC.NVIC_Periph.NVIC_ICPR (I) := 16#FFFF_FFFF#;
      end loop;
   end Quiet_Interrupts;

   ------------
   -- Branch --
   ------------

   procedure Branch (Stack : UInt32; Entry_Point : UInt32) is
      NL : constant Character := ASCII.LF;
   begin
      --  CONTROL.SPSEL = 0 selects MSP. The Ravenscar runtime has switched
      --  the bootloader to PSP, and the application's reset handler does
      --  not reload MSP itself: hardware does that only on a real reset.
      Asm
        ("cpsid i" & NL &
         "cpsid f" & NL &
         "dsb" & NL &
         "isb" & NL &
         "mrs r2, control" & NL &
         "bic r2, r2, #2" & NL &
         "msr control, r2" & NL &
         "isb" & NL &
         "msr msp, %0" & NL &
         "dsb" & NL &
         "isb" & NL &
         "bx %1",
         Inputs   =>
           (UInt32'Asm_Input ("r", Stack),
            UInt32'Asm_Input ("r", Entry_Point)),
         Clobber  => "r2",
         Volatile => True);
      loop
         null;
      end loop;
   end Branch;

   ------------------
   -- Installed_OK --
   ------------------

   function Installed_OK return Boolean is
      Origin : constant UInt32 := Flash_Layout.App_Origin;
      Limit  : constant UInt32 := Origin + Flash_Layout.App_Length;
   begin
      Internal_Flash.Invalidate_Caches;
      return Bootstrap_Image.Valid_Vector
        (SP     => Internal_Flash.Word_At (Origin),
         Reset  => Internal_Flash.Word_At (Origin + 4),
         Origin => Origin,
         Limit  => Limit);
   end Installed_OK;

   ----------
   -- Jump --
   ----------

   procedure Jump (Origin : UInt32; Switched : out Boolean) is
   begin
      Quiet_Interrupts;
      Switched := Switch_To_HSI;
      if not Switched then
         return;
      end if;

      Internal_Flash.Invalidate_Caches;
      Cortex_M_SVD.SCB.SCB_Periph.VTOR := Origin;
      Branch
        (Internal_Flash.Word_At (Origin),
         Internal_Flash.Word_At (Origin + 4));
   end Jump;

end App_Jump;

with System;

package body HW is

   RCC     : constant Unsigned_32 := 16#4002_3800#;
   GPIOA   : constant Unsigned_32 := 16#4002_0000#;
   GPIOB   : constant Unsigned_32 := 16#4002_0400#;
   GPIOD   : constant Unsigned_32 := 16#4002_0C00#;
   USART2  : constant Unsigned_32 := 16#4000_4400#;
   DEMCR   : constant Unsigned_32 := 16#E000_EDFC#;
   DWT_CTL : constant Unsigned_32 := 16#E000_1000#;
   DWT_CYC : constant Unsigned_32 := 16#E000_1004#;

   --  APB1 is 42 MHz and its prescaler is not 1, so USART2 is clocked at
   --  84 MHz. OVER8 = 0: USARTDIV = 84e6 / (16 * 115200) = 45.5729.
   --  BRR mantissa 45, fraction 9.
   USART_BRR : constant Unsigned_32 := 16#02D9#;

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

   procedure Field
     (Addr, Shift, Width, Value : Unsigned_32)
   is
      Mask : constant Unsigned_32 :=
        Shift_Left
          (Shift_Left (Unsigned_32'(1), Natural (Width)) - 1, Natural (Shift));
      Next : Unsigned_32;
   begin
      Next := (R32 (Addr) and not Mask) or
        (Shift_Left (Value, Natural (Shift)) and Mask);
      W32 (Addr, Next);
   end Field;

   procedure Pin_Out (Port : Unsigned_32; Pin : Unsigned_32) is
   begin
      Field (Port + 16#00#, Pin * 2, 2, 1);
      Field (Port + 16#08#, Pin * 2, 2, 0);
      Field (Port + 16#0C#, Pin * 2, 2, 1);
   end Pin_Out;

   procedure Pin_AF
     (Port, Pin, AF : Unsigned_32)
   is
      Reg : Unsigned_32;
   begin
      Field (Port + 16#00#, Pin * 2, 2, 2);
      Field (Port + 16#08#, Pin * 2, 2, 2);
      if Pin < 8 then
         Reg := Port + 16#20#;
         Field (Reg, Pin * 4, 4, AF);
      else
         Reg := Port + 16#24#;
         Field (Reg, (Pin - 8) * 4, 4, AF);
      end if;
   end Pin_AF;

   procedure BSRR (Port, Bit : Unsigned_32; High : Boolean) is
   begin
      if High then
         W32 (Port + 16#18#, Shift_Left (Unsigned_32'(1), Natural (Bit)));
      else
         W32 (Port + 16#18#,
              Shift_Left (Unsigned_32'(1), Natural (Bit + 16)));
      end if;
   end BSRR;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      W32 (DEMCR, R32 (DEMCR) or 16#0100_0000#);
      W32 (DWT_CYC, 0);
      W32 (DWT_CTL, R32 (DWT_CTL) or 1);

      W32 (RCC + 16#30#, R32 (RCC + 16#30#) or 16#0000_000B#);
      W32 (RCC + 16#40#, R32 (RCC + 16#40#) or 16#0002_4000#);

      Pin_Out (GPIOD, 12);
      Pin_Out (GPIOD, 13);
      Pin_Out (GPIOD, 14);
      Pin_Out (GPIOD, 15);
      Leds_Off;

      --  SPI2 and the two chip-selects. Both selects idle high.
      Pin_AF (GPIOB, 13, 5);
      Pin_AF (GPIOB, 14, 5);
      Pin_AF (GPIOB, 15, 5);
      Field (GPIOB + 16#0C#, 14 * 2, 2, 1);
      Pin_Out (GPIOB, 11);
      Pin_Out (GPIOB, 12);
      W32 (GPIOB + 16#18#, Shift_Left (Unsigned_32'(1), 11) or
                            Shift_Left (Unsigned_32'(1), 12));

      Pin_AF (GPIOA, 2, 7);
      Pin_AF (GPIOA, 3, 7);
      Field (GPIOA + 16#0C#, 2 * 2, 2, 1);
      Field (GPIOA + 16#0C#, 3 * 2, 2, 1);

      W32 (USART2 + 16#0C#, 0);
      W32 (USART2 + 16#08#, USART_BRR);
      W32 (USART2 + 16#0C#, 16#0000_200C#);
   end Initialize;

   ------------
   -- Cycles --
   ------------

   function Cycles return Unsigned_32 is (R32 (DWT_CYC));

   -------------
   -- Wait_Ms --
   -------------

   procedure Wait_Ms (Ms : Unsigned_32) is
      Start : constant Unsigned_32 := Cycles;
      Need  : constant Unsigned_32 := Ms * 168_000;
   begin
      while Cycles - Start < Need loop
         null;
      end loop;
   end Wait_Ms;

   ---------
   -- Put --
   ---------

   procedure Put (Text : String) is
   begin
      for C of Text loop
         while (R32 (USART2) and 16#80#) = 0 loop
            null;
         end loop;
         W32 (USART2 + 4, Unsigned_32 (Character'Pos (C)));
      end loop;
   end Put;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Text : String) is
      CRLF : constant String := (ASCII.CR, ASCII.LF);
   begin
      Put (Text);
      Put (CRLF);
   end Put_Line;

   --------------
   -- Leds_Off --
   --------------

   procedure Leds_Off is
   begin
      Blue (False);
      Red (False);
      Orange (False);
   end Leds_Off;

   procedure One (Pin : Unsigned_32; On : Boolean) is
   begin
      BSRR (GPIOD, Pin, On);
   end One;

   ----------
   -- Blue --
   ----------

   procedure Blue (On : Boolean) is
   begin
      One (15, On);
   end Blue;

   ---------
   -- Red --
   ---------

   procedure Red (On : Boolean) is
   begin
      One (14, On);
   end Red;

   ------------
   -- Orange --
   ------------

   procedure Orange (On : Boolean) is
   begin
      One (13, On);
   end Orange;

end HW;

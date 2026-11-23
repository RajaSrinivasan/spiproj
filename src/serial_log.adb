with HAL;          use HAL;

with STM32.Device; use STM32.Device;
with STM32.GPIO;   use STM32.GPIO;
with STM32.USARTs; use STM32.USARTs;

package body Serial_Log is

   TX_Pin : constant GPIO_Point := PA2;
   RX_Pin : constant GPIO_Point := PA3;

   Pins : constant GPIO_Points := TX_Pin & RX_Pin;

   Ready : Boolean := False;

   Pin_Conf : constant GPIO_Port_Configuration :=
     (Mode           => Mode_AF,
      Resistors      => Pull_Up,
      AF_Output_Type => Push_Pull,
      AF_Speed       => Speed_50MHz,
      AF             => GPIO_AF_USART2_7);

   procedure Put_Char (C : Character);

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
   begin
      Enable_Clock (Pins);
      Enable_Clock (USART_2);

      Configure_IO (Pins, Pin_Conf);

      Disable (USART_2);
      --  The baud divider reads the oversampling bit, so set that first.
      Set_Oversampling_Mode (USART_2, Oversampling_By_16);
      Set_Word_Length (USART_2, Word_Length_8);
      Set_Parity (USART_2, No_Parity);
      Set_Stop_Bits (USART_2, Stopbits_1);
      Set_Mode (USART_2, Tx_Rx_Mode);
      Set_Flow_Control (USART_2, No_Flow_Control);
      Set_Baud_Rate (USART_2, 115_200);
      Enable (USART_2);
      Ready := True;
   end Initialize;

   --------------
   -- Put_Char --
   --------------

   procedure Put_Char (C : Character) is
   begin
      loop
         exit when Tx_Ready (USART_2);
      end loop;
      Transmit (USART_2, UInt9 (Character'Pos (C)));
   end Put_Char;

   ---------
   -- Put --
   ---------

   procedure Put (Text : String) is
   begin
      if not Ready then
         return;
      end if;

      for C of Text loop
         Put_Char (C);
      end loop;
   end Put;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (Text : String) is
   begin
      Put (Text);
      Put (String'(ASCII.CR & ASCII.LF));
   end Put_Line;

end Serial_Log;

------------------------------------------------------------------------------
--  Branch to the application image.
--
--  The application is linked with its vector table at Flash_Layout.App_Origin.
--  Jump reads the initial stack pointer and the reset handler from that
--  table, points VTOR at it, and branches. The runtime's own startup then
--  copies .data, clears .bss, and installs the Ravenscar vector table.
--
--  Before the branch the clocks are moved back to HSI with the PLL off, so
--  the application's Setup_Pll starts from the same shape it sees after a
--  hardware reset. USART output after that point is not at 115200.
------------------------------------------------------------------------------

with HAL; use HAL;

package App_Jump is

   function Installed_OK return Boolean;
   --  The two words at the application origin look like a stack pointer
   --  and a Thumb reset handler inside the application window.

   procedure Jump (Origin : UInt32; Switched : out Boolean);
   --  Does not return when the branch is taken. Switched is False when the
   --  clock could not be moved to HSI; the caller is still running and the
   --  USART baud rate is unchanged. When the branch is taken, Switched is
   --  not observed.

end App_Jump;

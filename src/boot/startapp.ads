with Interfaces; use Interfaces;

package StartApp is

   function Installed return Boolean;
   --  The two words at the application origin look like a stack pointer
   --  in main SRAM and a Thumb reset handler inside the application window.

   procedure Jump (Origin : Unsigned_32; Switched : out Boolean);
   --  Does not return when the branch is taken. Switched is False when the
   --  clock could not be moved to HSI first; USART baud is then unchanged.

end StartApp;

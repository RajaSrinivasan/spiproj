with System;
with System.Storage_Elements;

package body Flash_Layout is

   Boot_Origin_Mark : UInt8
     with Import, Convention => C, External_Name => "__boot_origin";
   Boot_Length_Mark : UInt8
     with Import, Convention => C, External_Name => "__boot_length";
   App_Origin_Mark : UInt8
     with Import, Convention => C, External_Name => "__app_origin";
   App_Length_Mark : UInt8
     with Import, Convention => C, External_Name => "__app_length";

   function To_U32 (A : System.Address) return UInt32 is
     (UInt32 (System.Storage_Elements.To_Integer (A)));

   function Boot_Origin return UInt32 is
     (To_U32 (Boot_Origin_Mark'Address));

   function Boot_Length return UInt32 is
     (To_U32 (Boot_Length_Mark'Address));

   function App_Origin return UInt32 is
     (To_U32 (App_Origin_Mark'Address));

   function App_Length return UInt32 is
     (To_U32 (App_Length_Mark'Address));

end Flash_Layout;

with Flash_Layout;

package body Bootstrap_Image is

   Magic : constant Magic_Bytes := ('S', 'P', 'B', '1');

   ------------------
   -- Check_Fields --
   ------------------

   function Check_Fields
     (Item                 : Header;
      File_Bytes           : UInt64;
      Computed_Header_CRC  : UInt32;
      App_Origin           : UInt32;
      App_Length           : UInt32) return Failure
   is
   begin
      if Item.Magic /= Magic then
         return Bad_Magic;
      end if;

      --  The header CRC covers the length and the load address, so a
      --  mismatch here means those fields are not trustworthy yet.
      if Item.Header_Bytes /= Bootstrap_Image.Header_Bytes
        or else Item.Reserved_0 /= 0
        or else Item.Reserved_1 /= 0
        or else Computed_Header_CRC /= Item.Header_CRC
      then
         return Bad_Header;
      end if;

      if Item.Load_Address /= App_Origin then
         return Bad_Address;
      end if;

      if Item.Payload_Bytes < 8
        or else Item.Payload_Bytes > App_Length
        or else File_Bytes /=
          UInt64 (Bootstrap_Image.Header_Bytes) + UInt64 (Item.Payload_Bytes)
      then
         return Bad_Length;
      end if;

      return None;
   end Check_Fields;

   ------------------
   -- Valid_Vector --
   ------------------

   function Valid_Vector
     (SP, Reset, Origin, Limit : UInt32) return Boolean
   is
      Target : UInt32;
   begin
      if Limit <= Origin then
         return False;
      end if;

      if SP < Flash_Layout.SRAM_Origin + 8
        or else SP > Flash_Layout.SRAM_Limit
        or else SP mod 8 /= 0
      then
         return False;
      end if;

      --  The vector's low bit is the Thumb marker. Cortex-M refuses to
      --  start without it.
      if Reset mod 2 = 0 then
         return False;
      end if;

      Target := Reset and 16#FFFF_FFFE#;
      return Target >= Origin and then Target < Limit;
   end Valid_Vector;

end Bootstrap_Image;

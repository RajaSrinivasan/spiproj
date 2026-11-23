with System;
with System.Storage_Elements;

with STM32_CRC;

package body Flash_CRC is

   Text_Start_Mark : UInt8
     with Import, Convention => C, External_Name => "__text_start";
   Text_End_Mark : UInt8
     with Import, Convention => C, External_Name => "__text_end";
   Rodata_Start_Mark : UInt8
     with Import, Convention => C, External_Name => "__rodata_start";
   Rodata_End_Mark : UInt8
     with Import, Convention => C, External_Name => "__rodata_end";
   Data_LMA_Start_Mark : UInt8
     with Import, Convention => C, External_Name => "__data_lma_start";
   Data_LMA_End_Mark : UInt8
     with Import, Convention => C, External_Name => "__data_lma_end";

   References : array (Segment_Id) of Digest;
   Captured   : Boolean := False;

   function To_U32 (A : System.Address) return UInt32 is
     (UInt32 (System.Storage_Elements.To_Integer (A)));

   procedure Region
     (First : System.Address;
      Last  : System.Address;
      Item  : out Digest);

   ------------
   -- Region --
   ------------

   procedure Region
     (First : System.Address;
      Last  : System.Address;
      Item  : out Digest)
   is
      use System.Storage_Elements;
      Length : constant UInt32 := UInt32 (Last - First);
   begin
      --  STM32_CRC.Digest is the same little-endian word walk the
      --  bootloader uses on a bootstrap payload, including a short tail.
      Item :=
        (Start  => To_U32 (First),
         Length => Length,
         CRC    => STM32_CRC.Digest (First, Length));
   end Region;

   ------------------------
   -- Capture_References --
   ------------------------

   procedure Capture_References is
   begin
      Region (Text_Start_Mark'Address, Text_End_Mark'Address,
              References (Text));
      Region (Rodata_Start_Mark'Address, Rodata_End_Mark'Address,
              References (Rodata));
      Region (Data_LMA_Start_Mark'Address, Data_LMA_End_Mark'Address,
              References (Data_LMA));
      Captured := True;
   end Capture_References;

   ---------------
   -- Reference --
   ---------------

   function Reference (Id : Segment_Id) return Digest is
     (References (Id));

   -------------------
   -- Segment_Image --
   -------------------

   function Segment_Image (Id : Segment_Id) return String is
     (case Id is
         when Text     => "text",
         when Rodata   => "rodata",
         when Data_LMA => "data_lma");

   -------------
   -- Recheck --
   -------------

   procedure Recheck
     (Id      : Segment_Id;
      Current : out Digest;
      Match   : out Boolean)
   is
   begin
      case Id is
         when Text =>
            Region (Text_Start_Mark'Address, Text_End_Mark'Address, Current);
         when Rodata =>
            Region (Rodata_Start_Mark'Address, Rodata_End_Mark'Address,
                    Current);
         when Data_LMA =>
            Region (Data_LMA_Start_Mark'Address, Data_LMA_End_Mark'Address,
                    Current);
      end case;

      Match := Captured
        and then Current.Start = References (Id).Start
        and then Current.Length = References (Id).Length
        and then Current.CRC = References (Id).CRC;
   end Recheck;

end Flash_CRC;

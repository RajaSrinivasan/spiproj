with STM32.CRC;    use STM32.CRC;
with STM32.Device;  use STM32.Device;

with System;
with System.Storage_Elements;

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

   function Word_At (A : System.Address) return UInt32;
   function Byte_At (A : System.Address) return UInt8;

   procedure Region
     (First : System.Address;
      Last  : System.Address;
      Item  : out Digest);

   function Word_At (A : System.Address) return UInt32 is
      W : UInt32 with Volatile, Import, Address => A;
   begin
      return W;
   end Word_At;

   function Byte_At (A : System.Address) return UInt8 is
      B : UInt8 with Volatile, Import, Address => A;
   begin
      return B;
   end Byte_At;

   ------------
   -- Region --
   ------------

   procedure Region
     (First : System.Address;
      Last  : System.Address;
      Item  : out Digest)
   is
      use System.Storage_Elements;
      Length    : constant UInt32 := UInt32 (Last - First);
      Remaining : UInt32 := Length / 4;
      Tail      : constant UInt32 := Length mod 4;
      Cursor    : System.Address := First;
      Last_W    : UInt32 := 16#FFFF_FFFF#;
   begin
      Reset_Calculator (CRC_Unit);

      while Remaining > 0 loop
         Update_CRC (CRC_Unit, Word_At (Cursor), Last_W);
         Cursor := Cursor + Storage_Offset (4);
         Remaining := Remaining - 1;
      end loop;

      if Tail /= 0 then
         declare
            Packed : UInt32 := 0;
            Piece  : UInt32;
         begin
            --  Little-endian tail: the first leftover byte is the low byte.
            --  The high bytes stay zero. tools/elf_hashes.py does the same.
            for I in 0 .. Tail - 1 loop
               Piece := UInt32 (Byte_At (Cursor));
               for S in 1 .. Natural (I) loop
                  Piece := Piece * 256;
               end loop;
               Packed := Packed or Piece;
               Cursor := Cursor + Storage_Offset (1);
            end loop;
            Update_CRC (CRC_Unit, Packed, Last_W);
         end;
      end if;

      if Length = 0 then
         Last_W := Value (CRC_Unit);
      end if;

      Item :=
        (Start  => To_U32 (First),
         Length => Length,
         CRC    => Last_W);
   end Region;

   ------------------------
   -- Capture_References --
   ------------------------

   procedure Capture_References is
   begin
      Enable_Clock (CRC_Unit);
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

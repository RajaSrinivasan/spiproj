with STM32.CRC;   use STM32.CRC;
with STM32.Device; use STM32.Device;

with System.Storage_Elements;

package body STM32_CRC is

   procedure Feed_Word (Word : UInt32);
   function Byte_At (A : System.Address) return UInt8;

   function Byte_At (A : System.Address) return UInt8 is
      B : UInt8 with Volatile, Import, Address => A;
   begin
      return B;
   end Byte_At;

   ---------------
   -- Feed_Word --
   ---------------

   procedure Feed_Word (Word : UInt32) is
      Unused : UInt32;
   begin
      Update_CRC (CRC_Unit, Word, Unused);
   end Feed_Word;

   -----------
   -- Start --
   -----------

   procedure Start (Acc : out Accumulator) is
   begin
      Enable_Clock (CRC_Unit);
      Reset_Calculator (CRC_Unit);
      Acc := (Partial => 0, Filled => 0);
   end Start;

   ------------
   -- Append --
   ------------

   procedure Append (Acc : in out Accumulator; Data : UInt8_Array) is
   begin
      for B of Data loop
         declare
            Piece : UInt32 := UInt32 (B);
         begin
            --  Little-endian: the first byte of a word is the low byte.
            for S in 1 .. Acc.Filled loop
               Piece := Piece * 256;
            end loop;
            Acc.Partial := Acc.Partial or Piece;
         end;
         Acc.Filled := Acc.Filled + 1;
         if Acc.Filled = 4 then
            Feed_Word (Acc.Partial);
            Acc.Partial := 0;
            Acc.Filled := 0;
         end if;
      end loop;
   end Append;

   ------------
   -- Finish --
   ------------

   function Finish (Acc : in out Accumulator) return UInt32 is
   begin
      if Acc.Filled > 0 then
         Feed_Word (Acc.Partial);
         Acc.Partial := 0;
         Acc.Filled := 0;
      end if;
      return Value (CRC_Unit);
   end Finish;

   ------------
   -- Digest --
   ------------

   function Digest (First : System.Address; Length : UInt32) return UInt32 is
      use System.Storage_Elements;
      Acc    : Accumulator;
      Cursor : System.Address := First;
      Left   : UInt32 := Length;
   begin
      Start (Acc);
      while Left > 0 loop
         declare
            One : constant UInt8_Array (1 .. 1) := (1 => Byte_At (Cursor));
         begin
            Append (Acc, One);
         end;
         Cursor := Cursor + Storage_Offset (1);
         Left := Left - 1;
      end loop;
      return Finish (Acc);
   end Digest;

end STM32_CRC;

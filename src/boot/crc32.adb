with Bytes;

package body CRC32 is

   function Feed (CRC, Word : Unsigned_32) return Unsigned_32 is
      C : Unsigned_32 := CRC xor Word;
   begin
      for I in 1 .. 32 loop
         if (C and 16#8000_0000#) /= 0 then
            C := Shift_Left (C, 1) xor 16#04C1_1DB7#;
         else
            C := Shift_Left (C, 1);
         end if;
      end loop;
      return C;
   end Feed;

   -----------
   -- Reset --
   -----------

   procedure Reset (Acc : out Accumulator) is
   begin
      Acc := (Value => 16#FFFF_FFFF#, Partial => 0, Filled => 0);
   end Reset;

   ------------
   -- Append --
   ------------

   procedure Append (Acc : in out Accumulator; Data : Bytes.Arr) is
   begin
      for B of Data loop
         declare
            Piece : Unsigned_32 := Unsigned_32 (B);
         begin
            for S in 1 .. Acc.Filled loop
               Piece := Piece * 256;
            end loop;
            Acc.Partial := Acc.Partial or Piece;
         end;
         Acc.Filled := Acc.Filled + 1;
         if Acc.Filled = 4 then
            Acc.Value := Feed (Acc.Value, Acc.Partial);
            Acc.Partial := 0;
            Acc.Filled := 0;
         end if;
      end loop;
   end Append;

   ------------
   -- Finish --
   ------------

   function Finish (Acc : in out Accumulator) return Unsigned_32 is
   begin
      if Acc.Filled > 0 then
         Acc.Value := Feed (Acc.Value, Acc.Partial);
         Acc.Partial := 0;
         Acc.Filled := 0;
      end if;
      return Acc.Value;
   end Finish;

end CRC32;

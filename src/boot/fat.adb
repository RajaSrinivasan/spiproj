with Bytes;

with SDCard;

package body FAT is

   type Kind_Type is (FAT12, FAT16, FAT32);

   Kind        : Kind_Type := FAT16;
   SPC         : Unsigned_8 := 1;
   Fat_Start   : Unsigned_32 := 0;
   Fat_Sectors : Unsigned_32 := 0;
   Num_FATs    : Unsigned_8 := 2;
   Root_Start  : Unsigned_32 := 0;
   Root_Sectors : Unsigned_32 := 0;
   Root_Cluster : Unsigned_32 := 0;
   Data_Start  : Unsigned_32 := 0;
   Max_Cluster : Unsigned_32 := 0;

   File_Start  : Unsigned_32 := 0;
   File_Size   : Unsigned_32 := 0;
   Opened      : Boolean := False;

   type Slot is record
      LBA    : Unsigned_32 := 0;
      Offset : Unsigned_16 := 0;
   end record;

   Slots  : array (1 .. 4) of Slot;
   NSlots : Natural := 0;

   Cur_Cluster : Unsigned_32 := 0;
   Cur_Base    : Unsigned_32 := 0;
   Pos         : Unsigned_32 := 0;

   Cache_LBA : Unsigned_32 := 16#FFFF_FFFF#;
   Cache     : SDCard.Block;
   Dirty     : Boolean := False;

   function Load (LBA : Unsigned_32) return Boolean;
   procedure Flush;
   function Fat_Get (Cluster : Unsigned_32) return Unsigned_32;
   procedure Fat_Put (Cluster, Value : Unsigned_32);
   function End_Of_Chain (Value : Unsigned_32) return Boolean;

   ----------
   -- Load --
   ----------

   function Load (LBA : Unsigned_32) return Boolean is
   begin
      if Cache_LBA = LBA then
         return True;
      end if;
      Flush;
      if not SDCard.Read (LBA, Cache) then
         Cache_LBA := 16#FFFF_FFFF#;
         return False;
      end if;
      Cache_LBA := LBA;
      Dirty := False;
      return True;
   end Load;

   -----------
   -- Flush --
   -----------

   procedure Flush is
   begin
      if Dirty and then Cache_LBA /= 16#FFFF_FFFF# then
         if SDCard.Write (Cache_LBA, Cache) then
            Dirty := False;
         end if;
      end if;
   end Flush;

   function U16 (Idx : Natural) return Unsigned_16 is
     (Unsigned_16 (Cache (Idx)) or
      Shift_Left (Unsigned_16 (Cache (Idx + 1)), 8));

   function U32 (Idx : Natural) return Unsigned_32 is
     (Unsigned_32 (Cache (Idx)) or
      Shift_Left (Unsigned_32 (Cache (Idx + 1)), 8) or
      Shift_Left (Unsigned_32 (Cache (Idx + 2)), 16) or
      Shift_Left (Unsigned_32 (Cache (Idx + 3)), 24));

   function Fat_Byte
     (Base, Offset : Unsigned_32;
      Value        : out Unsigned_8) return Boolean
   is
      LBA : constant Unsigned_32 := Base + Offset / 512;
      Idx : constant Natural := Natural (Offset mod 512);
   begin
      if not Load (LBA) then
         return False;
      end if;
      Value := Cache (Idx);
      return True;
   end Fat_Byte;

   function Put_Fat_Byte
     (Base, Offset : Unsigned_32;
      Value        : Unsigned_8) return Boolean
   is
      LBA : constant Unsigned_32 := Base + Offset / 512;
      Idx : constant Natural := Natural (Offset mod 512);
   begin
      if not Load (LBA) then
         return False;
      end if;
      Cache (Idx) := Value;
      Dirty := True;
      return True;
   end Put_Fat_Byte;

   -------------
   -- Fat_Get --
   -------------

   function Fat_Get (Cluster : Unsigned_32) return Unsigned_32 is
      B0, B1, B2, B3 : Unsigned_8;
      Word           : Unsigned_16;
   begin
      case Kind is
         when FAT12 =>
            declare
               Off : constant Unsigned_32 := Cluster + Cluster / 2;
            begin
               if not Fat_Byte (Fat_Start, Off, B0)
                 or else not Fat_Byte (Fat_Start, Off + 1, B1)
               then
                  return 16#FFFF_FFFF#;
               end if;
               Word := Unsigned_16 (B0) or Shift_Left (Unsigned_16 (B1), 8);
               if (Cluster and 1) = 0 then
                  return Unsigned_32 (Word and 16#0FFF#);
               else
                  return Unsigned_32 (Shift_Right (Word, 4));
               end if;
            end;
         when FAT16 =>
            if not Fat_Byte (Fat_Start, Cluster * 2, B0)
              or else not Fat_Byte (Fat_Start, Cluster * 2 + 1, B1)
            then
               return 16#FFFF_FFFF#;
            end if;
            return Unsigned_32 (B0) or Shift_Left (Unsigned_32 (B1), 8);
         when FAT32 =>
            if not Fat_Byte (Fat_Start, Cluster * 4, B0)
              or else not Fat_Byte (Fat_Start, Cluster * 4 + 1, B1)
              or else not Fat_Byte (Fat_Start, Cluster * 4 + 2, B2)
              or else not Fat_Byte (Fat_Start, Cluster * 4 + 3, B3)
            then
               return 16#FFFF_FFFF#;
            end if;
            return (Unsigned_32 (B0) or
                    Shift_Left (Unsigned_32 (B1), 8) or
                    Shift_Left (Unsigned_32 (B2), 16) or
                    Shift_Left (Unsigned_32 (B3), 24)) and 16#0FFF_FFFF#;
      end case;
   end Fat_Get;

   -------------
   -- Fat_Put --
   -------------

   procedure Fat_Put (Cluster, Value : Unsigned_32) is
      OK : Boolean;
   begin
      for Copy in 0 .. Natural (Num_FATs) - 1 loop
         declare
            Base : constant Unsigned_32 :=
              Fat_Start + Unsigned_32 (Copy) * Fat_Sectors;
         begin
            case Kind is
               when FAT12 =>
                  declare
                     Off  : constant Unsigned_32 := Cluster + Cluster / 2;
                     B0, B1 : Unsigned_8;
                     Word : Unsigned_16;
                  begin
                     if not Fat_Byte (Base, Off, B0)
                       or else not Fat_Byte (Base, Off + 1, B1)
                     then
                        return;
                     end if;
                     Word := Unsigned_16 (B0) or
                       Shift_Left (Unsigned_16 (B1), 8);
                     if (Cluster and 1) = 0 then
                        Word := (Word and 16#F000#) or
                          Unsigned_16 (Value and 16#0FFF#);
                     else
                        Word := (Word and 16#000F#) or
                          Shift_Left (Unsigned_16 (Value and 16#0FFF#), 4);
                     end if;
                     OK := Put_Fat_Byte (Base, Off, Unsigned_8 (Word and 16#FF#))
                       and then Put_Fat_Byte
                         (Base, Off + 1,
                          Unsigned_8 (Shift_Right (Word, 8)));
                     if not OK then
                        return;
                     end if;
                  end;
               when FAT16 =>
                  OK := Put_Fat_Byte
                    (Base, Cluster * 2, Unsigned_8 (Value and 16#FF#))
                    and then Put_Fat_Byte
                      (Base, Cluster * 2 + 1,
                       Unsigned_8 (Shift_Right (Value, 8) and 16#FF#));
                  if not OK then
                     return;
                  end if;
               when FAT32 =>
                  declare
                     Old : Unsigned_8;
                  begin
                     if not Fat_Byte (Base, Cluster * 4 + 3, Old) then
                        return;
                     end if;
                     OK := Put_Fat_Byte
                       (Base, Cluster * 4, Unsigned_8 (Value and 16#FF#))
                       and then Put_Fat_Byte
                         (Base, Cluster * 4 + 1,
                          Unsigned_8 (Shift_Right (Value, 8) and 16#FF#))
                       and then Put_Fat_Byte
                         (Base, Cluster * 4 + 2,
                          Unsigned_8 (Shift_Right (Value, 16) and 16#FF#))
                       and then Put_Fat_Byte
                         (Base, Cluster * 4 + 3,
                          (Old and 16#F0#) or
                            Unsigned_8 (Shift_Right (Value, 24) and 16#0F#));
                     if not OK then
                        return;
                     end if;
                  end;
            end case;
         end;
      end loop;
      Flush;
   end Fat_Put;

   ------------------
   -- End_Of_Chain --
   ------------------

   function End_Of_Chain (Value : Unsigned_32) return Boolean is
   begin
      case Kind is
         when FAT12 => return Value >= 16#0FF8#;
         when FAT16 => return Value >= 16#FFF8#;
         when FAT32 => return Value >= 16#0FFF_FFF8#;
      end case;
   end End_Of_Chain;

   function Parse_Volume (LBA : Unsigned_32) return Boolean is
      Root_Ent     : Unsigned_32;
      Total        : Unsigned_32;
      Reserved     : Unsigned_32;
      Fat_Sz       : Unsigned_32;
      Root_Sectors : Unsigned_32;
      Data_Sectors : Unsigned_32;
      Clusters     : Unsigned_32;
   begin
      if not Load (LBA) then
         return False;
      end if;
      if Cache (510) /= 16#55# or else Cache (511) /= 16#AA# then
         return False;
      end if;
      if U16 (11) /= 512 or else Cache (13) = 0 then
         return False;
      end if;
      SPC := Cache (13);
      Reserved := Unsigned_32 (U16 (14));
      Num_FATs := Cache (16);
      if Num_FATs = 0 or else Num_FATs > 2 then
         return False;
      end if;
      Root_Ent := Unsigned_32 (U16 (17));
      Total := Unsigned_32 (U16 (19));
      if Total = 0 then
         Total := U32 (32);
      end if;
      Fat_Sz := Unsigned_32 (U16 (22));
      if Fat_Sz = 0 then
         Fat_Sz := U32 (36);
      end if;
      if Total = 0 or else Fat_Sz = 0 or else Reserved = 0 then
         return False;
      end if;

      Root_Sectors := ((Root_Ent * 32) + 511) / 512;
      if Reserved + Unsigned_32 (Num_FATs) * Fat_Sz + Root_Sectors >= Total
      then
         return False;
      end if;
      Data_Sectors :=
        Total - Reserved - Unsigned_32 (Num_FATs) * Fat_Sz - Root_Sectors;
      Clusters := Data_Sectors / Unsigned_32 (SPC);
      if Clusters < 4085 then
         Kind := FAT12;
      elsif Clusters < 65525 then
         Kind := FAT16;
      else
         Kind := FAT32;
      end if;

      Fat_Start := LBA + Reserved;
      Fat_Sectors := Fat_Sz;
      Root_Start := Fat_Start + Unsigned_32 (Num_FATs) * Fat_Sz;
      FAT.Root_Sectors := Root_Sectors;
      Data_Start := Root_Start + Root_Sectors;
      Max_Cluster := Clusters + 1;
      if Kind = FAT32 then
         Root_Cluster := U32 (44);
      else
         Root_Cluster := 0;
      end if;
      return True;
   end Parse_Volume;

   -----------
   -- Mount --
   -----------

   function Mount return Boolean is
      Part_LBA  : Unsigned_32 := 0;
      Part_Type : Unsigned_8;
      Found     : Boolean := False;
   begin
      if not Load (0) then
         return False;
      end if;
      if Cache (510) = 16#55# and then Cache (511) = 16#AA# then
         for I in 0 .. 3 loop
            Part_Type := Cache (446 + I * 16 + 4);
            if Part_Type in 16#01# | 16#04# | 16#06# |
                            16#0B# | 16#0C# | 16#0E#
            then
               Part_LBA := U32 (446 + I * 16 + 8);
               Found := Part_LBA /= 0;
               exit when Found;
            end if;
         end loop;
      end if;
      if Found then
         return Parse_Volume (Part_LBA);
      else
         return Parse_Volume (0);
      end if;
   end Mount;

   type Name_Bytes is array (0 .. 38) of Unsigned_8;

   Name_Buf      : Name_Bytes := (others => 0);
   Name_Len      : Natural := 0;
   Have_LFN      : Boolean := False;
   LFN_Sum       : Unsigned_8 := 0;
   File_Name     : String (1 .. 32);
   File_Name_Len : Natural := 0;

   function Up (C : Unsigned_8) return Unsigned_8 is
   begin
      if C in Character'Pos ('a') .. Character'Pos ('z') then
         return C - 16#20#;
      else
         return C;
      end if;
   end Up;

   function Name_Is (Expect : String) return Boolean is
      N : Natural := 0;
   begin
      if Expect'Length > 32 then
         return False;
      end if;
      while N < Name_Len and then Name_Buf (N) /= 0 loop
         N := N + 1;
      end loop;
      if N /= Expect'Length then
         return False;
      end if;
      for I in 0 .. N - 1 loop
         if Up (Name_Buf (I)) /=
           Up (Unsigned_8 (Character'Pos (Expect (Expect'First + I))))
         then
            return False;
         end if;
      end loop;
      return True;
   end Name_Is;

   function Short_Checksum (Idx : Natural) return Unsigned_8 is
      Sum : Unsigned_8 := 0;
   begin
      for I in 0 .. 10 loop
         if (Sum and 1) /= 0 then
            Sum := Shift_Right (Sum, 1) or 16#80#;
         else
            Sum := Shift_Right (Sum, 1);
         end if;
         Sum := Sum + Cache (Idx + I);
      end loop;
      return Sum;
   end Short_Checksum;

   procedure Take_LFN (Idx : Natural) is
      Seq   : constant Unsigned_8 := Cache (Idx) and 16#1F#;
      Pos   : Natural;
      Chars : constant array (0 .. 12) of Natural :=
        (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30);
   begin
      if Seq = 0 or else Seq > 3 then
         Have_LFN := False;
         return;
      end if;
      if (Cache (Idx) and 16#40#) /= 0 then
         Name_Buf := (others => 0);
         Name_Len := 0;
         Have_LFN := True;
         LFN_Sum := Cache (Idx + 13);
      end if;
      if not Have_LFN or else Cache (Idx + 13) /= LFN_Sum then
         Have_LFN := False;
         return;
      end if;
      Pos := Natural (Seq - 1) * 13;
      for I in Chars'Range loop
         if Pos + I < Name_Buf'Length then
            if Cache (Idx + Chars (I) + 1) = 0 then
               Name_Buf (Pos + I) := Cache (Idx + Chars (I));
            else
               Name_Buf (Pos + I) := Character'Pos ('?');
            end if;
         end if;
      end loop;
      if Pos + 13 > Name_Len then
         Name_Len := Pos + 13;
      end if;
   end Take_LFN;

   function Short_Is (Idx : Natural; Expect : String) return Boolean is
      Raw : String (1 .. 12);
      N   : Natural := 0;
   begin
      for I in 0 .. 7 loop
         exit when Cache (Idx + I) = 16#20#;
         N := N + 1;
         Raw (N) := Character'Val (Cache (Idx + I));
      end loop;
      if Cache (Idx + 8) /= 16#20# then
         N := N + 1;
         Raw (N) := '.';
         for I in 8 .. 10 loop
            exit when Cache (Idx + I) = 16#20#;
            N := N + 1;
            Raw (N) := Character'Val (Cache (Idx + I));
         end loop;
      end if;
      if N /= Expect'Length then
         return False;
      end if;
      for I in 1 .. N loop
         if Up (Unsigned_8 (Character'Pos (Raw (I)))) /=
           Up (Unsigned_8 (Character'Pos (Expect (Expect'First + I - 1))))
         then
            return False;
         end if;
      end loop;
      return True;
   end Short_Is;

   procedure Consider (LBA : Unsigned_32; Idx : Natural; Hit : out Boolean) is
      Attr : constant Unsigned_8 := Cache (Idx + 11);
   begin
      Hit := False;
      if Cache (Idx) = 0 then
         Hit := True;
         return;
      end if;
      if Cache (Idx) = 16#E5# then
         Have_LFN := False;
         NSlots := 0;
         return;
      end if;
      if Attr = 16#0F# then
         if NSlots < Slots'Last then
            NSlots := NSlots + 1;
            Slots (NSlots) := (LBA, Unsigned_16 (Idx));
         end if;
         Take_LFN (Idx);
         return;
      end if;
      if (Attr and 16#18#) = 0 then
         if (Have_LFN and then Short_Checksum (Idx) = LFN_Sum
             and then Name_Is (File_Name (1 .. File_Name_Len)))
           or else
             (not Have_LFN
              and then Short_Is (Idx, File_Name (1 .. File_Name_Len)))
         then
            if NSlots < Slots'Last then
               NSlots := NSlots + 1;
               Slots (NSlots) := (LBA, Unsigned_16 (Idx));
            end if;
            File_Start :=
              Shift_Left (Unsigned_32 (U16 (Idx + 20)), 16) or
              Unsigned_32 (U16 (Idx + 26));
            File_Size := U32 (Idx + 28);
            Opened := True;
            Hit := True;
            return;
         end if;
      end if;
      Have_LFN := False;
      NSlots := 0;
   end Consider;

   function Walk_Sector
     (LBA : Unsigned_32;
      Stop : out Boolean) return Boolean
   is
   begin
      Stop := False;
      if not Load (LBA) then
         return False;
      end if;
      for I in 0 .. 15 loop
         Consider (LBA, I * 32, Stop);
         exit when Stop;
      end loop;
      return True;
   end Walk_Sector;

   ----------
   -- Open --
   ----------

   function Open (Name : String) return Boolean is
      Stop    : Boolean;
      Cluster : Unsigned_32;
      Guard   : Natural := 0;
   begin
      Opened := False;
      NSlots := 0;
      Have_LFN := False;
      File_Name_Len := Name'Length;
      if File_Name_Len > File_Name'Length then
         return False;
      end if;
      for I in 1 .. File_Name_Len loop
         File_Name (I) := Name (Name'First + I - 1);
      end loop;

      if Kind = FAT32 then
         Cluster := Root_Cluster;
         while Cluster >= 2 and then Cluster <= Max_Cluster
           and then not End_Of_Chain (Cluster)
         loop
            Guard := Guard + 1;
            if Guard > 64 then
               return False;
            end if;
            for S in 0 .. Unsigned_32 (SPC) - 1 loop
               if not Walk_Sector
                 (Data_Start + (Cluster - 2) * Unsigned_32 (SPC) + S, Stop)
               then
                  return False;
               end if;
               if Opened or else Stop then
                  goto Found;
               end if;
            end loop;
            Cluster := Fat_Get (Cluster);
         end loop;
      elsif Root_Sectors > 0 then
         for S in 0 .. Root_Sectors - 1 loop
            if not Walk_Sector (Root_Start + S, Stop) then
               return False;
            end if;
            exit when Opened or else Stop;
         end loop;
      end if;

      <<Found>>
      if not Opened then
         return False;
      end if;
      Cur_Cluster := File_Start;
      Cur_Base := 0;
      Pos := 0;
      return True;
   end Open;

   ----------
   -- Size --
   ----------

   function Size return Unsigned_32 is (File_Size);

   ------------
   -- Rewind --
   ------------

   procedure Rewind is
   begin
      Cur_Cluster := File_Start;
      Cur_Base := 0;
      Pos := 0;
   end Rewind;

   ----------
   -- Read --
   ----------

   procedure Read
     (Data : out Bytes.Arr;
      Got  : out Natural;
      OK   : out Boolean)
   is
      Want     : Natural := Data'Length;
      Done     : Natural := 0;
      Per      : constant Unsigned_32 := Unsigned_32 (SPC) * 512;
      In_Cl    : Unsigned_32;
      Sector   : Unsigned_32;
      Index    : Natural;
      Take     : Natural;
   begin
      OK := True;
      if not Opened then
         OK := False;
         Got := 0;
         return;
      end if;
      if Pos >= File_Size then
         Got := 0;
         return;
      end if;
      if Unsigned_32 (Want) > File_Size - Pos then
         Want := Natural (File_Size - Pos);
      end if;

      while Done < Want loop
         if Cur_Cluster < 2 or else Cur_Cluster > Max_Cluster then
            OK := False;
            Got := Done;
            return;
         end if;
         if Pos >= Cur_Base + Per then
            Cur_Cluster := Fat_Get (Cur_Cluster);
            Cur_Base := Cur_Base + Per;
            if End_Of_Chain (Cur_Cluster) then
               OK := False;
               Got := Done;
               return;
            end if;
         else
            In_Cl := Pos - Cur_Base;
            Sector :=
              Data_Start + (Cur_Cluster - 2) * Unsigned_32 (SPC) + In_Cl / 512;
            Index := Natural (In_Cl mod 512);
            if not Load (Sector) then
               OK := False;
               Got := Done;
               return;
            end if;
            Take := Want - Done;
            if Take > 512 - Index then
               Take := 512 - Index;
            end if;
            for I in 0 .. Take - 1 loop
               Data (Data'First + Done + I) := Cache (Index + I);
            end loop;
            Done := Done + Take;
            Pos := Pos + Unsigned_32 (Take);
         end if;
      end loop;
      Got := Done;
   end Read;

   ------------
   -- Delete --
   ------------

   function Delete return Boolean is
      Cluster : Unsigned_32 := File_Start;
      Next    : Unsigned_32;
      Guard   : Natural := 0;
   begin
      if not Opened then
         return False;
      end if;
      for I in 1 .. NSlots loop
         if not Load (Slots (I).LBA) then
            return False;
         end if;
         Cache (Natural (Slots (I).Offset)) := 16#E5#;
         Dirty := True;
      end loop;
      Flush;

      if Cluster < 2 then
         Opened := False;
         return True;
      end if;
      while not End_Of_Chain (Cluster) loop
         Guard := Guard + 1;
         if Guard > 4096 or else Cluster < 2 or else Cluster > Max_Cluster then
            return False;
         end if;
         Next := Fat_Get (Cluster);
         Fat_Put (Cluster, 0);
         Cluster := Next;
      end loop;
      Opened := False;
      return True;
   end Delete;

end FAT;

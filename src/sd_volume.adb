with HAL.Filesystem;

with File_IO;
with Filesystem;     use Filesystem;
with Filesystem.MBR; use Filesystem.MBR;

use type File_IO.Status_Code;
use type HAL.Filesystem.Status_Code;

package body SD_Volume is

   function Is_FAT (T : Partition_Type) return Boolean;

   ------------
   -- Is_FAT --
   ------------

   function Is_FAT (T : Partition_Type) return Boolean is
   begin
      --  Values match Partitions.Fat12_Parition, Fat16_Parition,
      --  Fat16B_Parition, Fat32_CHS_Parition, Fat32_LBA_Parition,
      --  Fat16B_LBA_Parition (note the library's "Parition" spelling).
      return T in 16#01# | 16#04# | 16#06# | 16#0B# | 16#0C# | 16#0E#;
   end Is_FAT;

   -----------
   -- Mount --
   -----------

   function Mount
     (Device : not null HAL.Block_Drivers.Any_Block_Driver;
      FS     : in out Filesystem.FAT.FAT_Filesystem)
      return File_IO.Status_Code
   is
      MBR    : Master_Boot_Record;
      MBR_St : File_IO.Status_Code;
      FAT_St : HAL.Filesystem.Status_Code;
      LBA    : Block_Number := 0;
      Found  : Boolean := False;
   begin
      MBR_St := Read (Device, MBR);

      if MBR_St = File_IO.OK then
         for P in Partition_Number'Range loop
            if Valid (MBR, P) and then Is_FAT (Get_Type (MBR, P)) then
               LBA := Filesystem.MBR.LBA (MBR, P);
               Found := True;
               exit;
            end if;
         end loop;

         --  Valid MBR but no FAT entry: still try LBA 0 as a last resort.
         if not Found then
            LBA := 0;
         end if;

      elsif MBR_St = File_IO.No_MBR_Found then
         --  Superfloppy: the volume starts at the first block.
         LBA := 0;

      else
         return MBR_St;
      end if;

      FAT_St := Filesystem.FAT.Open (Device, LBA, FS);
      if FAT_St /= HAL.Filesystem.OK then
         return File_IO.No_Filesystem;
      end if;

      return File_IO.Mount_Volume ("sd", FS'Unchecked_Access);
   end Mount;

end SD_Volume;

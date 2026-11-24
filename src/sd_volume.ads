------------------------------------------------------------------------------
--  Mount the FAT volume on an SD card the way Weather_Logger does.
--
--  Filesystem.MBR.Read finds the first FAT12/16/32 partition. A card with
--  no MBR is treated as a superfloppy and opened at LBA 0. The volume is
--  registered with File_IO under the name "sd", so paths look like
--  "/sd/bootstrap".
------------------------------------------------------------------------------

with HAL.Block_Drivers;

with File_IO;
with Filesystem.FAT;

package SD_Volume is

   function Mount
     (Device : not null HAL.Block_Drivers.Any_Block_Driver;
      FS     : in out Filesystem.FAT.FAT_Filesystem)
      return File_IO.Status_Code;

end SD_Volume;

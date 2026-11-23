------------------------------------------------------------------------------
--  Read-only FAT12/16/32 on the SD card, plus deletion of one root file.
--  The file must be in the root directory. Long names are matched
--  case-insensitively. Both FAT copies are updated when a chain is freed.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

with Bytes;

package FAT is

   function Mount return Boolean;

   function Open (Name : String) return Boolean;
   --  True when Name is a regular file in the root. The read cursor is
   --  at the first byte.

   function Size return Unsigned_32;

   procedure Rewind;

   procedure Read
     (Data : out Bytes.Arr;
      Got  : out Natural;
      OK   : out Boolean);
   --  Got is 0 at end of file. OK is False on an I/O or chain error.

   function Delete return Boolean;
   --  Mark the directory entries deleted and free the cluster chain.
   --  Call this only after the bytes have been verified in flash.

end FAT;

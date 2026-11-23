------------------------------------------------------------------------------
--  SD card over SPI2, just enough to read and write one 512-byte sector.
--  PB13 SCK, PB14 MISO, PB15 MOSI, CS PB12. PB11 is held high so the
--  BME280 stays off the bus.
------------------------------------------------------------------------------

with Interfaces; use Interfaces;

package SDCard is

   type Block is array (0 .. 511) of Unsigned_8;

   function Init return Boolean;
   function Read (LBA : Unsigned_32; Data : out Block) return Boolean;
   function Write (LBA : Unsigned_32; Data : Block) return Boolean;

end SDCard;

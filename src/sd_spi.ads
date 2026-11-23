------------------------------------------------------------------------------
--  SD card over SPI, sitting on SPI_Bus (SPI2, chip-select PB12).
--
--  There is no SPI-mode SD driver in Ada_Drivers_Library; this package
--  fills that gap. It is a limited extension of HAL.Block_Drivers.Block_Driver
--  (hal/src/hal-block_drivers.ads), so a card object can be passed as
--  Any_Block_Driver to Filesystem.FAT.Open and the rest of the library
--  FAT stack (middleware/src/filesystem).
------------------------------------------------------------------------------

with HAL;               use HAL;
with HAL.Block_Drivers; use HAL.Block_Drivers;

package SD_SPI is

   type SD_Status is
     (OK,
      Timeout,
      Illegal_Command,
      CRC_Error,
      Unexpected_Response,
      Token_Error,
      Write_Rejected,
      Not_Initialized,
      Unsupported_Card);

   type SD_Card is limited new Block_Driver with private;

   procedure Initialize (This : in out SD_Card; Status : out SD_Status);
   --  SPI-mode card init at the current (slow) SPI_Bus rate: at least 74
   --  clocks with CS high, CMD0, CMD8 (pattern 16#1AA#), ACMD41 (CMD55 +
   --  ACMD41 with HCS for v2 cards), CMD58 to read OCR / CCS, and CMD16
   --  to force a 512-byte block length on byte-addressed SDSC cards.
   --  On success the SPI2 prescaler is raised to BRP_4 via
   --  SPI_Bus.Set_Prescaler (about 10.5 MHz when APB1 is 42 MHz).

   function Last_Status (This : SD_Card) return SD_Status;

   function Uses_Block_Addressing (This : SD_Card) return Boolean;
   --  True for SDHC/SDXC (CCS set in OCR). False for SDSC, which is
   --  byte-addressed; Read/Write convert the block number accordingly.

   function Block_Count (This : SD_Card) return UInt64;
   --  Number of 512-byte blocks, from CMD9/CSD. Zero if CSD was not read.

   function Read_Single
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : out UInt8_Array)
      return SD_Status
     with Pre => Data'Length = HAL.Block_Drivers.Block_Size;
   --  CMD17 plus data token 16#FE# and a 512-byte payload (CRC16 skipped).

   function Write_Single
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : UInt8_Array)
      return SD_Status
     with Pre => Data'Length = HAL.Block_Drivers.Block_Size;
   --  CMD24 plus data token 16#FE#, payload, and the data-response token.

   overriding
   function Read
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : out Block)
      return Boolean;

   overriding
   function Write
     (This         : in out SD_Card;
      Block_Number : UInt64;
      Data         : Block)
      return Boolean;

private

   type SD_Card is limited new Block_Driver with record
      Ready          : Boolean := False;
      Block_Addr     : Boolean := False;
      Blocks         : UInt64  := 0;
      Last           : SD_Status := Not_Initialized;
   end record;

end SD_SPI;

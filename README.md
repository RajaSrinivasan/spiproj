# spiproj

[![build](https://github.com/RajaSrinivasan/spiproj/actions/workflows/build.yml/badge.svg)](https://github.com/RajaSrinivasan/spiproj/actions/workflows/build.yml)

Ada firmware for the STM32F4 Discovery board (STM32F407VG). A microSD card
reader and a BME280 weather sensor share SPI2. The sources use AdaCore's
[Ada_Drivers_Library](https://github.com/AdaCore/Ada_Drivers_Library) and the
`embedded-stm32f4` GNAT ARM ELF runtime.

SPI1 (PA5, PA6, PA7) is already used by the board's LIS3DSH accelerometer, so
the external devices sit on SPI2. Both devices share SCK, MISO, and MOSI.
Each has its own chip-select, held high when idle.

## Wiring

| Signal     | Pin  | Setup                                              |
|------------|------|----------------------------------------------------|
| SPI2 SCK   | PB13 | Alternate function AF5 (`GPIO_AF_SPI2_5`)          |
| SPI2 MISO  | PB14 | Alternate function AF5                             |
| SPI2 MOSI  | PB15 | Alternate function AF5                             |
| microSD CS | PB12 | Push-pull GPIO output, idle high                   |
| BME280 CS  | PB11 | Push-pull GPIO output, idle high                   |

Power both breakouts from 3.3 V and GND. Put 10 kΩ pull-ups to 3.3 V on both
chip-selects and on MISO. Use a 3.3 V microSD breakout, or a 5 V breakout that
has its own regulator and level shifter.

![STM32F4 Discovery SPI2 wiring for the microSD reader and BME280](docs/stm32f4_spi_schematic.png)

SPI2 comes up as a mode 0 master, 8-bit, MSB first, with software-managed NSS.
The baud prescaler starts at `BRP_128` (about 328 kHz when APB1 is 42 MHz),
which is slow enough for SD card initialization. After `SD_SPI.Initialize`
succeeds it is raised to `BRP_4` (about 10.5 MHz) through `SPI_Bus.Set_Prescaler`.

`tools/draw.py` redraws the schematic with
[schemdraw](https://schemdraw.readthedocs.io/). From `docs/`:

```sh
python3 ../tools/draw.py
```

That writes `stm32f4_spi_schematic.png` in the current directory. The copy
checked in above is `docs/stm32f4_spi_schematic.png`.

## Repository layout

```
spiproj.gpr                 project file (mains, runtime, library with)
src/spi_bus.ads/.adb        SPI2 pins, chip-selects, prescaler
src/sd_spi.ads/.adb         SD card over SPI (HAL.Block_Drivers.Block_Driver)
src/bme280.ads/.adb         BME280 driver (temperature, pressure, humidity)
src/read_bme280_id.adb      main: chip-id check
src/demo_spi2.adb           main: sensor read and SD block round-trip
src/weather_logger.adb      main: CSV log on the card every 10 s
docs/stm32f4_spi_schematic.png
tools/draw.py
lib/Ada_Drivers_Library/    git submodule
```

`obj/` and `bin/` are build outputs.

## Packages

- `SPI_Bus` sets up the pins and chip-selects and changes the SPI2 prescaler.
  `STM32.SPI` has no baud-only update, so `Set_Prescaler` disables the port,
  calls `STM32.SPI.Configure` again, and re-enables it.
- `SD_SPI` initializes an SD card in SPI mode (CMD0, CMD8, ACMD41, CMD58,
  CMD16), then reads and writes single 512-byte blocks (CMD17 and CMD24).
  Commands carry a CRC7. `SD_Card` extends `HAL.Block_Drivers.Block_Driver`,
  so `Card'Access` can be passed to `Filesystem.FAT.Open`. The library itself
  has no SPI-mode SD driver. The closest pieces are the SDIO controller in
  `STM32.SDMMC` / `HAL.SDMMC` and the `SDCard` board helper, which is wired
  for other boards.
- `BME280` is a standalone driver. Ada_Drivers_Library ships `BMP280` only,
  and that package does not implement humidity and only checks that the
  chip-id is non-zero. This driver requires chip-id `16#60#`, reads the
  humidity calibration (H1 at `16#A1#`, H2–H6 at `16#E1#` .. `16#E7#`), and
  applies Bosch's integer humidity compensation (Q22.10 %RH) along with the
  library's temperature and pressure formulas. Chip-select is PB11.

## Prerequisites

- A GNAT ARM ELF toolchain (`arm-eabi`) that provides the `embedded-stm32f4`
  runtime, and `gprbuild`. These sources were built with GNAT 15.3.0 ARM ELF.
  Prebuilt archives are on the
  [GNAT-FSF-builds](https://github.com/alire-project/GNAT-FSF-builds/releases)
  releases: `gnat-arm-elf-linux64-x86_64-15.3.0-1.tar.gz` from
  `gnat-15.3.0-1`, and a host `gprbuild-*-linux-*.tar.gz` from a `gprbuild-*`
  release. Unpack both and put each `bin` directory on `PATH`.
- Or [Alire](https://alire.ada.dev/). This repository is a plain GPR project.
  Alire is only needed as a way to install the same tools, for example
  `alr install gnat_arm_elf gprbuild`, which places them under `~/.alire`.

Fetch the library submodule (once per clone):

```sh
git submodule update --init --recursive
```

`git clone --recurse-submodules` does the same thing at clone time.

The `with` in `spiproj.gpr` is a relative path to
`lib/Ada_Drivers_Library/boards/stm32f407_discovery/stm32f407_discovery_full.gpr`.
If the library is checked out somewhere else, edit that one line.

## Build

From the repository root, with `gprbuild` and `arm-eabi-gcc` / `arm-eabi-gnat`
on `PATH`:

```sh
gprbuild -P spiproj.gpr
```

That builds all three mains. Object files go to `obj/`. The ELF images go to
`bin/` and are named `weather_logger`, `demo_spi2`, and `read_bme280_id`
(no extension). To build a single main:

```sh
gprbuild -P spiproj.gpr weather_logger.adb
gprbuild -P spiproj.gpr demo_spi2.adb
gprbuild -P spiproj.gpr read_bme280_id.adb
```

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds
`weather_logger`, `demo_spi2`, and `read_bme280_id` on every push, on pull
requests, and when the workflow is dispatched by hand. The job downloads the
GNAT FSF ARM ELF 15.3.0 toolchain and GPRbuild 25.0.0 from
[GNAT-FSF-builds](https://github.com/alire-project/GNAT-FSF-builds/releases)
(the same archives named above; the tarballs are cached between runs),
checks out `lib/Ada_Drivers_Library` with its submodules, and runs
`gprbuild -P spiproj.gpr`. The images are uploaded as the `stm32f4-images`
artifact: `weather_logger.elf` and `.bin`, `demo_spi2.elf` and `.bin`, and
`read_bme280_id.elf` and `.bin`. The `.elf` files are the extensionless
`bin/` programs with a suffix added. The `.bin` files come from
`arm-eabi-objcopy -O binary`.

## Flash

Each main is a separate image. Flash one of them to internal flash at
`0x08000000`. The Discovery's on-board ST-LINK is the debug probe.

Turn the ELF into a raw binary with `arm-eabi-objcopy`, then write it with
either `st-flash` (from the [stlink](https://github.com/stlink-org/stlink)
tools) or OpenOCD. Example for the weather logger:

```sh
arm-eabi-objcopy -O binary bin/weather_logger bin/weather_logger.bin
st-flash --reset write bin/weather_logger.bin 0x08000000
```

```sh
arm-eabi-objcopy -O binary bin/weather_logger bin/weather_logger.bin
openocd -f board/stm32f4discovery.cfg \
  -c "program bin/weather_logger.bin 0x08000000 verify reset exit"
```

OpenOCD can also program the ELF directly:

```sh
openocd -f board/stm32f4discovery.cfg \
  -c "program bin/weather_logger verify reset exit"
```

Use the same commands with `bin/demo_spi2` or `bin/read_bme280_id`.

The board has no console unless you add a USART or semihosting yourself.
The mains report through the user LEDs.

## Mains and LEDs

### `read_bme280_id`

Reads the BME280 chip-id register (`16#D0#`; the read bit is already set) and
expects `16#60#`.

- Green LED: the id matches.
- Red LED: the id does not match.

The LED stays on. This main does not touch the SD card.

### `demo_spi2`

Initializes the BME280 and the microSD card, reads temperature, pressure, and
humidity, writes one 512-byte pattern to the card, reads it back, and writes
the original bytes back. The block used is the last block reported by the
CSD.

- Green LED, solid: every step succeeded.
- Red LED, solid: a step failed. The program stops.

### `weather_logger`

Mounts the card's FAT volume and, every 10 seconds, appends one BME280 sample
to `/sd/WEATHER.CSV`. The header

```text
seconds,temp_c,pressure_pa,humidity_pct
```

is written only when the file is new (size 0). Temperature and humidity are
written with two decimal places. Pressure is stored by the driver in hPa and
converted to pascals for the `pressure_pa` column.

- Green LED: a short blink after each successful write.
- Red LED, solid: the card, the mount, or a write failed. Logging stops.

`File_IO` has no append mode, and opening a file `Write_Only` truncates it.
The logger opens `Read_Write` (which creates the file when it is missing),
seeks to the end when the file already has data, writes one line, and closes.
Close flushes the directory entry, so a power cut loses at most the line in
progress.

The `embedded-stm32f4` runtime includes `Ada.Text_IO` and does not include
`Ada.Text_IO.Float_IO`, so the CSV numbers are formatted by hand.

## Caveats

- The BME280 driver is standalone because Ada_Drivers_Library ships BMP280
  only.
- SD-over-SPI does not check data CRC16 (command frames still carry CRC7, and
  CMD59 stays off). Reads and writes are single-block transfers only.
- The card must already be formatted FAT12, FAT16, or FAT32, either with an
  MBR or as a superfloppy. The logger does not format a blank card.
- The `seconds` column is time since boot (elapsed seconds from the start of
  the logging loop), not wall-clock time.
- `demo_spi2` temporarily overwrites the card's last block. It restores that
  block when the test finishes, and it does not write block 0. A power loss
  in the middle of the test can leave the last block overwritten.
- If transfers are flaky at `BRP_4`, change the prescaler in
  `SD_SPI.Initialize` from `BRP_4` to `BRP_8`.

# Build the application images and the bootloader.
#
# Each link replaces the runtime's common-ROM.ld, so both builds pass
# -XLOADER=USER. The bootloader uses the light runtime and does not share
# the application's object files.

.PHONY: all app boot

all: app boot

app:
	gprbuild -P spiproj.gpr -XLOADER=USER -j$$(nproc)

boot:
	gprbuild -P bootloader.gpr -XLOADER=USER -j$$(nproc)

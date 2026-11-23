# Build the application images and the bootloader.
#
# The runtime linker script is replaced with ld/app_rom.ld or
# ld/boot_rom.ld, which requires the runtime's USER loader. The two
# gprbuild invocations are sequential: they share the Ada_Drivers_Library
# archive.

.PHONY: all app boot

all: app boot

app:
	gprbuild -P spiproj.gpr -XLOADER=USER -XIMAGE=app -j$$(nproc)

boot: app
	gprbuild -P spiproj.gpr -XLOADER=USER -XIMAGE=boot -j$$(nproc)

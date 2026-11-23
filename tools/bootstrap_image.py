#!/usr/bin/env python3
"""Pack, check, and describe an SD-card bootstrap image.

The file the bootloader looks for is named "bootstrap" and lives at the
root of the FAT volume. It is a 32-byte little-endian header followed by
the raw application image from arm-eabi-objcopy -O binary:

    offset  size  field
    0       4     magic ASCII "SPB1"
    4       4     header length (32)
    8       4     payload length
    12      4     load address (the application origin)
    16      4     STM32 CRC-32 of the payload
    20      4     STM32 CRC-32 of bytes 0..19
    24      8     reserved, must be zero
    32      N     payload, vector table first

The CRC is the STM32 unit (tools/elf_hashes.py): a corruption check, not a
signature. The load address and the payload's reset vector must agree with
ld/layout_symbols.ld. A binary linked at 0x08000000 is rejected.

The flash windows below are the same numbers as ld/layout_symbols.ld.
"""

import struct
import sys

from elf_hashes import PT_LOAD, crc32_stm32, parse_elf

MAGIC = b"SPB1"
HEADER_BYTES = 32
HEADER_CRC_BYTES = 20

# ld/layout_symbols.ld
BOOT_ORIGIN = 0x08000000
BOOT_LENGTH = 0x00010000
APP_ORIGIN = 0x08010000
APP_LENGTH = 0x000F0000

SRAM_ORIGIN = 0x20000000
SRAM_LIMIT = 0x20020000


def _prefix(payload: bytes, load_addr: int) -> bytes:
    payload_crc = crc32_stm32(payload)
    return struct.pack(
        "<4sIIII", MAGIC, HEADER_BYTES, len(payload), load_addr, payload_crc
    )


def vector_error(payload: bytes, load_addr: int) -> str | None:
    if len(payload) < 8:
        return "payload is shorter than a vector table"
    sp, reset = struct.unpack_from("<II", payload, 0)
    if sp < SRAM_ORIGIN + 8 or sp > SRAM_LIMIT or sp % 8 != 0:
        return f"initial stack pointer {sp:#010x} is not in main SRAM"
    if reset % 2 == 0:
        return f"reset vector {reset:#010x} is not a Thumb address"
    target = reset & ~1
    end = load_addr + len(payload)
    if target < load_addr or target >= end:
        return (
            f"reset handler {target:#010x} is outside "
            f"[{load_addr:#010x}, {end:#010x})"
        )
    return None


def pack(payload: bytes, load_addr: int) -> bytes:
    if load_addr != APP_ORIGIN:
        raise SystemExit(
            f"load address {load_addr:#010x} is not the application origin "
            f"{APP_ORIGIN:#010x}"
        )
    if len(payload) > APP_LENGTH:
        raise SystemExit(
            f"payload is {len(payload)} bytes, application window is {APP_LENGTH}"
        )
    problem = vector_error(payload, load_addr)
    if problem:
        raise SystemExit(problem)
    prefix = _prefix(payload, load_addr)
    header_crc = crc32_stm32(prefix)
    header = prefix + struct.pack("<III", header_crc, 0, 0)
    if len(header) != HEADER_BYTES:
        raise SystemExit("header is not 32 bytes")
    return header + payload


def check(blob: bytes) -> str | None:
    """Return an error string, or None when blob is a valid bootstrap."""
    if len(blob) < HEADER_BYTES:
        return "file is shorter than the header"
    magic, header_bytes, payload_bytes, load_addr, payload_crc = struct.unpack_from(
        "<4sIIII", blob, 0
    )
    header_crc, reserved_0, reserved_1 = struct.unpack_from("<III", blob, 20)
    if magic != MAGIC:
        return "bad magic"
    if header_bytes != HEADER_BYTES or reserved_0 != 0 or reserved_1 != 0:
        return "bad header"
    if crc32_stm32(blob[:HEADER_CRC_BYTES]) != header_crc:
        return "bad header crc"
    if load_addr != APP_ORIGIN:
        return f"load address {load_addr:#010x} is not {APP_ORIGIN:#010x}"
    if payload_bytes < 8 or payload_bytes > APP_LENGTH:
        return "bad payload length"
    if len(blob) != HEADER_BYTES + payload_bytes:
        return "file size does not match the header"
    payload = blob[HEADER_BYTES:]
    if crc32_stm32(payload) != payload_crc:
        return "bad payload crc"
    return vector_error(payload, load_addr)


def check_elf(path: str, role: str) -> None:
    if role == "app":
        origin, length = APP_ORIGIN, APP_LENGTH
    elif role == "boot":
        origin, length = BOOT_ORIGIN, BOOT_LENGTH
    else:
        raise SystemExit(f"unknown role {role}")
    limit = origin + length
    with open(path, "rb") as fh:
        blob = fh.read()
    _, phdrs = parse_elf(blob)
    flash = [
        ph for ph in phdrs
        if ph["p_type"] == PT_LOAD and ph["p_filesz"] > 0 and ph["p_paddr"] >= 0x08000000
    ]
    if not flash:
        raise SystemExit(f"{path}: no flash PT_LOAD")
    start = min(ph["p_paddr"] for ph in flash)
    end = max(ph["p_paddr"] + ph["p_filesz"] for ph in flash)
    if start != origin:
        raise SystemExit(
            f"{path}: flash starts at {start:#010x}, expected {origin:#010x}"
        )
    if end > limit:
        raise SystemExit(
            f"{path}: flash ends at {end:#010x}, window ends at {limit:#010x}"
        )
    seg = min(flash, key=lambda ph: ph["p_paddr"])
    sp, reset = struct.unpack_from("<II", blob, seg["p_offset"])
    problem = vector_error(blob[seg["p_offset"]:seg["p_offset"] + (end - start)], origin)
    # vector_error only needs the first 8 bytes; the slice above is the whole
    # image so the reset handler must fall inside what was actually linked.
    if problem:
        raise SystemExit(f"{path}: {problem} (sp={sp:#010x} reset={reset:#010x})")
    print(
        f"{path}: {role} {start:#010x}..{end:#010x} "
        f"({end - start} bytes) sp={sp:#010x} reset={reset:#010x}"
    )


def self_test() -> None:
    from elf_hashes import TAIL_010203, WORD_12345678, self_test as crc_self_test

    crc_self_test()
    if crc32_stm32(bytes.fromhex("78563412")) != WORD_12345678:
        raise SystemExit("word crc drifted from elf_hashes")
    if crc32_stm32(b"\x01\x02\x03") != TAIL_010203:
        raise SystemExit("tail crc drifted from elf_hashes")

    # Reset handler sits 16 bytes into the payload, Thumb bit set.
    payload = struct.pack("<II", SRAM_LIMIT, (APP_ORIGIN + 16) | 1) + bytes(32)
    good = pack(payload, APP_ORIGIN)
    if check(good) is not None:
        raise SystemExit(f"good image rejected: {check(good)}")
    if good[:4] != MAGIC or len(good) != HEADER_BYTES + len(payload):
        raise SystemExit("packed layout is wrong")

    bad_magic = b"XXXX" + good[4:]
    if check(bad_magic) != "bad magic":
        raise SystemExit("bad magic was accepted")

    flipped = bytearray(good)
    flipped[-1] ^= 0xFF
    if check(bytes(flipped)) != "bad payload crc":
        raise SystemExit("corrupt payload was accepted")

    short = good[:16]
    if check(short) is None:
        raise SystemExit("truncated file was accepted")

    try:
        pack(payload, BOOT_ORIGIN)
    except SystemExit:
        pass
    else:
        raise SystemExit("pack accepted the bootloader origin")

    # A reset vector that points at the low window must not pack.
    misplaced = struct.pack("<II", SRAM_LIMIT, BOOT_ORIGIN + 0x101) + bytes(32)
    try:
        pack(misplaced, APP_ORIGIN)
    except SystemExit as exc:
        if "reset handler" not in str(exc):
            raise
    else:
        raise SystemExit("pack accepted a reset vector in the bootloader")

    print("self-test ok")


def main(argv: list[str]) -> None:
    if len(argv) == 2 and argv[1] == "--self-test":
        self_test()
        return
    if len(argv) == 4 and argv[1] == "pack":
        with open(argv[2], "rb") as fh:
            payload = fh.read()
        image = pack(payload, APP_ORIGIN)
        with open(argv[3], "wb") as fh:
            fh.write(image)
        print(
            f"wrote {argv[3]} ({len(image)} bytes, "
            f"payload {len(payload)} at {APP_ORIGIN:#010x})"
        )
        return
    if len(argv) == 3 and argv[1] == "check":
        with open(argv[2], "rb") as fh:
            blob = fh.read()
        problem = check(blob)
        if problem:
            raise SystemExit(f"{argv[2]}: {problem}")
        print(f"{argv[2]}: ok ({len(blob)} bytes)")
        return
    if len(argv) == 4 and argv[1] == "check-elf":
        check_elf(argv[2], argv[3])
        return
    raise SystemExit(
        f"usage: {argv[0]} --self-test\n"
        f"       {argv[0]} pack APP.bin bootstrap\n"
        f"       {argv[0]} check bootstrap\n"
        f"       {argv[0]} check-elf FILE.elf app|boot"
    )


if __name__ == "__main__":
    main(sys.argv)

#!/usr/bin/env python3
"""STM32 CRC-32 of the flash images in an ELF file.

Matches Flash_CRC on the board: polynomial 0x04C11DB7, init 0xFFFFFFFF,
no reflection, no final XOR. Each 32-bit word is a little-endian load.
A 1..3 byte tail is packed into the low bytes of a zero-padded word.
This is a corruption check, not a cryptographic hash.

The printed lines use the same fields as a weather_logger HASH line, without
the sample number and without the REF/OK/MISMATCH status:

    HASH:text:<start_hex>:<length_hex>:<crc_hex>
    HASH:rodata:<start_hex>:<length_hex>:<crc_hex>
    HASH:data_lma:<start_hex>:<length_hex>:<crc_hex>

start_hex for data_lma is the ELF load address (p_paddr), which is
__data_lma_start, not the RAM VMA.
"""

import struct
import sys

POLY = 0x04C11DB7
INIT = 0xFFFFFFFF

# CRC of the single little-endian word 0x12345678. This is the value the
# STM32F4 CRC unit leaves in CRC_DR after a reset and that one write.
WORD_12345678 = 0xDF8A8A2B
TAIL_010203 = 0x615EAB4A

PT_LOAD = 1
SHT_PROGBITS = 1
SHT_NOBITS = 8


def crc32_stm32(data: bytes) -> int:
    crc = INIT
    whole = len(data) - (len(data) % 4)
    for offset in range(0, whole, 4):
        crc = _step(crc, int.from_bytes(data[offset:offset + 4], "little"))
    tail = data[whole:]
    if tail:
        crc = _step(crc, int.from_bytes(tail, "little"))
    return crc


def _step(crc: int, word: int) -> int:
    crc = (crc ^ word) & INIT
    for _ in range(32):
        if crc & 0x80000000:
            crc = ((crc << 1) ^ POLY) & INIT
        else:
            crc = (crc << 1) & INIT
    return crc


def self_test() -> None:
    if crc32_stm32(bytes.fromhex("78563412")) != WORD_12345678:
        raise SystemExit("self-test failed: word 0x12345678")
    if crc32_stm32(b"") != INIT:
        raise SystemExit("self-test failed: empty input")
    if crc32_stm32(b"\x01\x02\x03") != TAIL_010203:
        raise SystemExit("self-test failed: 3-byte tail")


def _u(fmt: str, blob: bytes, offset: int):
    return struct.unpack_from("<" + fmt, blob, offset)[0]


def parse_elf(blob: bytes):
    if blob[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file")
    if blob[4] != 1 or blob[5] != 1:
        raise SystemExit("need a 32-bit little-endian ELF")
    e_phoff = _u("I", blob, 28)
    e_shoff = _u("I", blob, 32)
    e_phentsize = _u("H", blob, 42)
    e_phnum = _u("H", blob, 44)
    e_shentsize = _u("H", blob, 46)
    e_shnum = _u("H", blob, 48)
    e_shstrndx = _u("H", blob, 50)

    phdrs = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        phdrs.append({
            "p_type": _u("I", blob, off),
            "p_offset": _u("I", blob, off + 4),
            "p_vaddr": _u("I", blob, off + 8),
            "p_paddr": _u("I", blob, off + 12),
            "p_filesz": _u("I", blob, off + 16),
            "p_memsz": _u("I", blob, off + 20),
        })

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sections.append({
            "sh_name": _u("I", blob, off),
            "sh_type": _u("I", blob, off + 4),
            "sh_addr": _u("I", blob, off + 12),
            "sh_offset": _u("I", blob, off + 16),
            "sh_size": _u("I", blob, off + 20),
        })

    strtab = sections[e_shstrndx]
    names = blob[strtab["sh_offset"]:strtab["sh_offset"] + strtab["sh_size"]]
    for sec in sections:
        end = names.index(b"\x00", sec["sh_name"])
        sec["name"] = names[sec["sh_name"]:end].decode("ascii")
    return sections, phdrs


def load_addr(section, phdrs) -> int:
    vma = section["sh_addr"]
    size = section["sh_size"]
    for ph in phdrs:
        if ph["p_type"] != PT_LOAD:
            continue
        span = ph["p_memsz"]
        if span == 0:
            continue
        if ph["p_vaddr"] <= vma and vma + size <= ph["p_vaddr"] + span:
            return ph["p_paddr"] + (vma - ph["p_vaddr"])
    raise SystemExit(f"no PT_LOAD covers {section['name']}")


def section_bytes(blob: bytes, section) -> bytes:
    if section["sh_type"] == SHT_NOBITS:
        raise SystemExit(f"{section['name']} has no file bytes")
    if section["sh_type"] != SHT_PROGBITS:
        raise SystemExit(f"{section['name']} is not PROGBITS")
    off = section["sh_offset"]
    size = section["sh_size"]
    return blob[off:off + size]


def main(argv: list[str]) -> None:
    if len(argv) == 2 and argv[1] == "--self-test":
        self_test()
        print("self-test ok")
        return
    if len(argv) != 2:
        raise SystemExit(f"usage: {argv[0]} --self-test | {argv[0]} FILE.elf")

    self_test()
    path = argv[1]
    with open(path, "rb") as fh:
        blob = fh.read()
    sections, phdrs = parse_elf(blob)
    by_name = {sec["name"]: sec for sec in sections}

    print(f"# {path}")
    print("# STM32 CRC-32 poly=0x04C11DB7 init=0xFFFFFFFF "
          "refin=0 refout=0 xorout=0x00000000")
    print("# little-endian 32-bit loads; corruption check, not a cryptographic hash")

    wanted = (("text", ".text"), ("rodata", ".rodata"), ("data_lma", ".data"))
    for label, name in wanted:
        if name not in by_name:
            raise SystemExit(f"ELF has no {name} section")
        sec = by_name[name]
        data = section_bytes(blob, sec)
        if len(data) != sec["sh_size"]:
            raise SystemExit(f"short read of {name}")
        start = load_addr(sec, phdrs)
        digest = crc32_stm32(data)
        print(f"HASH:{label}:{start:08X}:{sec['sh_size']:08X}:{digest:08X}")


if __name__ == "__main__":
    main(sys.argv)

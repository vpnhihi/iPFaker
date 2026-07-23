#!/usr/bin/env python3
"""
Lab patch: NOP HIOS ChangeInfoIosMG.dylib license gate (UNLICENSED → inert).

HIOS MG checks a license bit and if clear jumps to:
  log "ctor %s UNLICENSED → inert (no C hooks...)" then early-return.
That makes spoof dead without a valid HIOS key.

We NOP the single `tbz w8, #0, <unlicensed>` in each fat slice so hooks always run.
Original saved as ChangeInfoIosMG.dylib.orig
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs

ROOT = Path(__file__).resolve().parents[1]
MG = ROOT / "vendor" / "hios_426" / "dylibs" / "ChangeInfoIosMG.dylib"
NOP = bytes.fromhex("1f2003d5")  # ARM64 NOP


def parse_text(sliceb: bytes):
    ncmds = struct.unpack("<I", sliceb[16:20])[0]
    cursor = 32
    text_off = text_size = text_addr = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", sliceb[cursor : cursor + 8])
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack("<I", sliceb[cursor + 64 : cursor + 68])[0]
            so = cursor + 72
            for _s in range(nsects):
                secname = sliceb[so : so + 16].split(b"\x00")[0]
                saddr, ssize = struct.unpack("<QQ", sliceb[so + 32 : so + 48])
                soff = struct.unpack("<I", sliceb[so + 48 : so + 52])[0]
                if secname == b"__text":
                    text_off, text_size, text_addr = soff, ssize, saddr
                so += 80
        cursor += cmdsize
    return text_off, text_size, text_addr


def main() -> int:
    if not MG.is_file():
        print("missing", MG, file=sys.stderr)
        return 1
    raw = bytearray(MG.read_bytes())
    if raw[:4] != bytes.fromhex("cafebabe"):
        print("not a fat Mach-O", file=sys.stderr)
        return 2

    orig = MG.with_suffix(".dylib.orig")
    if not orig.exists():
        # Prefer pure original from import root if present
        pure = ROOT / "vendor" / "hios_426" / "root" / "var" / "jb" / "Library" / "MobileSubstrate" / "DynamicLibraries" / "ChangeInfoIosMG.dylib"
        if pure.is_file():
            orig.write_bytes(pure.read_bytes())
            raw = bytearray(pure.read_bytes())
            print("backup from vendor root pure →", orig)
        else:
            orig.write_bytes(bytes(raw))
            print("backup current →", orig)
    else:
        # Always patch from orig so re-run is idempotent
        raw = bytearray(orig.read_bytes())
        print("load from", orig)

    n = struct.unpack(">I", raw[4:8])[0]
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    patched = 0

    for i in range(n):
        hdr = 8 + i * 20
        _ct, _cs, offset, size, _al = struct.unpack(">IIIII", raw[hdr : hdr + 20])
        sliceb = bytes(raw[offset : offset + size])
        text_off, text_size, text_addr = parse_text(sliceb)
        if text_off is None:
            print(f"slice{i}: no __text")
            continue
        text = sliceb[text_off : text_off + text_size]
        # Find UNLICENSED format pageoff for this slice
        pos = sliceb.find(b"ctor %s UNLICENSED")
        if pos < 0:
            print(f"slice{i}: no UNLICENSED string")
            continue
        # Find tbz w8,#0 that lands on block loading that string
        for ins in md.disasm(text, text_addr):
            if ins.mnemonic != "tbz" or "w8" not in ins.op_str:
                continue
            if ", #0," not in ins.op_str and ", #0x0," not in ins.op_str:
                # only bit 0
                if "#0," not in ins.op_str.replace(" ", ""):
                    continue
            try:
                tgt = int(ins.op_str.split("#")[-1].strip(), 0)
            except ValueError:
                continue
            toff = tgt - text_addr
            if toff < 0 or toff >= text_size:
                continue
            region = text[toff : toff + 0x28]
            hit = False
            for r in md.disasm(region, tgt):
                if r.mnemonic == "add" and "x0" in r.op_str and "#" in r.op_str:
                    # verify nearby string is UNLICENSED via checking bl after
                    hit = True
                    break
            # Confirm target sequence: ldr x21; ldr x0; bl; stp; adrp; add (UNLICENSED)
            regs = list(md.disasm(region, tgt))
            if len(regs) < 6:
                continue
            if regs[0].mnemonic != "ldr" or regs[4].mnemonic != "adrp":
                continue
            # pageoff of UNLICENSED load
            add_ins = regs[5]
            if add_ins.mnemonic != "add":
                continue
            # Patch this tbz
            ioff = ins.address - text_addr
            abs_off = offset + text_off + ioff
            old = bytes(raw[abs_off : abs_off + 4])
            raw[abs_off : abs_off + 4] = NOP
            print(
                f"slice{i}: NOP tbz @ {hex(ins.address)} file+{abs_off} "
                f"old={old.hex()} → licensed path always"
            )
            patched += 1
            break

    if patched != 2:
        print(f"WARN: expected 2 slice patches, got {patched}", file=sys.stderr)
        if patched == 0:
            return 3

    MG.write_bytes(bytes(raw))
    print("wrote", MG, "size", len(raw))
    print("OK license gate patched (lab). Orig:", orig)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

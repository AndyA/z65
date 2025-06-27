# /// script
# requires-python = ">=3.13"
# dependencies = []
# ///

import os
from dataclasses import dataclass
from functools import cached_property
from typing import Callable

MODES = {"adc_cc", "adc_cs", "sbc_cc", "sbc_cs"}


def load_ref(mode: str, prefix: str) -> bytes:
    parts: list[bytes] = []
    for part in range(8):
        name = os.path.join("ref", mode, f"{prefix}{part}")
        with open(name, "rb") as f:
            parts.append(f.read())
    return b"".join(parts)


@dataclass(kw_only=True, frozen=True)
class Results:
    table: bytes

    def result(self, a: int, b: int) -> int:
        if 0 <= a < 256 and 0 <= b < 256:
            return self.table[a + b * 256]
        raise ValueError("a and b must be in the range [0, 255]")


@dataclass(kw_only=True, frozen=True)
class Reference:
    mode: str

    @cached_property
    def res(self) -> Results:
        return Results(table=load_ref(self.mode, "W.RES"))

    @cached_property
    def pst(self) -> Results:
        return Results(table=load_ref(self.mode, "W.PST"))

    def result(self, a: int, b: int) -> tuple[int, int]:
        return self.res.result(a, b), self.pst.result(a, b)


def format_flags(flags: int) -> str:
    off_flags = "nv0bdizc"
    on_flags = "NV1BDIZC"
    parts = [
        on_flags[bit] if flags & (1 << (7 - bit)) else off_flags[bit]
        for bit in range(8)
    ]
    return "".join(parts)


# ref = {mode: Reference(mode=mode) for mode in MODES}
# for mode in MODES:
#     for a in range(256):
#         for b in range(256):
#             res, pst = ref[mode].result(a, b)
#             rec: dict[str, str] = {
#                 "mode": mode,
#                 "a": f"{a:02x}",
#                 "b": f"{b:02x}",
#                 "res": f"{res:02x}",
#                 "pst": format_flags(pst),
#             }
#             print(json.dumps(rec, separators=(",", ":")))


def from_bcd(byte: int) -> int:
    return (byte & 0x0F) + ((byte >> 4) & 0x0F) * 10


def to_bcd(byte: int) -> int:
    return (byte // 100 % 10) << 8 | (byte // 10 % 10) << 4 | (byte % 10)


def adc(a: int, b: int, c_in: int) -> tuple[int, int]:
    bin_res = (a + b + c_in) & 0xFF
    z_bit = Z_BIT if bin_res == 0 else 0

    dr_hi = 0
    dr_lo = (a & 0x0F) + (b & 0x0F) + c_in
    if dr_lo > 9:
        dr_lo -= 10
        dr_lo &= 0x0F
        dr_hi = 1

    dr_hi += (a >> 4) + (b >> 4)

    n_bit = N_BIT if dr_hi & 0x08 else 0
    v_bit = V_BIT if ((a ^ b) & 0x80) == 0 and ((a ^ (dr_hi << 4)) & 0x80) else 0
    c_bit = 0

    if dr_hi > 9:
        c_bit = C_BIT
        dr_hi -= 10
        dr_hi &= 0x0F

    res = (dr_lo & 0x0F) | (dr_hi << 4)

    return res, c_bit | z_bit | n_bit | v_bit


def sbc(a: int, b: int, c_in: int) -> tuple[int, int]:
    bin_res = a - b - 1 + c_in
    dr_lo = (a & 0x0F) - (b & 0x0F) - 1 + c_in
    dr_hi = (a >> 4) - (b >> 4)

    if dr_lo & 0x10:
        dr_lo = (dr_lo - 6) & 0x0F
        dr_hi -= 1

    if dr_hi & 0x10:
        dr_hi = (dr_hi - 6) & 0x0F

    n_bit = N_BIT if bin_res & 0x80 else 0
    z_bit = Z_BIT if bin_res & 0xFF == 0 else 0
    v_bit = V_BIT if (a ^ bin_res) & (b ^ a) & 0x80 else 0
    c_bit = C_BIT if bin_res & 0x100 == 0 else 0

    return dr_lo | (dr_hi << 4), c_bit | z_bit | n_bit | v_bit


C_BIT = 1 << 0
Z_BIT = 1 << 1
I_BIT = 1 << 2
D_BIT = 1 << 3
B_BIT = 1 << 4
V_BIT = 1 << 6
N_BIT = 1 << 7


def check(mode: str, fn: Callable[[int, int], tuple[int, int]], valid: int) -> None:
    ref = Reference(mode=mode)
    print(f"Checking {mode}...")
    for a in range(256):
        for b in range(256):
            w_res, w_pst = ref.result(a, b)
            g_res, g_pst = fn(a, b)
            if w_res != g_res or w_pst & valid != g_pst & valid:
                print(
                    f"Mismatch for {mode}: a={a:02x}, b={b:02x}, "
                    f"expected res={w_res:02x}, pst={format_flags(w_pst)}, "
                    f"got res={g_res:02x}, pst={format_flags(g_pst)}"
                )


valid = C_BIT | Z_BIT | N_BIT | V_BIT
check("adc_cc", lambda a, b: adc(a, b, 0), valid)
check("adc_cs", lambda a, b: adc(a, b, 1), valid)
check("sbc_cc", lambda a, b: sbc(a, b, 0), valid)
check("sbc_cs", lambda a, b: sbc(a, b, 1), valid)

# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "tabulate",
# ]
# ///
from dataclasses import dataclass
from functools import cached_property
from typing import Callable, Optional, Self

from tabulate import tabulate

M6502 = {
    "LDA #": 0xA9,
    "LDA (zpg, X)": 0xA1,
    "LDA abs": 0xAD,
    "LDA abs, X": 0xBD,
    "LDA abs, Y": 0xB9,
    "LDA (zpg), Y": 0xB1,
    "LDA zpg": 0xA5,
    "LDA zpg, X": 0xB5,
    "LDX #": 0xA2,
    "LDX abs": 0xAE,
    "LDX abs, Y": 0xBE,
    "LDX zpg": 0xA6,
    "LDX zpg, Y": 0xB6,
    "LDY #": 0xA0,
    "LDY abs": 0xAC,
    "LDY abs, X": 0xBC,
    "LDY zpg": 0xA4,
    "LDY zpg, X": 0xB4,
    "STA (zpg, X)": 0x81,
    "STA abs": 0x8D,
    "STA abs, X": 0x9D,
    "STA abs, Y": 0x99,
    "STA (zpg), Y": 0x91,
    "STA zpg": 0x85,
    "STA zpg, X": 0x95,
    "STX abs": 0x8E,
    "STX zpg": 0x86,
    "STX zpg, Y": 0x96,
    "STY abs": 0x8C,
    "STY zpg": 0x84,
    "STY zpg, X": 0x94,
    "PHA": 0x48,
    "PLA": 0x68,
    "PHP": 0x08,
    "PLP": 0x28,
    "TAX": 0xAA,
    "TXA": 0x8A,
    "TAY": 0xA8,
    "TYA": 0x98,
    "TSX": 0xBA,
    "TXS": 0x9A,
    "AND #": 0x29,
    "AND (zpg, X)": 0x21,
    "AND abs": 0x2D,
    "AND abs, X": 0x3D,
    "AND abs, Y": 0x39,
    "AND (zpg), Y": 0x31,
    "AND zpg": 0x25,
    "AND zpg, X": 0x35,
    "EOR #": 0x49,
    "EOR (zpg, X)": 0x41,
    "EOR abs": 0x4D,
    "EOR abs, X": 0x5D,
    "EOR abs, Y": 0x59,
    "EOR (zpg), Y": 0x51,
    "EOR zpg": 0x45,
    "EOR zpg, X": 0x55,
    "ORA #": 0x09,
    "ORA (zpg, X)": 0x01,
    "ORA abs": 0x0D,
    "ORA abs, X": 0x1D,
    "ORA abs, Y": 0x19,
    "ORA (zpg), Y": 0x11,
    "ORA zpg": 0x05,
    "ORA zpg, X": 0x15,
    "BIT abs": 0x2C,
    "BIT zpg": 0x24,
    "ADC #": 0x69,
    "ADC (zpg, X)": 0x61,
    "ADC abs": 0x6D,
    "ADC abs, X": 0x7D,
    "ADC abs, Y": 0x79,
    "ADC (zpg), Y": 0x71,
    "ADC zpg": 0x65,
    "ADC zpg, X": 0x75,
    "SBC #": 0xE9,
    "SBC (zpg, X)": 0xE1,
    "SBC abs": 0xED,
    "SBC abs, X": 0xFD,
    "SBC abs, Y": 0xF9,
    "SBC (zpg), Y": 0xF1,
    "SBC zpg": 0xE5,
    "SBC zpg, X": 0xF5,
    "CMP #": 0xC9,
    "CMP (zpg, X)": 0xC1,
    "CMP abs": 0xCD,
    "CMP abs, X": 0xDD,
    "CMP abs, Y": 0xD9,
    "CMP (zpg), Y": 0xD1,
    "CMP zpg": 0xC5,
    "CMP zpg, X": 0xD5,
    "CPX #": 0xE0,
    "CPX abs": 0xEC,
    "CPX zpg": 0xE4,
    "CPY #": 0xC0,
    "CPY abs": 0xCC,
    "CPY zpg": 0xC4,
    "ASL abs": 0x0E,
    "ASL abs, X": 0x1E,
    "ASL zpg": 0x06,
    "ASL zpg, X": 0x16,
    "ASLA": 0x0A,
    "LSR abs": 0x4E,
    "LSR abs, X": 0x5E,
    "LSR zpg": 0x46,
    "LSR zpg, X": 0x56,
    "LSRA": 0x4A,
    "ROL abs": 0x2E,
    "ROL abs, X": 0x3E,
    "ROL zpg": 0x26,
    "ROL zpg, X": 0x36,
    "ROLA": 0x2A,
    "ROR abs": 0x6E,
    "ROR abs, X": 0x7E,
    "ROR zpg": 0x66,
    "ROR zpg, X": 0x76,
    "RORA": 0x6A,
    "DEC abs": 0xCE,
    "DEC abs, X": 0xDE,
    "DEC zpg": 0xC6,
    "DEC zpg, X": 0xD6,
    "INC abs": 0xEE,
    "INC abs, X": 0xFE,
    "INC zpg": 0xE6,
    "INC zpg, X": 0xF6,
    "DEX": 0xCA,
    "DEY": 0x88,
    "INX": 0xE8,
    "INY": 0xC8,
    "CLC": 0x18,
    "SEC": 0x38,
    "CLI": 0x58,
    "SEI": 0x78,
    "CLV": 0xB8,
    "CLD": 0xD8,
    "SED": 0xF8,
    "BPL rel": 0x10,
    "BMI rel": 0x30,
    "BVC rel": 0x50,
    "BVS rel": 0x70,
    "BCC rel": 0x90,
    "BCS rel": 0xB0,
    "BNE rel": 0xD0,
    "BEQ rel": 0xF0,
    "JSR abs": 0x20,
    "JMP abs": 0x4C,
    "JMP (abs)*": 0x6C,
    "RTS": 0x60,
    "BRK": 0x00,
    "RTI": 0x40,
    "NOP": 0xEA,
}


@dataclass(kw_only=True, frozen=True)
class Instruction:
    mnemonic: str
    opcode: int
    address_mode: str

    @classmethod
    def from_instr(cls, instr: str, opcode: int) -> "Instruction":
        parts = instr.split(" ", 1)
        if len(parts) == 1:
            mnemonic = parts[0]
            address_mode = "impl"
        else:
            mnemonic, address_mode = parts
        return cls(mnemonic=mnemonic, opcode=opcode, address_mode=address_mode)


@dataclass(kw_only=True, frozen=True)
class InstructionSet:
    instructions: list[Instruction]

    def _index_by(
        self, key: Callable[[Instruction], str]
    ) -> dict[str, list[Instruction]]:
        index: dict[str, list[Instruction]] = {}
        for instr in self.instructions:
            slot = index.setdefault(key(instr), [])  # type: ignore
            slot.append(instr)  # type: ignore
        return index

    @cached_property
    def by_mnemonic(self) -> dict[str, list[Instruction]]:
        return self._index_by(lambda instr: instr.mnemonic)

    @cached_property
    def by_address_mode(self) -> dict[str, list[Instruction]]:
        return self._index_by(lambda instr: instr.address_mode or "none")

    def for_mnemonic(self, mnem: str) -> Self:
        return self.__class__(instructions=self.by_mnemonic[mnem])

    def lookup(self, mnem: str, addr_mode: str) -> Optional[Instruction]:
        return self.for_mnemonic(mnem).by_address_mode.get(addr_mode, [None])[0]


def fmt_opcode(mnemonic: str, addr_mode: str) -> str:
    """Format the opcode for display."""
    instr = machine.lookup(mnemonic, addr_mode)
    if instr is None:
        return ""
    return f"{instr.opcode:02X}"


instruction_list = [
    Instruction.from_instr(instr, opcode)
    for instr, opcode in sorted(M6502.items(), key=lambda item: item[1])
]

machine = InstructionSet(instructions=instruction_list)

sta = machine.by_mnemonic["STA"]
addr_modes = {i.address_mode for i in sta}
seen_modes: set[str] = set()
big64: list[str] = []
for mnemonic, instrs in machine.by_mnemonic.items():
    modes = {i.address_mode for i in instrs}
    if modes & addr_modes == addr_modes:
        big64.append(mnemonic)
        seen_modes |= modes

all_modes = sorted(seen_modes)

table: list[list[str]] = [
    [mnem, *[fmt_opcode(mnem, m) for m in sorted(all_modes)]] for mnem in big64
]

print(
    tabulate(
        table,
        headers=["mnemonic", *all_modes],
        tablefmt="rounded_grid",
    )
)

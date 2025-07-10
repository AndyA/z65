import json
import sys
from dataclasses import dataclass
from functools import cached_property
from typing import Self


@dataclass(kw_only=True, frozen=True)
class ListingLine:
    text: str

    @cached_property
    def address(self) -> int:
        return int(self.text[0:4], 16)

    @cached_property
    def bytes(self) -> list[int]:
        return [int(byte, 16) for byte in self.text[7:18].split()]

    @cached_property
    def source(self) -> str:
        return self.text[18:]


@dataclass(kw_only=True, frozen=True)
class Listing:
    lines: list[ListingLine]

    @classmethod
    def from_lines(cls, lines: list[str]) -> Self:
        return cls(lines=[ListingLine(text=line) for line in lines])

    @cached_property
    def by_address(self) -> dict[int, ListingLine]:
        return {line.address: line for line in self.lines}


@dataclass(kw_only=True, frozen=True)
class Step:
    pc: int
    p: str
    a: int
    x: int
    y: int
    s: int
    s: int
    s: int
    s: int
    s: int
    s: int
    s: int

    def __str__(self) -> str:
        return (
            f"PC: {self.pc:04X} "
            f"P: {self.p} "
            f"A: {self.a:02X} "
            f"X: {self.x:02X} "
            f"Y: {self.y:02X} "
            f"S: {self.s:02X}"
        )


def load_steps(file_name: str) -> list[Step]:
    steps: list[Step] = []
    with open(file_name, "r") as f:
        for line in f:
            if not line.startswith("{"):
                continue
            step = json.loads(line)
            steps.append(Step(**step))
    return steps


with open("ref/hibasic.as65", "r") as f:
    lines = f.readlines()
    listing = Listing.from_lines(lines)

trace_files = sys.argv[1:]
for trace_file in trace_files:
    steps = load_steps(trace_file)
    print(f"Loaded {len(steps)} steps from {trace_file}")

    for step in steps:
        print(step, end="")
        line = listing.by_address.get(step.pc, None)
        if line := listing.by_address.get(step.pc, None):
            print(f" | {line.text.strip()}", end="")
        print()

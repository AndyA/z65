# /// script
# requires-python = ">=3.14"
# dependencies = []
# ///

import re
import unicodedata
from dataclasses import dataclass
from functools import cached_property
from itertools import groupby

DATA = "ref/EastAsianWidth.txt"


@dataclass(frozen=True, kw_only=True)
class Mapping:
    codepoint: int
    width: str

    @cached_property
    def cells(self) -> int:
        char = chr(self.codepoint)
        if unicodedata.category(char).startswith("Cc"):
            return 0
        if unicodedata.combining(char):
            return 0
        match self.width:
            case "F" | "W":
                return 2
            case "H" | "Na" | "N":
                return 1
            case "A":
                return 3  # could be one or two - to taste
            case _:
                raise ValueError(f"Unknown width {self.width}")


def read_db(file: str) -> list[Mapping]:
    mappings: list[Mapping] = []
    with open(file, "r") as f:
        for line in f:
            if line.startswith("#") or line.strip() == "":
                continue
            if m := re.match(
                r"([0-9a-f]+)\s*;\s*(\w+)",
                line,
                re.IGNORECASE,
            ):
                mappings.append(
                    Mapping(codepoint=int(m.group(1), 16), width=m.group(2))
                )
            elif m := re.match(
                r"([0-9a-f]+)\.\.([0-9a-f]+)\s*;\s*(\w+)",
                line,
                re.IGNORECASE,
            ):
                start = int(m.group(1), 16)
                end = int(m.group(2), 16)
                width = m.group(3)
                for cp in range(start, end + 1):
                    mappings.append(Mapping(codepoint=cp, width=width))
            else:
                raise ValueError("Syntax error")

    return sorted(mappings, key=lambda m: m.codepoint)


print(
    """
pub const Range = packed struct {
    first: u21,
    width: u2,
};

pub const WIDTHS = [_]Range{
"""
)

mappings = read_db(DATA)
runs = 0
for key, run in groupby(mappings, lambda m: m.cells):
    runs += 1
    same = list(run)
    print(f".{{ .first = 0x{same[0].codepoint:0>06x}, .width = {key} }},")

print(f".{{ .first = 0x{same[-1].codepoint + 1:0>06x}, .width = 0 }},")


print("""
};
""")

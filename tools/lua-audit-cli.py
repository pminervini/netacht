#!/usr/bin/env python3
"""Small static dead-code/data audit for NetAcht's compact PICO-8 Lua.

This is intentionally conservative. It reports low-reference symbols and
string literals, then leaves final judgment to a human because this cart uses
data tables and dynamic lookups.
"""

from __future__ import annotations

import argparse
import re
from collections import Counter
from pathlib import Path


IDENT_RE = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
FUNCTION_RE = re.compile(r"^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", re.M)
TOP_ASSIGN_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=")
LOCAL_RE = re.compile(r"\blocal\s+([A-Za-z_][A-Za-z0-9_]*)")
CALLBACKS = {"_init", "_update", "_draw"}
BUILTINS = {
    "abs", "add", "all", "btn", "btnp", "cartdata", "cls", "del", "deli",
    "dget", "dset", "flr", "max", "mid", "min", "poke", "print", "rect",
    "rectfill", "rnd", "stat", "stop", "sub",
}
KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "if", "in", "local", "nil", "not", "or", "return", "then", "true", "while",
}


def lua_section(text: str) -> tuple[str, int]:
    offset = 0
    if "__lua__" in text:
        before, text = text.split("__lua__", 1)
        offset = before.count("\n")
    for marker in ("\n__gfx__", "\n__gff__", "\n__map__", "\n__sfx__", "\n__music__"):
        if marker in text:
            text = text.split(marker, 1)[0]
    return text, offset


def strip_comments_and_strings(text: str, offset: int) -> tuple[str, Counter[str], dict[str, int]]:
    """Return code-shaped text with comments/strings blanked plus string counts."""
    out: list[str] = []
    strings: Counter[str] = Counter()
    string_lines: dict[str, int] = {}
    i = 0
    n = len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == "-" and i + 1 < n and text[i + 1] == "-":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c in ("'", '"'):
            quote = c
            val: list[str] = []
            start_line = line + offset
            out.append(" ")
            i += 1
            while i < n:
                c = text[i]
                if c == "\\" and i + 1 < n:
                    val.append(text[i + 1])
                    out.extend("  ")
                    i += 2
                    continue
                if c == quote:
                    out.append(" ")
                    i += 1
                    break
                val.append(c)
                out.append("\n" if c == "\n" else " ")
                if c == "\n":
                    line += 1
                i += 1
            literal = "".join(val)
            strings[literal] += 1
            string_lines.setdefault(literal, start_line)
            continue
        out.append(c)
        if c == "\n":
            line += 1
        i += 1
    return "".join(out), strings, string_lines


def top_level_globals(code: str, offset: int) -> dict[str, int]:
    """Collect globals assigned on unindented top-level lines."""
    globals_by_name: dict[str, int] = {}
    for lineno, line in enumerate(code.splitlines(), 1):
        if not line or line[0].isspace():
            continue
        if line.startswith(("function ", "__", "pico-8 ", "version ")):
            continue
        for match in TOP_ASSIGN_RE.finditer(line):
            globals_by_name.setdefault(match.group(1), lineno + offset)
    return globals_by_name


def local_decls(code: str, offset: int) -> dict[str, list[int]]:
    locals_by_name: dict[str, list[int]] = {}
    for lineno, line in enumerate(code.splitlines(), 1):
        for match in LOCAL_RE.finditer(line):
            locals_by_name.setdefault(match.group(1), []).append(lineno + offset)
    return locals_by_name


def function_defs(lua: str, offset: int) -> dict[str, int]:
    defs: dict[str, int] = {}
    for match in FUNCTION_RE.finditer(lua):
        defs[match.group(1)] = lua.count("\n", 0, match.start()) + 1 + offset
    return defs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cart", type=Path, nargs="?", default=Path("src/netacht.p8"))
    parser.add_argument(
        "--literal",
        action="append",
        default=[],
        help="specific string literal to report; may be provided more than once",
    )
    parser.add_argument("--max-string-refs", type=int, default=1)
    args = parser.parse_args()

    lua, offset = lua_section(args.cart.read_text())
    code, strings, string_lines = strip_comments_and_strings(lua, offset)
    identifiers = Counter(IDENT_RE.findall(code))
    functions = function_defs(lua, offset)
    globals_by_name = top_level_globals(code, offset)
    locals_by_name = local_decls(code, offset)

    print("functions referenced only by their definition:")
    any_fn = False
    for name, line in sorted(functions.items(), key=lambda item: item[1]):
        if name in CALLBACKS:
            continue
        if identifiers[name] <= 1:
            print(f"  line {line}: {name}")
            any_fn = True
    if not any_fn:
        print("  none")

    print("\ntop-level globals with no identifier references outside assignment:")
    any_global = False
    for name, line in sorted(globals_by_name.items(), key=lambda item: item[1]):
        if name in BUILTINS or name in KEYWORDS:
            continue
        if identifiers[name] <= 1:
            print(f"  line {line}: {name}")
            any_global = True
    if not any_global:
        print("  none")

    print("\ntop-level globals shadowed by local declarations:")
    any_shadow = False
    for name, line in sorted(globals_by_name.items(), key=lambda item: item[1]):
        if name in locals_by_name:
            lines = ", ".join(str(n) for n in locals_by_name[name])
            print(f"  line {line}: {name} shadowed locally at line(s) {lines}")
            any_shadow = True
    if not any_shadow:
        print("  none")

    if args.literal:
        print("\nselected string literal usage:")
        for literal in args.literal:
            print(f"  line {string_lines.get(literal, 0)}: {literal!r} ({strings[literal]})")

    print(f"\nstring literals with <= {args.max_string_refs} occurrence:")
    any_string = False
    for literal, count in sorted(strings.items()):
        if count <= args.max_string_refs and literal.strip():
            print(f"  line {string_lines.get(literal, 0)}: {literal!r} ({count})")
            any_string = True
    if not any_string:
        print("  none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Check a 6502 family include against a BIOS build.

    check-include.py INC --dbg BIOS.dbg --jumptable jumptable.json
                         [--spec SPEC.md] [--allow NAME,...]

Always point it at a build of a tag, made in scratch:

    T=$(mktemp -d)
    git -C ../6502-BIOS archive v1.6 | tar -x -C $T && make -C $T build
    python3 tools/check-include.py 6502.inc --dbg $T/BIOS.dbg \\
            --jumptable $T/tests/fixtures/jumptable.json \\
            --allow MONITOR_ENTRY,MONITOR_BRK_ENTRY

Checks:

  Equates     Every symbol in INC (:= or =) that BIOS.dbg defines at scope 0
              has the BIOS's value.
  Jump table  Every jumptable.json entry is in INC at its address.
  Stale       Every := symbol in INC valued $A000-$FFFF is defined by the
              BIOS, or named in --allow.
  Names       SPEC values are VC_*, and BIOS names are copied from BIOS.inc.
              BIOS.inc's own VDP_* names for SPEC values stay internal to the
              BIOS, so every VDP_* symbol in INC must be a Kernal RAM variable
              ($0300-$03FF) that BIOS.dbg defines.
  SPEC        With --spec (6502-PICOVDP SPEC.md): every register name in §5
              has a VC_REG_<NAME> at its block address ($10 and up for the
              aliases at $02-$06), and every status register in §6 has a
              VC_STAT<n> equal to n. The STAT8-STAT15 collision map is
              VC_STAT_COLLIDE, its first selector.

Prints one summary line and exits non-zero on any failure.
"""

import argparse
import json
import re
import sys

NAME = r"[A-Za-z_][A-Za-z0-9_]*"
EQUATE = re.compile(r"^\s*(" + NAME + r")\s*(:?=)\s*([^;]*?)\s*(?:;.*)?$")
TOKEN = re.compile(r"\s*(\$[0-9A-Fa-f]+|%[01]+|[0-9]+|" + NAME + r"|<<|>>|[-+*/|&^~()])")


def read_include(path):
    """Return {name: (expression, is_absolute, line number)} in file order."""
    equates = {}
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            m = EQUATE.match(line)
            if m:
                name, op, expr = m.groups()
                if name in equates:
                    sys.exit(f"{path}:{n}: {name} defined twice")
                equates[name] = (expr, op == ":=", n)
    return equates


def evaluate(expr, values):
    """Evaluate a ca65 constant expression, or return None if a name is unknown."""
    out, pos = [], 0
    while pos < len(expr):
        m = TOKEN.match(expr, pos)
        if not m:
            raise ValueError(f"can't parse {expr!r}")
        tok, pos = m.group(1), m.end()
        if tok[0] == "$":
            out.append(str(int(tok[1:], 16)))
        elif tok[0] == "%":
            out.append(str(int(tok[1:], 2)))
        elif tok[0].isdigit():
            out.append(str(int(tok)))
        elif tok[0].isalpha() or tok[0] == "_":
            if tok not in values:
                return None
            out.append(str(values[tok]))
        else:
            out.append("//" if tok == "/" else tok)
    return eval(" ".join(out), {"__builtins__": {}})


def resolve(equates):
    values, pending = {}, dict(equates)
    while pending:
        progress = False
        for name, (expr, _, _) in list(pending.items()):
            v = evaluate(expr, values)
            if v is not None:
                values[name] = v
                del pending[name]
                progress = True
        if not progress:
            names = ", ".join(sorted(pending))
            sys.exit(f"unresolved symbols: {names}")
    return values


def read_dbg(path):
    """Return {name: value} for the scope-0 symbols that carry a value."""
    syms = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("sym\t"):
                continue
            fields = dict(kv.split("=", 1) for kv in line.rstrip("\n")[4:].split(","))
            if fields.get("scope") != "0" or "val" not in fields:
                continue
            syms[fields["name"].strip('"')] = int(fields["val"], 16)
    return syms


def spec_section(text, number):
    """The body of a numbered SPEC section ("5. Register Map" to "6. ...")."""
    start = re.search(r"^%d\. .*\n-+\n" % number, text, re.M)
    end = re.search(r"^%d\. .*\n-+\n" % (number + 1), text, re.M)
    if not start or not end:
        sys.exit(f"SPEC: section {number} not found")
    return text[start.end():end.start()]


def read_spec(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    registers = {}
    for m in re.finditer(r"^\| `\$([0-9A-Fa-f]{2})` \| `(" + NAME + r")` \|",
                         spec_section(text, 5), re.M):
        # An aliased name appears twice; the block address is the higher one.
        value = int(m.group(1), 16)
        registers[m.group(2)] = max(value, registers.get(m.group(2), 0))
    status = {}
    for m in re.finditer(r"^\| (\d+)(?:–(\d+))? \| `STAT(\d+)`(?:–`STAT(\d+)`)? \|",
                         spec_section(text, 6), re.M):
        first = int(m.group(1))
        if int(m.group(3)) != first:
            sys.exit(f"SPEC §6: row {first} names STAT{m.group(3)}")
        name = "VC_STAT_COLLIDE" if m.group(2) else f"VC_STAT{first}"
        status[name] = first
    return registers, status


def main():
    ap = argparse.ArgumentParser(description="Check an include against a BIOS build.")
    ap.add_argument("inc")
    ap.add_argument("--dbg", required=True, help="BIOS.dbg from a tagged build")
    ap.add_argument("--jumptable", required=True, help="tests/fixtures/jumptable.json")
    ap.add_argument("--spec", help="6502-PICOVDP SPEC.md")
    ap.add_argument("--allow", default="", help="ROM names the BIOS doesn't define")
    args = ap.parse_args()

    equates = read_include(args.inc)
    values = resolve(equates)
    dbg = read_dbg(args.dbg)
    allow = {a for a in args.allow.split(",") if a}
    problems = []

    match = differ = 0
    for name, value in values.items():
        if name in dbg:
            if dbg[name] == value:
                match += 1
            else:
                differ += 1
                problems.append(f"{name}: include ${value:04X}, BIOS ${dbg[name]:04X}")
    summary = [f"{match} match, {differ} differ"]

    with open(args.jumptable, encoding="utf-8") as f:
        table = json.load(f)
    present = 0
    for addr, name in table.items():
        want = int(addr.lstrip("$"), 16)
        if name not in values:
            problems.append(f"jump table: {name} ({addr}) missing")
        elif values[name] != want:
            problems.append(f"jump table: {name} at ${values[name]:04X}, BIOS {addr}")
        else:
            present += 1
    summary.append(f"{present}/{len(table)} jump-table entries")

    stale = 0
    for name, (_, absolute, line) in equates.items():
        if absolute and 0xA000 <= values[name] <= 0xFFFF and name not in dbg:
            if name in allow:
                allow.discard(name)
                continue
            stale += 1
            problems.append(f"stale: {name} = ${values[name]:04X} (line {line}) not in the BIOS")
    summary.append(f"{stale} stale")
    for name in sorted(allow):
        problems.append(f"--allow {name}: not needed")

    misnamed = 0
    for name, (_, _, line) in equates.items():
        if name.startswith("VDP_") and not (name in dbg and 0x0300 <= dbg[name] <= 0x03FF):
            misnamed += 1
            problems.append(f"name: {name} (line {line}) is not a BIOS RAM variable; "
                            f"SPEC values are VC_*")
    summary.append(f"{misnamed} misnamed")

    if args.spec:
        registers, status = read_spec(args.spec)
        for label, rows, prefix in (("registers", registers, "VC_REG_"), ("status", status, "")):
            bad = 0
            for spec_name, want in rows.items():
                name = prefix + spec_name
                if name not in values:
                    bad += 1
                    problems.append(f"SPEC {label}: {name} missing (${want:02X})")
                elif values[name] != want:
                    bad += 1
                    problems.append(f"SPEC {label}: {name} = ${values[name]:02X}, SPEC ${want:02X}")
            summary.append(f"SPEC {label} {len(rows) - bad}/{len(rows)}")
        extra = sorted(n for n in values if re.fullmatch(r"VC_STAT\d+", n) and n not in status)
        for name in extra:
            problems.append(f"SPEC status: {name} is not a §6 status register")

    for p in problems:
        print(p)
    print("; ".join(summary))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

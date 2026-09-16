# VDP assessment: 6502-ASM

> An outline, not a plan. The detailed plan for this repository goes in `VDP-PLAN.md`,
> written in a session of its own. Surveyed 2026-09-16 across the whole workspace.

## The change

The ACE moves from a Pico9918 running stock TMS9918A firmware to the **6502-PICOVDP**
(`6502-PICOVDP/SPEC.md`) on PICO9918 PRO v2.0 hardware, running **BIOS 2.x**. Everything
else stays where it is: COB, DEV, KIM, VCS, PicoCalc, and any ACE whose card cannot be
reflashed (RP2040 pico9918 v1.0–1.3). Those keep the stock firmware and **BIOS 1.x (1.5)**.

- **Legacy** in these documents means TMS9918A + BIOS 1.x. **VDP** means PICOVDP + BIOS 2.x.
- **Compatibility runs one way.** The PICOVDP's legacy submode runs Text and Graphics I
  programs unchanged, so BIOS 1.5 and existing cartridges run on it. Graphics II and
  Multicolor fall back to Graphics I and draw garbage. Register writes above 7 no longer
  alias, so F18A tricks break. Sprites per line are 16 by default, not 4. Nothing written
  for the VDP runs on a TMS9918A.
- **BIOS 2.0 is assumed to be:** BIOS 1.5, plus the NVRAM save slots in
  `6502-BIOS/PLAN.md`, plus the VDP work in `6502-EMULATOR`'s
  `docs/handoff/6502-BIOS.md` (branch `v3-vdp`). Existing jump-table addresses stay put.
  A later BIOS redesign may revise this.

## Decisions already made

- No new repositories.
- **6502-EMULATOR** makes the video card an option (TMS9918A or PICOVDP): one app, one
  site. It also publishes a frozen 2.6.9 web build at a versioned path for the legacy docs.
- **6502-DOCS** is versioned: legacy docs are frozen at `/6502-DOCS/v1/`, and the main
  site is rewritten for the VDP.
- **6502-BIOS** gets a `v1.x` maintenance branch; `main` becomes 2.x.
- **Assembly and C projects** get a VDP include chosen by a build option, not branches.
- **EhBASIC and vc83basic** stay 1.x. **PicoCalc** stays legacy. **The YouTube series**
  teaches the legacy VDP and mentions the new features.

## Order across the workspace

1. **6502-PICOVDP:** firmware proven on the PRO (its Phases 9–11). This gates the
   hardware switch, not the software work.
2. **6502-EMULATOR:** frozen 2.6.9 web build at `/6502-EMULATOR/v2/`.
3. **6502-DOCS:** `v1` branch published at `/6502-DOCS/v1/`, embeds pinned to step 2.
4. **6502-EMULATOR:** `v3-vdp` merged, with the card as an option; tagged 3.x.
5. **6502-BIOS:** `v1.x` cut; 2.0 built on `main`. This can start any time, because the
   `v3-vdp` emulator already runs the PICOVDP.
6. **6502-ASM** sets the VDP include convention. 6502-CRT, 6502-PRG, 6502-BIN and 6502-C
   follow it.
7. The emulator bundles BIOS 2.0. 6502-DOCS `main` is rewritten. 6502-ACE, bastok,
   WIZARDSLAB, 6502-EHBASIC, vc83basic and 6502-ASSEMBLY follow.

---

## This repository's role

**Lead for the include files.** Its README ("Targets, includes and configs") already
defines the include/config pattern (`6502.inc` for the ACE, `6502-KIM.inc` for the KIM),
and says `6502.inc` "is kept identical across the repositories that ship a copy". The VDP
include convention is decided here, and 6502-CRT, 6502-PRG, 6502-BIN, 6502-C and (if it
ever wants one) WIZARDSLAB copy it.

## Where it stands

- Programs: `HelloWorld` (`.prg`, `6502.inc`, `6502.cfg`), `HelloWorldCart` (`.crt`,
  `6502-16K.cfg`), and `BitRally`/`Countdown` (KIM: `6502-KIM.inc`, `6502-KIM.cfg`).
- The root `Makefile` delegates to every subdirectory with a Makefile.
- **The legacy `6502.inc` is settled** (2026-09-16, commit "Bring 6502.inc in line with
  the other copies").
  - One byte-identical file in 6502-ASM, 6502-CRT, 6502-PRG, 6502-BIN, 6502-EHBASIC,
    6502-C, and WIZARDSLAB (as `include/ac6502.inc`).
  - Every equate the BIOS also defines was checked against a v1.5 build (`BIOS.dbg`,
    `BIOS.inc`): 248 match, none differ, and all 85 jump-table entries are present.
    Rebuilt binaries were unchanged.
  - It is the BIOS 1.x + TMS9918A baseline. It changes only for a 1.x BIOS fix.
  - 6502-DOCS's `samples/lib/6502.inc` is separate: generated from `BIOS.inc` by
    `extract-facts.mjs`, not a copy of this file.

## Work outline

1. **Decide the build-option convention**, once, for every repo.
   - **Legacy stays `6502.inc`, unchanged:** BIOS 1.x + TMS9918A.
   - **A new, complete include for BIOS 2.x + PICOVDP** (working name `6502-VDP.inc`).
     It should stand alone rather than layer on `6502.inc`, because BIOS 2 will diverge
     further.
   - **Two mechanisms to choose between:**
     - (a) `make VDP=1` passes `-D VDP`, and each source does
       `.ifdef VDP` / `.include "6502-VDP.inc"` / `.else` / `.include "6502.inc"`.
     - (b) Same-named includes in two directories, selected with `--asm-include-dir`,
       with sources untouched.
   - Build outputs need distinct names or directories, so both builds can coexist.
   - The root `Makefile` passes the option through.
2. **Write `6502-VDP.inc`.**
   - Everything in `6502.inc`.
   - Port B (`$9C02`/`$9C03`).
   - Register names `$08`–`$7F` and status selection from SPEC §5–§6.
   - `VBANK`/`VINC`, palette location, `VMODE` values.
   - BIOS 2.0's card-type RAM byte, NVRAM slot entries and VDP entry points.
   - Comments that say PICOVDP.
   - The hardware equates can be written from the SPEC now. The Kernal part waits for
     BIOS 2.0's jump table.
3. **Programs.** `HelloWorld` and `HelloWorldCart` build both ways. `make run` for a VDP
   build must select the emulator's PICOVDP card (flag named by 6502-EMULATOR).
   Optionally add a small VDP sample, or point at the emulator's `samples/vdp-modes/`.
4. **README.**
   - The targets table gains the VDP variant.
   - Guidance: legacy builds run on both platforms, VDP builds only on a converted ACE.
     Using `6502-VDP.inc` for a legacy machine is the same kind of mistake the README
     already warns about for `6502-KIM.inc`.
5. **KIM targets:** untouched.

## Linked repositories

| Repository | Path | Why |
|---|---|---|
| 6502-BIOS | `~/Developer/Assembly/6502-BIOS` | 2.0's `BIOS.inc` and jump table are what `6502-VDP.inc` describes |
| 6502-PICOVDP | `~/Developer/C/6502-PICOVDP` | `SPEC.md` §4–§6 for ports and registers |
| 6502-EMULATOR | `~/Developer/NodeJS/6502-EMULATOR` | Card flag for `make run` |
| 6502-CRT | `~/Developer/Assembly/6502-CRT` | Follows this convention |
| 6502-PRG | `~/Developer/Assembly/6502-PRG` | Follows this convention |
| 6502-BIN | `~/Developer/Assembly/6502-BIN` | Follows this convention |
| 6502-C | `~/Developer/C/6502-C` | Follows it, with `6502.h` parity |
| 6502-EHBASIC, WIZARDSLAB | `~/Developer/Assembly/…` | Hold copies of the legacy `6502.inc`; they stay on it |
| 6502-DOCS | `~/Developer/NodeJS/6502-DOCS` | Generates its own `samples/lib/6502.inc` from BIOS source |

## Questions for VDP-PLAN.md

1. Mechanism (a) or (b).
2. The include's final name.
3. Where the canonical copy of `6502-VDP.inc` lives, and how its copies are kept
   identical. A check against the BIOS build, like the one used to settle `6502.inc`, or
   a script like 6502-C's `tests/parity.py`.
4. Output naming for dual builds.

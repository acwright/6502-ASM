# VDP assessment: 6502-ASM

> An outline, not a plan. The detailed plan for this repository goes in `VDP-PLAN.md`,
> written in a session of its own. Surveyed 2026-09-16 across the whole workspace.

## The change

The ACE moves from a Pico9918 running stock TMS9918A firmware to the **6502-PICOVDP**
(`6502-PICOVDP/SPEC.md`) on PICO9918 PRO v2.0 hardware, running **BIOS 2.x**. Everything
else stays where it is: COB, DEV, KIM, VCS, PicoCalc, and any ACE whose card cannot be
reflashed (RP2040 pico9918 v1.0–1.3). Those keep the stock firmware and **BIOS 1.x**,
whose last release is **1.6**.

- **Legacy** in these documents means TMS9918A + BIOS 1.x. **VDP** means PICOVDP + BIOS 2.x.
- **Compatibility runs one way.** The PICOVDP's legacy submode runs Text and Graphics I
  programs unchanged, so BIOS 1.x and existing cartridges run on it. Graphics II and
  Multicolor fall back to Graphics I and draw garbage. Register writes above 7 no longer
  alias, so F18A tricks break. Sprites per line are 16 by default, not 4. Nothing written
  for the VDP runs on a TMS9918A.

## Decisions already made

- **No new repositories.**
- **BIOS 1.6 is the last 1.x release.** It is 1.5 plus the NVRAM save slots in
  `6502-BIOS/PLAN.md`, and nothing else. It ships in emulator **2.7.0**, and the frozen
  legacy docs document it.
- **BIOS 2.0 is 1.6 plus:**
  - The PICOVDP work in `6502-EMULATOR`'s `docs/handoff/6502-BIOS.md` (branch `v3-vdp`):
    card detection, hardware scroll, port B for interrupt handlers, `WaitVBlank`.
  - A console in the PICOVDP's **Text mode** (`VMODE $1`, 40×24, 6×8 cells) with a
    **per-cell colour table**. It keeps the same font and every screen layout.
  - **No Monitor.** The machine **boots straight to BASIC**, with a new header and a colour
    logo drawn from the font's CP437 block characters. Wozmon stays at `$FF00`.
  - **The font lives in the PICOVDP firmware.** The card loads it into VRAM at reset and
    on command (a new register and a capability bit, SPEC draft 0.5). ROM `$B800` holds
    no font on 2.x.
  - **ROM layout:** BASIC takes the Monitor's 4.3 KB (`$C000–$FEFF`), and the Kernal takes
    all of `$A000–$BFFF`, including the space the font used. Nothing the Kernal needs goes
    above `$C000`, because cartridges overlay `$C000–$FFFF`. The Kernal holds the
    primitives cartridges need; BASIC-only work lives in BASIC.
  - **No TMS9918A support.** BIOS 2.x runs only with a PICOVDP, with no fallback paths.
  - **New BASIC commands with matching Kernal entries.**
    - Core: `SCREEN`, `VPOKE`/`VPEEK`, `VREG`, `PALETTE`, `VSYNC`, `VLOAD`.
    - Second tier, if room is found: `SPRITE`, `SCROLL`, `LAYER`, `VSTAT`.
    - Save-slot commands, if room is found.
    - `SYS addr[,a,x,y]`, and `BLOAD`/`BSAVE` over XModem when given no filename.
    - BASIC returns to the text console when a program stops.
  - **Tokens:** every 1.x token keeps its value, and new keywords are appended after `$D4`.
    The `BRK` statement is retired and its token `$B4` goes to a new keyword.
  - **A BRK instruction** prints `BREAK $nn AT $xxxx  A= X= Y= P= S=` and warm-starts
    BASIC. `BRK_PTR` stays hookable.
  - **`COLOR fg[,bg[,border]]`** sets the pen for later output, `CLS` fills the screen with
    it, and `border` is register 7's low nibble.
  - **Existing jump-table addresses do not move.** New entries are appended.
- **6502-EMULATOR** makes the video card an option (TMS9918A or PICOVDP): one app, one
  site. It also publishes a frozen **2.7.0** web build at `/6502-EMULATOR/v2/` for the
  legacy docs.
- **6502-DOCS** is versioned: legacy docs (BIOS 1.6) are frozen at `/6502-DOCS/v1/`, and
  the main site is rewritten for the VDP and BIOS 2.x.
- **6502-BIOS** gets a `v1.x` branch cut at `v1.6`; `main` becomes 2.x.
- **Assembly and C projects** get a VDP include chosen by a build option, not branches.
  The legacy `6502.inc` gets one last update, for 1.6.
- **EhBASIC and vc83basic** stay 1.x. **PicoCalc** stays legacy. **The YouTube series**
  teaches the legacy VDP and mentions the new features.

## Order across the workspace

**Part 1: BIOS 1.6, the last legacy release**

1. **6502-BIOS:** build 1.6 on `main`, tag `v1.6`, and cut `v1.x` from it.
2. **6502-EMULATOR `main`:** bundle 1.6, re-capture the `bios/` goldens (the splash says
   v1.6), and release **2.7.0**. Then merge `main` into `v3-vdp` and re-capture there.
3. **6502-PICOVDP:** re-sync `tests/oracle/`, whose pinned `bios` goldens moved.
4. **The legacy include** gains the NVRAM entries in every copy: 6502-ASM, 6502-CRT,
   6502-PRG, 6502-BIN, 6502-EHBASIC, 6502-C (with `6502.h`) and WIZARDSLAB.
5. **6502-DOCS `main`** documents 1.6 and pins 2.7.0. Then it cuts `v1`, published at
   `/6502-DOCS/v1/`, against the emulator's frozen 2.7.0 build at `/6502-EMULATOR/v2/`.

**Part 2: the VDP**

6. **6502-PICOVDP:**
   - SPEC draft 0.5 adds the built-in font and its load command. The emulator's PICOVDP
     card implements it first, then the firmware.
   - Firmware proven on the PRO (its Phases 9–11) gates the hardware switch, not the
     software work.
7. **6502-EMULATOR:** `v3-vdp` merged, with the card as an option; tagged 3.x.
8. **6502-BIOS:** 2.0 on `main`. This can start once step 1 is done, because the `v3-vdp`
   emulator already runs the PICOVDP. Its console work needs the built-in font in the
   emulator (step 6).
9. **6502-ASM** sets the VDP include convention. 6502-CRT, 6502-PRG, 6502-BIN and 6502-C
   follow it.
10. **Everything else follows BIOS 2.0:**
    - The emulator bundles BIOS 2.0.
    - 6502-DOCS `main` is rewritten.
    - bastok gains the 2.x token table.
    - 6502-ACE, WIZARDSLAB, 6502-EHBASIC, vc83basic, cffs and 6502-ASSEMBLY follow.

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
  - It is the BIOS 1.x + TMS9918A baseline. It gets **one more update, for BIOS 1.6**,
    and after that changes only for a 1.x bug fix.
  - 6502-DOCS's `samples/lib/6502.inc` is separate: generated from `BIOS.inc` by
    `extract-facts.mjs`, not a copy of this file.

## Work outline

0. **BIOS 1.6 update to the legacy include** (Part 1, as soon as 6502-BIOS tags `v1.6`).
   - Add the 6 NVRAM slot entries and their equates (`PLAN.md` §2–§3 in 6502-BIOS).
   - Update the header to "BIOS v1.6".
   - Re-run the check against the `v1.6` build (every equate the BIOS defines matches, and
     the jump table is complete).
   - Copy the result byte-identically to 6502-CRT, 6502-PRG, 6502-BIN, 6502-EHBASIC,
     6502-C (plus `6502.h` declarations) and WIZARDSLAB (`include/ac6502.inc`).
   - Rebuild everything to confirm the binaries are unchanged.
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
   - BIOS 2.0's card-type RAM byte, the NVRAM slot entries, the VDP entry points, and the
     per-cell colour pen variable.
   - **Removed:** `MONITOR_ENTRY`/`MONITOR_BRK_ENTRY` (`$EE00` is BASIC on 2.x). Update the
     `BRK_PTR` and BRK register comments to describe the BRK report.
   - **Memory-map header:** Kernal `$A000–$BFFF`, BASIC `$C000–$FEFF`, no Monitor, and no
     character set in ROM. The font is in the card: name the load-font register and the
     `STAT6` font bit from SPEC draft 0.5, and `VdpLoadFont`.
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

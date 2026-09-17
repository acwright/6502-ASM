6502-ASM
========

Assembly code for the [AC6502](https://github.com/acwright/6502-ACE) family of computer systems.
> 📖 **Guide:** [AC6502 Documentation](https://acwright.github.io/6502-DOCS/) — the user's and programmer's guide for the whole family.
> Several of these programs are walked through line by line in [Worked projects](https://acwright.github.io/6502-DOCS/assembly/projects).

## Building Programs

Each program directory contains its own Makefile. To build a program, navigate to its directory and use `make`.

### Prerequisites

#### CC65 Compiler

On macOS, install via Homebrew:
```bash
brew install cc65
```

For other platforms or installation methods, refer to the [cc65 project](https://github.com/cc65/cc65).

#### bin2woz

Install from NPM (recommended):
```bash
npm install -g bin2woz
```

Or build from source:
1. Clone the repository:
   ```bash
   git clone https://github.com/acwright/bin2woz.git
   cd bin2woz
   ```

2. Install dependencies and build:
   ```bash
   npm install
   npm run build
   ```

3. Link globally (optional):
   ```bash
   npm link
   ```

For more information, see the [bin2woz project](https://github.com/acwright/bin2woz).

#### cffs

Install from NPM:
```bash
npm install -g cffs-image-tool
```

The `cffs` tool is used to create CompactFlash disk images and add files to them. It's required for the `make cf` target.

For more information, see the [cffs project](https://github.com/acwright/cffs).

#### 6502 CLI

Installed via the [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) app's Settings → Command Line → Install. Required for the `make run` target.

### Available Targets

- `make` or `make all` - Build the program (`make VDP=1` builds the 6502-PICOVDP version, see [Choosing a build](#choosing-a-build))
- `make view` - Display hexdump of the built program
- `make woz` - Create a Wozmon compatible file using [bin2woz](https://github.com/acwright/bin2woz)
- `make cf` - Create a CompactFlash disk image containing the program
- `make run` - Launch the emulator app with the built program loaded (`ROM=path/to/BIOS.bin` boots that BIOS image instead of the bundled one)
- `make eeprom` - Burn a cartridge image to an AT28C256 (cartridge targets)
- `make clean` - Remove build artifacts

Not every program offers every target: `woz` and `cf` belong to programs
loaded into RAM, and `eeprom` to cartridges.

### Example

```bash
cd <directory-name>
make        # Build the program
make view   # View the hexdump
make woz    # Create a Wozmon compatible file
make run    # Launch the emulator
```

## Targets, includes and configs

This repository holds three kinds of program, and each picks up a different
pair of files. The Kernal's jump table is the same on every machine here —
what differs is which hardware exists, which BIOS runs it, and where the code
lives.

| Program | Machine | Include | Config | Output |
|---|---|---|---|---|
| `HelloWorld` | AC6502 (ACE), TMS9918A, BIOS 1.x | `6502.inc` | `6502.cfg` | `HelloWorld.prg` loaded at `$0800` |
| `HelloWorld` (`VDP=1`) | ACE with 6502-PICOVDP, BIOS 2.x | `6502-VDP.inc` | `6502.cfg` | `HelloWorld-VDP.prg` loaded at `$0800` |
| `HelloWorldCart` | AC6502 (ACE), TMS9918A, BIOS 1.x | `6502.inc` | `6502-16K.cfg` | `HelloWorldCart.crt` ROM at `$C000` |
| `HelloWorldCart` (`VDP=1`) | ACE with 6502-PICOVDP, BIOS 2.x | `6502-VDP.inc` | `6502-16K.cfg` | `HelloWorldCart-VDP.crt` ROM at `$C000` |
| `VdpTiles` | ACE with 6502-PICOVDP, BIOS 2.x | `6502-VDP.inc` | `6502.cfg` | `VdpTiles.prg` loaded at `$0800` |
| `BitRally`, `Countdown` | AC6502 KIM | `6502-KIM.inc` | `6502-KIM.cfg` | `.bin` loaded at `$0800` |

### The includes

`6502.inc` describes a fully fitted ACE with a TMS9918A running BIOS 1.x: the
Kernal jump table, BASIC, the Monitor, video, sound, storage, the RTC and the
VIA. It is **frozen at BIOS 1.6** and changes only for a 1.x fix.

`6502-VDP.inc` describes an ACE whose video card is a
[6502-PICOVDP](https://github.com/acwright/6502-PICOVDP), running BIOS 2.x.
It stands alone rather than layering on `6502.inc`, and follows its section
order, so `diff 6502.inc 6502-VDP.inc` shows what 2.x changed:

- The PICOVDP's second port pair, its registers, status registers and bit
  fields, as `VC_*` names taken from the card's `SPEC.md`.
- The 2.0 Kernal: the Text-mode console with a colour per cell, the thirteen
  VDP entries from `VdpInfo` to `VdpStatus`, and the video variables.
- No Monitor, and no character set in ROM: the Kernal is all of
  `$A000-$BFFF`, and the font is the card's own, loaded by `InitVideo`.

Names for things the SPEC defines are `VC_*`; names for things the BIOS
defines are copied from the BIOS's `BIOS.inc`. `tools/check-include.py`
checks the file against a build of a BIOS tag and the SPEC's tables.

Both ACE includes are kept identical across the repositories that ship a copy
(6502-CRT, 6502-PRG, 6502-BIN and 6502-C).

`6502-KIM.inc` describes the KIM, which is not a stock ACE. The Keypad Card
overlays `$C000-$FFFF` and is decoded before ROM, so the machine boots into a
hex monitor rather than BASIC. It has no video, no sound, no storage, no RTC
and no VIA, and a few addresses mean something else entirely — `$9400` is a
write-only LED latch here, not the family's GPIO window. It also names the
things only a KIM has: the LED latch, and the keypad mailbox that replaces
`Chrin`, which never returns anything on this machine.

Using `6502.inc` for a KIM program is the mistake worth avoiding. It compiles
and it links, but it puts several hundred names in scope for hardware that is
not fitted, and it does not name the hardware that is.

### Choosing a build

`make` builds for every ACE on BIOS 1.x. `make VDP=1` builds for an ACE
converted to a 6502-PICOVDP, on BIOS 2.x, and writes its outputs beside the
legacy ones with a `-VDP` suffix. `make VDP=1` at the top level builds every
program that has a VDP build; the KIM programs ignore it.

A source that builds both ways picks its include with the `VDP` symbol, which
the Makefile passes to ca65 as `--asm-define VDP`:

```asm
.ifdef VDP
.include "../6502-VDP.inc"
.else
.include "../6502.inc"
.endif
```

A program written only for the PICOVDP, like `VdpTiles`, includes
`6502-VDP.inc` directly and has no legacy build.

- **Nothing built with `VDP=1` runs on a TMS9918A.**
- A legacy build that only calls the jump table also runs on 2.x. The 2.x
  `KernalInit` leaves the PICOVDP in the TMS9918-compatible submode and brings
  the Text console up the first time something prints, so a legacy cartridge
  that drives the video chip itself runs unchanged too. `HelloWorld` and
  `HelloWorldCart` build to the same bytes either way.
- The mistake worth avoiding is the KIM one again: `6502-VDP.inc` in a
  program meant for a TMS9918A machine compiles, links and fails at run time.

`make VDP=1 run` passes the emulator `--vdp picovdp`. Until the emulator
bundles BIOS 2.0 for that card, add `ROM=path/to/BIOS.bin` to boot a 2.0
image.

### The configs

`6502.cfg` and `6502-KIM.cfg` are the same layout today — program RAM at
`$0800-$7FFF` — and are kept separate so the KIM's can change without
disturbing the family's. Both ACE builds, legacy and VDP, use the same two
configs: program RAM and the cartridge window are the same on 2.x.

`6502-16K.cfg` is the cartridge layout: 16K of code space at `$C000-$FFF9`,
emitted as a 32K image spanning `$8000-$FFFF` so it can be burned straight to
a 28C256. A cartridge starts at the RESET vector with nothing initialized and
nothing to return to, so it calls `KernalInit` itself and never exits. See
[6502-CRT](https://github.com/acwright/6502-CRT) for the fully commented
template.

## Related

- [6502-ACE](https://github.com/acwright/6502-ACE) — the hardware, and the index of the whole family
- [6502-BIOS](https://github.com/acwright/6502-BIOS) — the firmware behind `6502.inc` (1.x) and `6502-VDP.inc` (2.x)
- [6502-PICOVDP](https://github.com/acwright/6502-PICOVDP) — the video card behind `6502-VDP.inc`, and the `SPEC.md` its `VC_*` names come from
- [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) — run these programs without hardware
- [6502-PRG](https://github.com/acwright/6502-PRG) — template for starting a new assembly program
- [6502-CRT](https://github.com/acwright/6502-CRT) — template for starting a new cartridge
- [6502-BAS](https://github.com/acwright/6502-BAS) — the same idea for BASIC listings
- [6502-DOCS](https://github.com/acwright/6502-DOCS) — the documentation site: the assembly guide these programs illustrate

## License

MIT License — see [LICENSE](LICENSE).

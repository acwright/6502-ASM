6502-ASM
========

Assembly code for the [A.C. Wright 6502](https://github.com/acwright/6502-ACE) family of computer systems.
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

- `make` or `make all` - Build the program
- `make view` - Display hexdump of the built program
- `make woz` - Create a Wozmon compatible file using [bin2woz](https://github.com/acwright/bin2woz)
- `make cf` - Create a CompactFlash disk image containing the program
- `make run` - Launch the emulator app with the built program loaded
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
pair of files. The Kernal is the same on every machine here — what differs is
which hardware exists and where the code lives.

| Program | Machine | Include | Config | Output |
|---|---|---|---|---|
| `HelloWorld` | AC6502 (ACE) | `6502.inc` | `6502.cfg` | `.prg` loaded at `$0800` |
| `HelloWorldCart` | AC6502 (ACE) | `6502.inc` | `6502-16K.cfg` | `.crt` ROM at `$C000` |
| `BitRally`, `Countdown` | AC6502 KIM | `6502-KIM.inc` | `6502-KIM.cfg` | `.bin` loaded at `$0800` |

### The includes

`6502.inc` describes a fully fitted ACE: the Kernal jump table, BASIC, video,
sound, storage, the RTC and the VIA. It tracks the published API of the
[BIOS](https://github.com/acwright/6502-BIOS) and is kept identical across the
repositories that ship a copy.

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

### The configs

`6502.cfg` and `6502-KIM.cfg` are the same layout today — program RAM at
`$0800-$7FFF` — and are kept separate so the KIM's can change without
disturbing the family's.

`6502-16K.cfg` is the cartridge layout: 16K of code space at `$C000-$FFF9`,
emitted as a 32K image spanning `$8000-$FFFF` so it can be burned straight to
a 28C256. A cartridge starts at the RESET vector with nothing initialized and
nothing to return to, so it calls `KernalInit` itself and never exits. See
[6502-CRT](https://github.com/acwright/6502-CRT) for the fully commented
template.

## Related

- [6502-ACE](https://github.com/acwright/6502-ACE) — the hardware, and the index of the whole family
- [6502-BIOS](https://github.com/acwright/6502-BIOS) — the firmware behind `6502.inc`
- [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) — run these programs without hardware
- [6502-PRG](https://github.com/acwright/6502-PRG) — template for starting a new assembly program
- [6502-CRT](https://github.com/acwright/6502-CRT) — template for starting a new cartridge
- [6502-BAS](https://github.com/acwright/6502-BAS) — the same idea for BASIC listings
- [6502-DOCS](https://github.com/acwright/6502-DOCS) — the documentation site: the assembly guide these programs illustrate

## License

MIT License — see [LICENSE](LICENSE).

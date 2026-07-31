6502-ASM
========

Assembly code for the [A.C. Wright 6502](https://github.com/acwright/6502-ACE) family of computer systems.

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
- `make run` - Launch the emulator app with the built program loaded
- `make clean` - Remove build artifacts

### Example

```bash
cd <directory-name>
make        # Build the program
make view   # View the hexdump
make woz    # Create a Wozmon compatible file
make run    # Launch the emulator
```

Each program includes `6502.inc`, the shared include file describing the Kernal
jump table, hardware registers, and system constants. It tracks the published
API of the [BIOS](https://github.com/acwright/6502-BIOS) and is kept identical
across the repositories that ship a copy.

## Related

- [6502-ACE](https://github.com/acwright/6502-ACE) — the hardware, and the index of the whole family
- [6502-BIOS](https://github.com/acwright/6502-BIOS) — the firmware behind `6502.inc`
- [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) — run these programs without hardware
- [6502-PRG](https://github.com/acwright/6502-PRG) — template for starting a new assembly program
- [6502-CRT](https://github.com/acwright/6502-CRT) — template for starting a new cartridge
- [6502-BAS](https://github.com/acwright/6502-BAS) — the same idea for BASIC listings

## License

MIT License — see [LICENSE](LICENSE).

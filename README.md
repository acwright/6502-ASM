6502
====

This is a collection of my 6502 assembly language programs.

## Building Programs

Each program directory contains its own Makefile. To build a program, navigate to its directory and use `make`.

### Available Targets

- `make` or `make all` - Build the program
- `make view` - Display hexdump of the built program
- `make run` - Run the program in the xvic emulator
- `make clean` - Remove build artifacts

### Example

```bash
cd <directory-name>
make        # Build the program
make view   # View the hexdump
make run    # Run in emulator
```


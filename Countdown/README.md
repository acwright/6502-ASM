Countdown
=========

An LED coundown for the [AC6502 KIM](https://github.com/acwright/6502-KIM).

A raw binary. Loads at `$0800`; the first byte of the file is the entry point — no
BASIC startup stub.

## Building

    make        # assemble
    make view   # hexdump
    make run    # launch the emulator
    make woz    # Wozmon-loadable format
    make clean

On hardware, key `$0800` on the pad and press `▲`, which calls the program as a
subroutine — so `RTS` returns you to the KC Monitor.

Once the game is driving the LEDs, add `--accessory led-latch` to the `run` target in
the [Makefile](Makefile) so the emulator shows them.

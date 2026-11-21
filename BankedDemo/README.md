Banked Demo
===========

Eight full-screen pictures, one per bank, cycled with a key or a joystick. It
is a Flash Cart because it has to be: a picture is 2,848 bytes, eight of them
is 22,784, and a fixed 16 KB cartridge has 16,378.

That is the only reason this project exists. A demo that would fit in a fixed
cartridge teaches nothing about why banking is there.

Press any key — or push joystick 1 right — for the next picture, `,` or left
for the previous one. Every byte but `,` steps forward, so over serial a
terminal's Return is a step of its own: `A` then Return is two pictures.

Reading the stick
-----------------

The demo reads joystick 1 at most once a video frame (`WaitVBlank` on the 2.x
build; a 2 cs `SysDelay` on the 1.x build, which has no `WaitVBlank`), and a
push or a release counts only when two reads a frame apart agree. That does two
jobs, both found on an ACE at the bench (2026-11-21):

- **The keyboard keeps working.** Reading the stick disables the keyboard
  encoders for the read. Read back to back, they were enabled for only ~90 µs at
  a time, and the ACE's own keyboard sent nothing. Read once a frame, they have
  nearly the whole frame.
- **One push is one step.** A stick's switch bounces as it closes. Taken at
  face value, the bounce looked like a release, so one push stepped twice: once
  at the push and once at the real release.

The step is taken when the stick comes back to centre, so a held stick steps
nothing until it is let go. Any program that polls a stick in a loop should read
it at most once a frame, for the first reason.

`make DIAG=1` (with or without `VDP=1`) builds a bench variant that prints a line
over serial for every step: `S xx p` for a byte from the input buffer (serial or
either keyboard) or `J xx p` for a stick step, `xx` the byte or the stick value
and `p` the picture now shown.

The shape of it
---------------

    FIXED    $E000-$FFF9   all of the code, and the vectors
    BANK00   $C000-$DFFF   Checkers        BANK04   Maze
    BANK01                 Rings           BANK05   Waves
    BANK02                 Stripes         BANK06   Spiral
    BANK03                 Starfield       BANK07   Lattice

The segment name is the value you write to the bank register: `.segment
"BANK03"` is reached with `lda #$03` and `jsr SetBank`. Every bank has the
same layout, so one `ShowPicture` reads one set of addresses and works on
whichever bank is selected:

| Address | Size | What |
|---|--:|---|
| `$C000` | 2,048 | pattern table — 256 patterns of 8 rows, msb leftmost |
| `$C800` | 32 | colour table — `ink << 4 \| paper`, one per 8 patterns |
| `$C820` | 768 | name table — 32 × 24 cells, each naming a pattern |

2,848 bytes of an 8,192-byte bank; the rest is `$FF`. A bank is 8 KB whether
you fill it or not.

The three things to read it for
-------------------------------

1. **`SetBank` is in `FIXED`, and it is called from `FIXED`.** `jsr SetBank`
   from code at `$C000-$DFFF` returns to an address that no longer holds the
   calling code. The machine does not fault; it runs whatever the new bank has
   there.
2. **The shadow is written before the register.** The register cannot be read
   back, so the byte at `$3A` is the only record of which bank is selected.
   Writing it first means an interrupt landing between the two stores sees the
   shadow one instruction *ahead* of the hardware, which restoring from the
   shadow puts right; the other order leaves the two permanently disagreed.
3. **Reading a bank is not special.** Everything after `jsr SetBank` in
   `ShowPicture` is an ordinary `lda (ptr),y`. `CopyToVram` has no idea it is
   reading out of a window, and that is the point.

Building
--------

Install:

    brew install cc65

Build, for the 512 KB part:

    make

Or for the 128 KB part, which holds the same eight banks and is the cheaper
chip:

    make FLASH=128K

`make all-flash` builds all four sizes; 256K and 1M are the same image in a
bigger chip. There is no `make` without a `FLASH=` target here and no `make
eeprom`: the pictures alone are four times a 28C256.

View:

    make view

Run:

    make run
    make run FLASH=128K

**`make run` needs 6502-EMULATOR 3.4.0 or later.** On 3.3.0 the cartridge is
dropped without a word and the machine boots to BASIC — `Cart.load()` takes
32,768 bytes and says nothing about the other sizes — so a silent BASIC prompt
is the symptom of an old emulator, not of a broken cartridge.

To run it on a local BIOS image instead of the emulator's bundled one:

    make ROM=path/to/BIOS.bin run

Onto a cart:

    make flash

That is `6502-flash program`, through the Flash Helper, in circuit. It reads
the `.crt` and nothing else.

The pictures are generated
--------------------------

`Gallery.inc` is written by `tools/make-gallery.mjs` and committed, so the
cartridge builds with nothing but cc65 installed.

    make gallery         rewrite it
    make check-gallery   fail if it is stale

Graphics I gives a picture 256 patterns to build 768 cells from, so a picture
is a mosaic and these are geometric on purpose. Two of them — Rings and Spiral
— are drawn on a two-pixel grid rather than a one-pixel one: at full resolution
a circle crosses 487 of the 768 cells differently and the pattern table cannot
hold them all. The generator prints the distinct-cell count for each picture,
and folds anything over 256 into its nearest neighbour rather than failing.

Both cards
----------

`make VDP=1` builds against `6502-VDP.inc` for an ACE with a 6502-PICOVDP on
BIOS 2.x; the default builds against `6502.inc` for the TMS9918A on BIOS 1.x.
The body of the program is the same either way, because registers 0–7 mean the
same thing on both cards and Graphics I is one of them. The VDP build refuses
to run on a 1.x BIOS and says so.

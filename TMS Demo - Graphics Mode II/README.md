TMS Demo — Graphics Mode II
===========================

The Graphics Mode I demo turned up to full colour resolution: every cell on
screen gets its own checkerboard pattern *and* its own eight random colour
pairs, one per pixel row.

Press any key to restore text mode and return to BASIC.

How it works
------------

Graphics Mode II (R0 bit 1 set) keeps the 32 x 24 grid of 8x8 cells, but the
pattern and colour tables grow to 6144 bytes each and the screen splits into
three horizontal thirds of eight rows. Each third indexes its own 2 KB slice of
those tables, so filling the name table with `$00-$FF` three times gives all
768 cells a unique pattern and a unique colour slot.

The colour table is the interesting part: it is the same shape as the pattern
table, one byte per pattern byte, so *every pixel row* of every cell carries its
own foreground/background pair. This demo fills all 6144 colour bytes with
random pairs.

The tile is the same single-pixel checkerboard the Graphics Mode I demo uses,
which makes the two directly comparable: identical shape, but here each of the
eight pixel rows in a cell has its own colour pair rather than the whole cell
sharing one. Both row values (`%01010101` / `%10101010`) have four set and four
clear bits, so every row shows both of its colours.

Background colours are generated as `foreground XOR (non-zero delta)`, which
guarantees the two nibbles never match and the checkerboard is never invisible.
Colour 0 is transparent and shows the backdrop, which is black here, so it
simply reads as black.

VRAM layout:

| Address       | Table               | Register |
|---------------|---------------------|----------|
| `$0000-$17FF` | Pattern (6144 b)    | R4 = $03 |
| `$1800-$1AFF` | Name (768 bytes)    | R2 = $06 |
| `$1B00-$1B7F` | Sprite attributes   | R5 = $36 |
| `$2000-$37FF` | Colour (6144 b)     | R3 = $FF |
| `$3800-$3FFF` | Sprite patterns     | R6 = $07 |

R3 and R4 are interpreted differently in this mode: only their top address bit
selects the base (`$0000` or `$2000`), and the remaining low bits are an AND
mask over the table which must be all ones to expose the full 6144 bytes. Hence
`R3 = $FF` and `R4 = $03` rather than plain address multiples.

Notes
-----

- The PRNG uses a fixed seed, so the same screen appears every run.
- Interrupts are disabled while VRAM is loaded so the Kernal IRQ handler cannot
  touch the VDP between the two port writes that make up an address or register
  write. They are re-enabled to wait for a key, since input is IRQ driven.
- `InitVideo` ($A015) restores text mode fully — both the mode registers and the
  character set in the pattern table at `$0800`, which this demo overwrites. That
  requires BIOS v1.2 or later with the `InitVideo` character set reload; against
  an earlier BIOS the prompt comes back rendered in this demo's pattern and the
  program has to copy the character ROM at `$B800` into VRAM itself.
- The display is left blanked (R1 bit 6 = 0) until VRAM is loaded, which avoids
  a flash of garbage and gives VRAM writes unrestricted access. Loading ~13 KB
  of VRAM takes a moment on a real machine.

Install:

    brew install cc65

Build:

    make

View:

    make view

Run:

    make run

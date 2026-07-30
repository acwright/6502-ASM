TMS Demo — Multicolor Mode
==========================

Fills the screen with randomly coloured 4x4 pixel blocks (64 x 48 of them) to
exercise the TMS9918 Multicolor mode.

Press any key to restore text mode and return to BASIC.

How it works
------------

Multicolor mode has no colour table — colour comes straight out of the pattern
table, one nibble per 4x4 block (high nibble = left block, low nibble = right
block). Each 8x8 name table cell covers only 2x2 blocks, so it uses just 2 of
the 8 bytes of its pattern, chosen by the cell's row within its group of four:

| Rows        | Pattern bytes |
|-------------|---------------|
| 0, 4, 8, …  | 0-1           |
| 1, 5, 9, …  | 2-3           |
| 2, 6, 10, … | 4-5           |
| 3, 7, 11, … | 6-7           |

Giving all four rows of a group the same name lets one 8-byte pattern cover all
of them, which turns the pattern table into a plain linear framebuffer:

    name[row][col] = (row / 4) * 32 + col     -> 192 patterns
    192 patterns x 8 bytes                    -> 1536 bytes = 64 x 48 blocks

So the demo lays out the name table that way and then fills all 1536 pattern
bytes with random values.

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
  a flash of garbage and gives VRAM writes unrestricted access.

Install:

    brew install cc65

Build:

    make

View:

    make view

Run:

    make run

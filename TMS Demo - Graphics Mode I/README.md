TMS Demo — Graphics Mode I
==========================

Builds a character set of 256 identical checkerboards, colours it with all 32
foreground/background pairs Graphics Mode I allows, and fills the screen with
random characters to exercise the mode.

Press any key to restore text mode and return to BASIC.

How it works
------------

Graphics Mode I is 32 x 24 cells of 8x8 pixels, with each name table entry
selecting one of 256 patterns from the 2 KB pattern table. Colour is coarse:
the 32-byte colour table holds one entry per *group of eight* patterns (high
nibble = foreground, low nibble = background), so characters $00-$07 share
entry 0, $08-$0F share entry 1, and so on — 32 colour combinations per screen.

Since every pattern in this demo is the same single-pixel checkerboard
(`%01010101` / `%10101010` on alternating rows), the only thing that varies
across the screen is the colour pair, which is exactly the mode's colour
granularity made visible. Each 8x8 cell reads as one textured tile in its own two
colours.

The 1x1 grain is deliberate: Multicolor mode cannot draw anything finer than a
4x4 block, so resolving this texture at all confirms the VDP really is in
Graphics Mode I. (A 4x4 checkerboard here makes the output indistinguishable from
the Multicolor demo, which is not a useful test.)

VRAM layout:

| Address       | Table              | Register |
|---------------|--------------------|----------|
| `$0000-$02FF` | Name (768 bytes)   | R2 = $00 |
| `$0300-$031F` | Colour (32 bytes)  | R3 = $0C |
| `$0700-$077F` | Sprite attributes  | R5 = $0E |
| `$0800-$0FFF` | Pattern (2048 b)   | R4 = $01 |

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

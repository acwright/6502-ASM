VDP Tiles
=========

Scrolls a screen of 4bpp tiles diagonally and cycles one palette colour, on an
ACE with a 6502-PICOVDP running BIOS 2.x. Press any key to return to BASIC.

It is a VDP-only example: it includes `6502-VDP.inc` and drives the PICOVDP's
registers directly, so it has no TMS9918A build. On an older BIOS it prints
`NEEDS BIOS 2 AND A 6502-PICOVDP` and returns to BASIC.

Install:

    brew install cc65

Build:

    make

View:

    make view

Run:

    make run

To run it on a local BIOS image instead of the emulator's bundled one:

    make ROM=path/to/BIOS.bin run

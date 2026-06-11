KIM LED Demo — Binary Counter
=============================

Counts 0–255 on the 8 LEDs connected to the 74HC373 latch at `$9400`, stepping approximately every 500 ms. Wraps automatically and runs forever.

18 bytes of machine code — suitable for hand-entry via the KIM keypad at `$0800`.

Install:

    brew install cc65

Build:

    make

View:

    make view

## Machine Code

| Address | Bytes          | Instruction         |
|---------|----------------|---------------------|
| `$0800` | `64 36`        | `stz $36`           |
| `$0802` | `A5 36`        | `lda $36`           |
| `$0804` | `8D 00 94`     | `sta $9400`         |
| `$0807` | `A9 32`        | `lda #$32`          |
| `$0809` | `A2 00`        | `ldx #$00`          |
| `$080B` | `20 75 A0`     | `jsr $A075`         |
| `$080E` | `E6 36`        | `inc $36`           |
| `$0810` | `80 F0`        | `bra $0802`         |

To adjust the step rate, change the byte at `$0808` (`#$32` = 50 centiseconds ≈ 500 ms).

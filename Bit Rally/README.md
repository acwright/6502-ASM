Bit Rally
=========

A two-ended *Kill the Bit* for the [AC6502 KIM](https://github.com/acwright/6502-KIM):
eight LEDs, two players, one bit, and the two arrow keys on the pad.

A raw binary. Loads at `$0800`; the first byte of the file is the entry point — no
BASIC startup stub.

## How to play

One bit sweeps across the eight LEDs. Each end of the row is a kill zone, and each
zone belongs to a player:

```
   LED   7  6  5  4  3  2  1  0
         ●  ○  ○  ○  ○  ○  ○  ●
         ▲  ◄──────────────►  ▲
         │                    │
    LEFT kills here      RIGHT kills here
    with  ◄              with  ►
```

**Left** presses `◄` at the instant the bit is on LED 7. **Right** presses `►` at the
instant the bit is on LED 0. That is the whole game.

Anything else is ignored — the wrong key, the right key a frame early, the right key
in the other player's zone. Unlike the original *Kill the Bit* there is no penalty for
missing: a miss costs you nothing but the trip.

**The bit ping-pongs.** It runs to one end, turns around on the very frame it was
killable, and runs back to the other. Seven steps between the zones, fourteen for the
round trip — so a zone you have just missed is a long wait away, and you get to watch
the bit coming at you the whole way in.

Every round is dealt fresh: the bit starts at a **random position** travelling in a
**random direction**, so there is no reading the rhythm from the round before. It
never starts inside a kill zone — that would be a free point for whoever happened to
own that end.

### Two players, or one

Sit two people at the pad, one on each arrow. The game itself never knows how many
hands are on it — it only knows which end got hit — so playing alone means covering
both ends yourself, and the score just tells you which end you are better at.

### Scoring

The score is a single byte, shown on the LEDs between rounds and packed as two
nibbles:

```
   %1111 1111
    ──┬─ ──┬─
   left    right
```

So a display of `%1010 0011` is left 10, right 3. **First side to `$F` wins.**

You only see the score between rounds. While the bit is sweeping the display belongs
to the bit.

### A round

| | What you see | For how long |
|---|---|---|
| 1. Countdown | `$81` `$42` `$24` `$18` — two LEDs walking in from the ends until they meet | `COUNT_TIME` a step |
| 2. Sweep | The bit, ping-ponging end to end | `SWEEP_DELAY` a step, until somebody hits it |
| 3. Score | The packed score | `SCORE_TIME` |
| 4. Win | The final score, flashing | `WIN_FLASHES` × `WIN_TIME` |

Then back to the countdown, and the bit is dealt a new position and a new direction.
The countdown also runs once at startup, so nobody is caught cold.

At `$F` the game is won: the final score flashes — the winner's nibble reading `$F`
says who took it — and then the whole thing restarts from zero.

### Quitting

`ESC`. The KC Monitor aborts a running program from anywhere, so the game needs no
code for it and never stops on its own.

## Notes for the implementation

**Settle the win at `$F`.** A nibble holds 0–15. Incrementing a nibble that already
reads `$F` carries into the other player's score and corrupts it, so the win has to be
detected before or instead of that sixteenth increment.

**`Chrin` does not work on this machine.** `CartReset` repoints `IRQ_PTR` at the
cartridge's own `KeyIrq`, and `KeyIrq` never calls `WriteBuffer` — so the Kernal ring
at `$0200` is never fed and `Chrin` returns `C=0` forever. (The monitor reuses `$0200`
as its Wozmon line buffer, and puts serial bytes in its own ring at `$0400`.) Keypad
input comes from the monitor's one-deep mailbox in zero page instead:

```asm
KEY_CODE  := $44        ; Last keycode latched by KeyIrq
KEY_READY := $45        ; Nonzero when a press is waiting
```

Read `KEY_READY`, and if it's set take `KEY_CODE` and zero `KEY_READY` behind an
`SEI`/`CLI` so you don't race the ISR — but never leave `I` set, because ESC dies with
it.

**Clear `KEY_READY` every frame, hit or miss.** The mailbox is one press deep but it
holds that press indefinitely, so a press made three frames ago will score when the
bit finally arrives unless you have thrown it away.

**Zero page is not all yours.** The BIN template says `$3A–$FF` is free, and that is
true of a machine with nothing running underneath. Here the KC Monitor is live and
keeps its state in that range: `$40–$45` for the keypad monitor, `$46–$51` for the
serial Wozmon. What is actually free is **`$3A–$3F` and `$52–$FF`**.

**Randomness has to come from the player.** The KIM has no RTC and no VIA timer:
`HW_PRESENT` is `$10` and nothing else. A free-running counter ticked once per frame
and sampled at the moment of a hit is enough entropy for both draws, out of one read:
bits 0–2 are the position (`POS_MASK`), bit 3 is the direction (`DIR_MASK`, valued so
that `AND #DIR_MASK` yields `DIR_LEFT` or `DIR_RIGHT` directly). Turn the position
into a one-hot bit with an eight-byte table or a shift loop, and clamp it to
`POS_MIN`…`POS_MAX` so it never lands in a zone. An LFSR does the same job if you want
a longer period.

**The turn is not a free frame.** The bit occupies each end for exactly one
`SWEEP_DELAY` — the same as every other position — and reverses on that frame. If the
ends play too tight, the honest knobs are a slower `SWEEP_DELAY` or a deliberate extra
frame of dwell at each end; both change the feel a lot.

**Two open questions**, both cheap to change:

- The countdown is written here as a symmetric converge, `$81` `$42` `$24` `$18`. The
  series plan says "`$81`, `$62`, …", which isn't symmetric — if `$62` was deliberate,
  the table in `Bit Rally.asm` is the only thing that needs editing.
- With no miss penalty, mashing both keys is a viable strategy. Draining the buffer
  each frame at least forces the press to land inside the zone's own frame, but if you
  want it properly punished, the usual fix is a short lockout: a press outside your
  zone freezes that player for a few frames. That is an addition, not a change — the
  rules above stand without it.

## Tuning

All timings are in centiseconds (10 ms units), the `SysDelay` unit, and live at the
top of [Bit Rally.asm](<Bit Rally.asm>):

| Constant | Default | Effect |
|---|---|---|
| `SWEEP_DELAY` | `8` | Per LED step — **the difficulty knob**. Seven steps end to end, so 560 ms between zones |
| `COUNT_TIME` | `40` | Per countdown step |
| `SCORE_TIME` | `75` | How long the score sits on the LEDs after a hit |
| `WIN_TIME` | `20` | Per flash phase, on and off |
| `WIN_FLASHES` | `6` | Flashes before the game restarts |

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

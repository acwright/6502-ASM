.setcpu "65C02"

.include "../6502-KIM.inc"

.segment "CODE"

; =============================================================================
;   Bit Rally — a two-ended Kill the Bit for the AC6502 KIM
; =============================================================================
;   This is a raw binary image, not a BASIC program.  There is no tokenized
;   startup stub: the first byte of the file is the first byte of code, and it
;   lands at $0800 (PROGRAM_START).  Nothing may be placed before Start —
;   put data after the code, or behind a jump.
;
;   Target is the AC6502 KIM.  The Keypad Card overlays $C000-$FFFF, so the
;   machine boots into the KC Monitor rather than BASIC:
;     - No video, no sound, no storage, no RTC, no VIA (HW_PRESENT is $10)
;     - Chrout goes to the serial port; the LCD belongs to the monitor
;     - The eight LEDs are a write-only 74HC373 latch on the accessory bus
;     - ESC aborts a running program from anywhere — that needs no code here
;
;   Launching:
;     Keypad   $0800 then UP   calls here; RTS returns to the KC Monitor
;     Wozmon   0800R           jumps here; nothing to return to
;
;   ESC is the way out, and it is unconditional.  KeyIrq catches it before it
;   reaches the mailbox — from the pad or as an ESC byte over serial — and
;   JMPs to WarmStart, which does LDX #$FF / TXS and re-enters the monitor
;   loop.  The interrupted frame is abandoned, so it does not matter how deep
;   you were, what you had pushed, or how you were launched.  It also means
;   ESC does not return to your caller: it lands in the KC Monitor, always.
; =============================================================================
;   THE GAME
; =============================================================================
;   One bit sweeps across the eight LEDs.  Each end of the row is a kill zone
;   belonging to a player:
;
;     LED   7  6  5  4  3  2  1  0
;           ^                    ^
;           |                    |
;        LEFT kills           RIGHT kills
;        here with ◄          here with ►
;
;   A hit is a press made while the bit is standing in that player's zone —
;   ◄ while the pattern is $80, or ► while it is $01.  Anything else is
;   ignored: the wrong key, the right key a frame early, the right key in the
;   other player's zone.  Unlike the original Kill the Bit there is no penalty
;   for missing; a miss costs only the lap.
;
;   Two players, or one taking both ends.  The game never knows how many hands
;   are on the pad — it only knows which end got hit.
;
;   SCORING.  The score is one byte, packed as two nibbles, shown on the LEDs
;   between rounds:
;
;     %1111 1111
;      ^^^^ ^^^^
;      left right
;
;   First side to $F wins.  A nibble holds 0-15, so the win must be settled
;   at $F — incrementing a nibble that already reads $F carries into the other
;   player's score and corrupts it.
;
;   ROUND FLOW.
;     1. COUNTDOWN   the converging pattern below, one step per COUNT_TIME
;     2. SWEEP       the bit ping-pongs, one step per SWEEP_DELAY, until a hit
;     3. HIT         the packed score is displayed for SCORE_TIME
;     4. WIN         at $F, the final score flashes WIN_FLASHES times and the
;                    game restarts from zero
;
;   The score is only on the LEDs during step 3 — while the bit is sweeping,
;   the display belongs to the bit.  The countdown also runs once at startup,
;   before the first sweep, so nobody is caught cold.
;
;   THE SWEEP ping-pongs.  The bit runs to one end, and the frame it spends in
;   that kill zone is also the frame it turns around on; it then runs back to
;   the other end.  Seven steps between the zones, fourteen for a round trip,
;   so a zone you have just missed is a long way off — and you can watch the
;   bit coming at you the whole way.
;
;   Every round is dealt fresh: a random starting position AND a random
;   starting direction.  The entropy is the player's own reaction time, since
;   the KIM has no RTC and no VIA timer to read — a free-running counter
;   ticked once per frame and sampled at the moment of the hit is enough.  One
;   sample gives both: bits 0-2 are the position, bit 3 is the direction.
;
;   Clamp the starting position inward with POS_MIN / POS_MAX.  A bit that
;   starts life already standing in a kill zone hands that player a free point
;   on frame one, before they have even seen where it is.
;
;   INPUT comes from the KC Monitor's mailbox, NOT from Chrin — see the
;   Keypad section below.  The mailbox is one press deep and holds that press
;   indefinitely, so clear KEY_READY every frame whether it mattered or not.
;   A press left sitting from three frames ago must not be allowed to score
;   when the bit finally arrives.
; =============================================================================

; =============================================================================
;   Hardware
; =============================================================================
;   LEDS, the keypad mailbox and the Kernal entries all come from
;   6502-KIM.inc.  The latch is write-only — a read is open bus — so the
;   sweep keeps its own copy of the pattern rather than reading it back.

; =============================================================================
;   Zero page
; =============================================================================
;   Not the whole of $3A-$FF, whatever the BIN template says.  That is true of
;   a machine running nothing underneath you; here the KC Monitor is live and
;   keeps its own state in the "free" user page:
;
;     $00-$39   Kernal
;     $3A-$3F   yours
;     $40-$45   KC Monitor — CUR_ADDR, MODE, MON_TMP, KEY_CODE, KEY_READY
;     $46-$51   KC Monitor — serial Wozmon parser and RX ring indices
;     $52-$FF   yours
;
;   Also live below $0800: $0200 is the monitor's Wozmon line buffer and
;   $0400-$04FF its serial RX ring.  Neither is in our way at $0800.
; =============================================================================

; =============================================================================
;   Keypad — read the KC Monitor's mailbox, not Chrin
; =============================================================================
;   Chrin is not the way in on this machine.  CartReset repoints IRQ_PTR at
;   the cartridge's own KeyIrq, and KeyIrq never calls WriteBuffer — so the
;   Kernal ring at $0200 is never fed, and Chrin returns C=0 forever.  Serial
;   bytes go the same way, into the monitor's own ring at $0400.
;
;   KeyIrq latches the keycode into a one-deep mailbox instead:
;
;     lda KEY_READY
;     beq @NoKey
;     sei                       ; take both bytes without racing KeyIrq
;     lda KEY_CODE
;     stz KEY_READY
;     cli                       ; NEVER leave I set — ESC dies with it
;
;   These are the cartridge's own zero-page variables rather than a published
;   API, and they are still the lesser evil: KeyPoll sits in ROM with no
;   jump-table entry, so calling it means hardcoding an address that moves on
;   every firmware build.
; =============================================================================

;   KEY_CODE, KEY_READY, KEY_LEFT and KEY_RIGHT all come from 6502-KIM.inc.
;   The code is not the value — they come off the MM74C922 encoder in the
;   order the switches sit on the board, not the order they are printed.
;   ESC ($10) never reaches the mailbox: KeyIrq takes it and jumps to
;   WarmStart.

; =============================================================================
;   Scoring
; =============================================================================

SCORE_WIN   = $0F               ; First nibble to reach this wins
MASK_LEFT   = %11110000         ; Left player's nibble
MASK_RIGHT  = %00001111         ; Right player's nibble
INC_LEFT    = $10               ; One point in the upper nibble
INC_RIGHT   = $01               ; One point in the lower nibble

; =============================================================================
;   Kill zones
; =============================================================================
;   The bit turns around on the same frame it is killable.

ZONE_LEFT  = %10000000          ; $80 — LED 7, killed with ◄
ZONE_RIGHT = %00000001          ; $01 — LED 0, killed with ►

; =============================================================================
;   Sweep direction
; =============================================================================
;   Valued to drop straight out of the frame counter: AND #DIR_MASK gives one
;   or the other with no further work.
; =============================================================================

DIR_MASK  = %00001000           ; Counter bit 3 -> starting direction
DIR_LEFT  = %00000000           ; Travelling toward LED 7 — ASL
DIR_RIGHT = %00001000           ; Travelling toward LED 0 — LSR

; =============================================================================
;   Starting position
; =============================================================================

POS_MASK = %00000111            ; Counter bits 0-2 -> position 0-7
POS_MIN  = 1                    ; Clamped inward, so the bit never starts
POS_MAX  = 6                    ; life inside a kill zone

; =============================================================================
;   Timing — all in centiseconds (10 ms units), the SysDelay unit
; =============================================================================

SWEEP_DELAY = 8                 ; Per LED step.  The difficulty knob: seven
                                ; steps end to end, so 560 ms between zones
COUNT_TIME  = 40                ; Per countdown step
SCORE_TIME  = 75                ; How long the score sits on the LEDs
WIN_TIME    = 20                ; Per flash phase, on and off
WIN_FLASHES = 6                 ; Flashes before the game restarts

; =============================================================================
;   Start — Program entry point ($0800)
; =============================================================================
Start:
  lda #0
  sta Score

; =============================================================================
;   Do Round — The entry point for each round
; =============================================================================

DoRound:
  jsr CountdownDisplay          ; Show the countdown when the round begins
  jsr SweepInit                 ; Start the sweep; When we fall out a hit has occurred...

  lda Score
  and #MASK_LEFT                ; Mask out the upper nibble
  lsr
  lsr
  lsr
  lsr                           ; and shift it right four bits
  cmp #SCORE_WIN                ; Did left player win?
  beq @DoRoundWinner            ; if so show win

  lda Score
  and #MASK_RIGHT               ; Mask out the lower nibble
  cmp #SCORE_WIN                ; Did right player win?
  beq @DoRoundWinner            ; if so show win

  jsr ScoreDisplay              ; ...otherwise show the score
  jmp DoRound                   ; and play the next round
@DoRoundWinner:
  jsr WinDisplay                ; Display the winner
  jmp Start                     ; Restart

; =============================================================================
;   Check Input — Latch and clear the mailbox, once per frame
; =============================================================================
;   Must run every frame regardless of outcome — see the INPUT note up top.
;   LastKey is left at $FF ("no key") on a miss; no keycode off the MM74C922
;   can ever collide with that, so CheckHit can trust it below.

CheckInput:
  lda KEY_READY
  beq @CheckInputIsZero         ; No key; fall out of check
  lda KEY_CODE                  ; otherwise get the key code
  sta LastKey                   ; and store it
  stz KEY_READY                 ; Clear key ready
  bra @CheckInputDone           ; and exit
@CheckInputIsZero:
  lda #$FF                      ; $FF sentinel — no real keycode reaches this
  sta LastKey                   ; far, so it can't be mistaken for a press
@CheckInputDone:
  rts

; =============================================================================
;   Check Hit — Score a hit if SweepVal's zone matches LastKey
; =============================================================================
;   Must run before SweepVal is stepped below — this is checking whether the
;   value that was just shown and delayed on (still in SweepVal) was killed,
;   not the value the bit is about to move to next.

CheckHit:
  lda #0
  sta Hit                       ; Clear Hit — stale non-zero here would end
                                ; every future sweep on frame one
  lda SweepVal
  cmp #ZONE_LEFT                ; Are we in the left kill zone?
  beq @CheckHitLeft             ; Continue to the left hit check
  cmp #ZONE_RIGHT               ; Are we in the right kill zone?
  beq @CheckHitRight            ; Continue to the right hit check
  bra @CheckHitDone             ; otherwise fall out of check

@CheckHitLeft:
  lda LastKey                   ; Load the last key press
  cmp #KEY_LEFT                 ; Is it the left key?
  beq @CheckHitDoHitLeft        ; if so record the hit
  bra @CheckHitDone             ; if not, exit

@CheckHitRight:
  lda LastKey                   ; Load the last key press
  cmp #KEY_RIGHT                ; Is it the right key?
  beq @CheckHitDoHitRight       ; if so record the hit
  bra @CheckHitDone             ; if not, exit

@CheckHitDoHitLeft:
  lda #1
  sta Hit                       ; Store the hit
  lda Score
  clc
  adc #INC_LEFT                 ; Increment the player left score
  sta Score
  bra @CheckHitDone             ; Exit

@CheckHitDoHitRight:
  lda #1
  sta Hit                       ; Store the hit
  lda Score
  clc
  adc #INC_RIGHT                ; Increment the player right score
  sta Score                     ; Falls through to @CheckHitDone

@CheckHitDone:
  rts

; =============================================================================
;   Sweep Init — The sweep init routine
; =============================================================================

SweepInit:
  lda Counter                   ; Load the last counter value
  and #DIR_MASK                 ; and get the direction
  sta SweepDir

  lda Counter                   ; Load the last counter value again
  and #POS_MASK                 ; and get the possible starting position (0-7)

  cmp #POS_MIN
  bcs @SweepPosNotBelow         ; If A >= POS_MIN, skip to next check
  lda #POS_MIN                  ; otherwise clamp to POS_MIN
@SweepPosNotBelow:
  cmp #POS_MAX
  bcc @SweepPosClamped          ; If A < POS_MAX, we are good
  lda #POS_MAX                  ; otherwise clamp to POS_MAX
@SweepPosClamped:
  tax                           ; X = clamped position, 1-6

  lda #1                        ; build the one-hot pattern, starting at bit 0
@SweepPosShift:
  cpx #0
  beq @SweepPosShiftDone
  asl                           ; walk the lit bit up to the starting position
  dex
  bra @SweepPosShift
@SweepPosShiftDone:
  sta SweepVal                  ; store the one-hot starting position

; =============================================================================
;   Sweep Display — The sweep display loop
; =============================================================================

SweepDisplay:
  inc Counter                   ; Free-running; also reseeds next round's SweepInit

  lda SweepVal                  ; Show the bit at its current position
  sta LEDS
  jsr SweepDelay
  jsr CheckInput                ; Latch this frame's key press, or $FF
  jsr CheckHit                  ; Score against the position just shown above —
                                ; both must run before SweepVal moves below
  lda Hit
  bne @SweepDisplayDone         ; A hit ends the sweep

  lda SweepDir
  cmp #DIR_LEFT
  beq @SweepLeft                ; DIR_LEFT  -> walking toward LED 7, step with ASL
  bra @SweepRight               ; DIR_RIGHT -> walking toward LED 0, step with LSR

@SweepLeft:
  lda SweepVal                  ; Reload — SweepDir was in A for the check above
  asl                           ; One step toward LED 7
  sta SweepVal
  cmp #ZONE_LEFT                ; Landed in the left kill zone?
  beq @SweepReverse
  bra SweepDisplay

@SweepRight:
  lda SweepVal                  ; Reload — SweepDir was in A for the check above
  lsr                           ; One step toward LED 0
  sta SweepVal
  cmp #ZONE_RIGHT               ; Landed in the right kill zone?
  beq @SweepReverse
  bra SweepDisplay

@SweepReverse:
  lda SweepDir
  eor #DIR_MASK                 ; Flip toward the opposite wall
  sta SweepDir
  bra SweepDisplay              ; The bit still shows in the zone on the next pass

@SweepDisplayDone:              ; Reached only when CheckHit sets Hit, above
  rts                           ; Unwinds through SweepInit's fallthrough, back to DoRound

; =============================================================================
;   Sweep Delay - The sweep delay subroutine
; =============================================================================

SweepDelay:
  phy                           ; SysDelay clobbers Y so lets save it...
  lda #SWEEP_DELAY
  ldx #0
  jsr SysDelay                  ; Delay for SWEEP_DELAY centiseconds
  ply                           ; and restore it
  rts

; =============================================================================
;   Countdown Display — The countdown display loop
; =============================================================================

CountdownDisplay:
  lda #0
  sta LEDS                      ; Clear the LEDs
  ldy #0
@CountdownDisplayLoop:
  jsr CountdownDelay
  lda Countdown,y               ; Load the next byte from the countdown data
  sta LEDS
  iny
  tya
  cmp #COUNTDOWN_LEN
  bne @CountdownDisplayLoop
@CountdownDisplayExit:
  jsr CountdownDelay
  lda #$FF                      ; Light all the LEDs
  sta LEDS
  rts

; =============================================================================
;   Countdown Delay - The countdown delay subroutine
; =============================================================================

CountdownDelay:
  phy                           ; SysDelay clobbers Y so lets save it...
  lda #COUNT_TIME
  ldx #0
  jsr SysDelay                  ; Delay for COUNT_TIME centiseconds
  ply                           ; and restore it
  rts

; =============================================================================
;   Score Display — The score display routine
; =============================================================================

ScoreDisplay:
  lda Score
  sta LEDS
  jsr ScoreDelay
  rts

; =============================================================================
;   Score Delay - The score delay subroutine
; =============================================================================

ScoreDelay:
  phy                           ; SysDelay clobbers Y so lets save it...
  lda #SCORE_TIME
  ldx #0
  jsr SysDelay                  ; Delay for SCORE_TIME centiseconds
  ply                           ; and restore it
  rts

; =============================================================================
;   Win Display — The win display routine
; =============================================================================

WinDisplay:
  ldy #WIN_FLASHES
@WinDisplayLoop:
  lda Score
  sta LEDS
  jsr WinDelay
  lda #0
  sta LEDS
  jsr WinDelay
  dey
  tya
  bne @WinDisplayLoop
@WinDisplayExit:
  rts

; =============================================================================
;   Win Delay - The win delay subroutine
; =============================================================================

WinDelay:
  phy                           ; SysDelay clobbers Y so lets save it...
  lda #WIN_TIME
  ldx #0
  jsr SysDelay                  ; Delay for WIN_TIME centiseconds
  ply                           ; and restore it
  rts

; =============================================================================
;   Data
; =============================================================================

Score:    .byte 0               ; The players score; Upper nibble player left - Lower nibble player right
Counter:  .byte 0               ; The sweep counter
SweepVal: .byte 0               ; Current sweep value
SweepDir: .byte 0               ; Current sweep direction
LastKey:  .byte $FF             ; Latched by CheckInput each frame; $FF means no key
Hit:      .byte 0               ; Set by CheckHit; cleared at the top of every call

; The countdown: two lit LEDs walking in from the ends until they meet.
; Four steps of COUNT_TIME, then the sweep starts.
;
;   $81  %10000001
;   $42  %01000010
;   $24  %00100100
;   $18  %00011000

Countdown:
  .byte $81, $42, $24, $18
COUNTDOWN_LEN = * - Countdown

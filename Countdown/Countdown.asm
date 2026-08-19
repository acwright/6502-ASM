.setcpu "65C02"

.include "../6502-KIM.inc"

.segment "CODE"

; =============================================================================
;   Coundown - An LED countdown for the KIM
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
;   Hardware
; =============================================================================
;   LEDS and the Kernal entries come from 6502-KIM.inc.  The latch is
;   write-only — a read is open bus — so the countdown keeps its own copy
;   of the pattern rather than reading it back.

; =============================================================================
;   Timing — all in centiseconds (10 ms units), the SysDelay unit
; =============================================================================

DELAY = 32

; =============================================================================
;   Start — Program entry point ($0800)
; =============================================================================

Start:
  jsr CountdownDisplay
  rts

; =============================================================================
;   CountdownDisplay — The countdown display loop
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
  lda #DELAY
  ldx #0
  jsr SysDelay                  ; Delay for DELAY centiseconds
  ply                           ; and restore it
  rts

; =============================================================================
;   Data
; =============================================================================

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

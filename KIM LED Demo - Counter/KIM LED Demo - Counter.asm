.setcpu "65C02"

.include "../6502.inc"

.segment "CODE"

; =============================================================================
;   KIM LED Demo — Binary Counter ($0800)
; =============================================================================
;   Counts 0–255 on the 8 LEDs connected to the 74HC373 latch at $9400.
;   Uses SysDelay (centiseconds) for a visible ~500 ms step rate.
;   Wraps naturally at 255 → 0 and runs forever.
;
;   Machine code (19 bytes):
;     0800: 64 36 A5 36 8D 00 94 A9 32 A2 00 20 75 A0 E6 36 80 F0
; =============================================================================

LED         = $9400          ; 74HC373 LED latch
DELAY_CS    = 50             ; delay in centiseconds (~500 ms per step)
CNT         = $36            ; zero-page counter ($36–$FF free for user programs)

Start:
  stz CNT                    ; start counter at 0
Loop:
  lda CNT
  sta LED                    ; show current count on LEDs
  lda #DELAY_CS
  ldx #0                     ; high byte of delay
  jsr SysDelay               ; wait ~500 ms
  inc CNT                    ; advance counter (wraps $FF → $00 automatically)
  bra Loop                   ; repeat forever

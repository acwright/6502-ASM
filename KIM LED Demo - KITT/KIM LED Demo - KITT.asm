.setcpu "65C02"

.include "../6502.inc"

.segment "CODE"

; =============================================================================
;   KIM LED Demo — KITT Scanner ($0800)
; =============================================================================
;   Single LED bounces left and right on the 8 LEDs at $9400,
;   like the KITT scanner from Knight Rider.
;   Uses SysDelay (centiseconds) for ~100 ms per step.
;   Runs forever.
;
;   Machine code (38 bytes):
;     0800: A0 00 B9 18 08 8D 00 94 5A A9 0A A2 00 20 75 A0
;     0810: 7A C8 C0 0E D0 EC 80 E8
;     0818: 01 02 04 08 10 20 40 80 40 20 10 08 04 02
; =============================================================================

LED         = $9400          ; 74HC373 LED latch
DELAY_CS    = 10             ; delay in centiseconds (~100 ms per step)

Start:
  ldy #0
Loop:
  lda Table,y
  sta LED                    ; show current LED pattern
  phy                        ; save index — SysDelay clobbers Y
  lda #DELAY_CS
  ldx #0                     ; SysDelay high byte
  jsr SysDelay               ; wait ~100 ms
  ply                        ; restore index
  iny
  cpy #14                    ; 14 steps per sweep cycle (0..13)
  bne Loop
  bra Start                  ; restart sweep

Table:
  .byte $01,$02,$04,$08,$10,$20,$40,$80  ; sweep left  → right
  .byte $40,$20,$10,$08,$04,$02          ; sweep right → left

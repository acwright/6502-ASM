.setcpu "65C02"

.include "../6502.inc"

.segment "CODE"

; =============================================================================
;   BASIC Startup Stub
; =============================================================================
;   A tokenized BASIC line: 10 SYS 2060
;   When this program is loaded into $0800 and RUN in BASIC, the SYS command
;   jumps to the machine code entry point at $080C (decimal 2060).
;   This stub must remain at the very start of the program.

BasicStartup: .byte $0A, $08, $0A, $00, $A5, $32, $30, $36, $30, $00, $00, $00

; =============================================================================
;   TMS9918 Multicolor Mode Demo ($080C)
; =============================================================================
;   Fills the screen with randomly coloured 4x4 pixel blocks, then waits for
;   a key press, restores text mode, and returns to BASIC.
;
;   MULTICOLOR MODE
;   ---------------
;   Selected by M1=0, M2=1, M3=0 (R1 bit 3 set).  The display is 64 x 48
;   blocks of 4 x 4 pixels.  There is no colour table — colour comes straight
;   out of the pattern table, one nibble per block (high nibble = left block,
;   low nibble = right block).
;
;   Each of the 32 x 24 name table cells covers 8 x 8 pixels = 2 x 2 blocks,
;   so it consumes only 2 of the 8 bytes of its pattern.  Which pair is used
;   depends on the cell's row: rows 0,4,8..  use bytes 0-1, rows 1,5,9.. use
;   bytes 2-3, rows 2,6,10.. use bytes 4-5, rows 3,7,11.. use bytes 6-7.
;
;   Giving the four rows of each row-group the *same* name therefore lets one
;   8-byte pattern cover all four, and the pattern table becomes a plain
;   linear framebuffer:
;
;     name[row][col] = (row / 4) * 32 + col        -> 192 patterns
;     192 patterns x 8 bytes                       -> 1536 bytes = 64 x 48
;
;   So filling the pattern table with random bytes paints the whole screen.
; =============================================================================

; --- Zero page (safe user range is $3A-$FF) ---
RND             = $3A               ; 2 bytes — PRNG state (must never be $0000)
ROW_BASE        = $3C               ; 1 byte  — name table base for current row

; --- VRAM layout ---
MC_NAME         = $0000             ; Name table          ($0000-$02FF, 768 bytes)
MC_SPR_ATTR     = $0700             ; Sprite attributes   ($0700-$077F)
MC_PATTERN      = $0800             ; Pattern table       ($0800-$0DFF, 1536 bytes)

; --- Screen geometry (the graphics modes are 32 columns wide, not 40) ---
GFX_COLS        = 32
GFX_ROWS        = VID_ROWS

; --- Register 1 values (16K VRAM, VDP interrupt off, Multicolor mode) ---
R1_BLANK        = %10001000         ; Display blanked — used while loading VRAM
R1_ACTIVE       = %11001000         ; Display enabled

RND_SEED        = $A55A             ; Fixed seed: the same screen every run

; =============================================================================
;   Start — Program entry point
; =============================================================================

Start:
  lda HW_PRESENT
  and #HW_VID                       ; Is a video card present?
  bne @HaveVideo
  lda #<NoVideoMsg
  ldy #>NoVideoMsg
  jsr PrintStr
  jsr PrintCRLF
  rts                               ; Nothing to demo — back to BASIC

@HaveVideo:
  sei                               ; The Kernal IRQ handler must not touch the
                                    ; VDP between our two-byte port writes
  jsr InitRandom
  jsr InitMode                      ; Mode registers, display still blanked
  jsr HideSprites
  jsr FillNames                     ; Name table -> linear framebuffer layout
  jsr FillPatterns                  ; Pattern table -> random block colours
  jsr ShowDisplay
  cli

  jsr WaitKey                       ; Needs interrupts — input is IRQ driven

  sei
  jsr InitVideo                     ; Restore the BIOS text mode
  jsr VideoClear
  cli

End:
  rts                               ; Return to BASIC

; =============================================================================
;   InitMode — Load the VDP registers for Multicolor mode
; =============================================================================

InitMode:
  lda VC_STATUS                     ; Reset the VDP address/data flip-flop
  ldx #0
@Loop:
  lda VdpRegs,x
  sta VC_REG                        ; Data byte first...
  txa
  ora #$80                          ; ...then register number | $80
  sta VC_REG
  inx
  cpx #8
  bne @Loop
  rts

; =============================================================================
;   ShowDisplay — Un-blank the display now that VRAM is loaded
; =============================================================================

ShowDisplay:
  lda #R1_ACTIVE
  ldx #1
  jmp SetVdpReg

; =============================================================================
;   HideSprites — Terminate the sprite list so no sprites are drawn
; =============================================================================

HideSprites:
  lda #<MC_SPR_ATTR
  ldx #>MC_SPR_ATTR
  jsr SetVramWrite
  lda #$D0                          ; Y = $D0 ends the sprite list
  sta VC_DATA
  rts

; =============================================================================
;   FillNames — Lay the name table out as a linear framebuffer
; =============================================================================
;   name[row][col] = (row / 4) * 32 + col
;   (row / 4) * 32 is the same as (row & $FC) * 8, which is three shifts.

FillNames:
  lda #<MC_NAME
  ldx #>MC_NAME
  jsr SetVramWrite
  ldx #0                            ; X = row (0-23)
@Row:
  txa
  and #$FC                          ; Drop the low 2 bits (row within group)
  asl a
  asl a
  asl a                             ; x 8  ->  (row / 4) * 32
  sta ROW_BASE
  ldy #0                            ; Y = column (0-31)
@Col:
  tya
  clc
  adc ROW_BASE
  sta VC_DATA
  iny
  cpy #GFX_COLS
  bne @Col
  inx
  cpx #GFX_ROWS
  bne @Row
  rts

; =============================================================================
;   FillPatterns — Paint every 4x4 block a random colour
; =============================================================================
;   1536 bytes = 6 x 256.  Each byte holds two blocks: high nibble = left,
;   low nibble = right.  Colour 0 is transparent and shows the backdrop.

FillPatterns:
  lda #<MC_PATTERN
  ldx #>MC_PATTERN
  jsr SetVramWrite
  ldx #6                            ; 6 blocks of 256 bytes
@Block:
  ldy #0
@Byte:
  jsr Random
  sta VC_DATA
  iny
  bne @Byte
  dex
  bne @Block
  rts

; =============================================================================
;   VDP Helpers
; =============================================================================

; SetVdpReg — write a VDP register
;   In: A = value, X = register number (0-7)
SetVdpReg:
  sta VC_REG
  txa
  ora #$80
  sta VC_REG
  rts

; SetVramWrite — set the VRAM address for auto-incrementing writes
;   In: A = address low byte, X = address high byte
SetVramWrite:
  sta VC_REG
  txa
  ora #$40                          ; $40 flags a write
  sta VC_REG
  rts

; =============================================================================
;   Random — 16-bit xorshift PRNG
; =============================================================================
;   Out: A = pseudo-random byte.  Preserves X and Y.

InitRandom:
  lda #<RND_SEED
  sta RND
  lda #>RND_SEED
  sta RND+1
  rts

Random:
  lda RND+1
  lsr a
  lda RND
  ror a
  eor RND+1
  sta RND+1
  ror a
  eor RND
  sta RND
  eor RND+1
  sta RND+1
  rts

; =============================================================================
;   WaitKey — Discard pending input, then block until a key is pressed
; =============================================================================

WaitKey:
  jsr BufferSize                    ; A = unread bytes in the input buffer
  cmp #0
  beq @Wait
  jsr ReadBuffer                    ; Drain stale input (no echo)
  bra WaitKey
@Wait:
  jsr BufferSize
  cmp #0
  beq @Wait
  jsr ReadBuffer
  rts

; =============================================================================
;   Data
; =============================================================================

; VDP registers 0-7
VdpRegs:
  .byte $00                         ; R0: M3=0, no external video
  .byte R1_BLANK                    ; R1: 16K, blanked, Multicolor mode
  .byte $00                         ; R2: name table         @ $0000
  .byte $00                         ; R3: unused in Multicolor mode
  .byte $01                         ; R4: pattern table      @ $0800
  .byte $0E                         ; R5: sprite attributes  @ $0700
  .byte $01                         ; R6: sprite patterns    @ $0800
  .byte TMS_BLACK                   ; R7: backdrop colour

NoVideoMsg: .asciiz "No video card present."

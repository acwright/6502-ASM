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
;   TMS9918 Graphics Mode II Demo ($080C)
; =============================================================================
;   Same idea as the Graphics Mode I demo, but with per-row colour: every cell
;   on screen gets its own checkerboard pattern *and* its own eight random
;   colour pairs, one per pixel row.  Waits for a key press, restores text
;   mode, and returns to BASIC.
;
;   GRAPHICS MODE II
;   ----------------
;   Selected by M3=1 (R0 bit 1 set).  Still 32 x 24 cells of 8 x 8 pixels, but
;   the pattern and colour tables grow to 6144 bytes each and the screen is
;   split into three horizontal thirds of 8 rows.  Each third indexes its own
;   2 KB slice of those tables, so all 768 cells can have unique pixels and
;   unique colour — 256 KB worth of freedom compared to Mode I's 256 patterns.
;
;   The colour table is the important part: it is the same shape as the
;   pattern table, one byte per pattern byte, so *every pixel row* of every
;   cell carries its own foreground/background pair (high nibble / low
;   nibble).  This demo fills all 6144 colour bytes with random pairs.
;
;   VRAM layout (the usual Graphics II arrangement):
;     $0000-$17FF   Pattern table    (6144 bytes)   R4 = $03
;     $1800-$1AFF   Name table       (768 bytes)    R2 = $06
;     $1B00-$1B7F   Sprite attrs                    R5 = $36
;     $2000-$37FF   Colour table     (6144 bytes)   R3 = $FF
;     $3800-$3FFF   Sprite patterns                 R6 = $07
;
;   Note R3 and R4 are interpreted differently in this mode: only their top
;   address bit selects the base ($0000 or $2000) and the remaining low bits
;   are an AND mask over the table, which must be all ones to expose the full
;   6144 bytes.  Hence R3 = $FF and R4 = $03 rather than plain multiples.
; =============================================================================

; --- Zero page (safe user range is $3A-$FF) ---
RND             = $3A               ; 2 bytes — PRNG state (must never be $0000)
TMP             = $3C               ; 1 byte  — scratch
FG              = $3D               ; 1 byte  — foreground nibble being built
BLOCKS          = $3E               ; 1 byte  — outer loop counter

; --- Screen geometry (the graphics modes are 32 columns wide, not 40) ---
GFX_COLS        = 32
GFX_ROWS        = VID_ROWS
GFX_CELLS       = GFX_COLS * GFX_ROWS   ; 768 name table entries

; --- VRAM layout ---
G2_PATTERN      = $0000             ; Pattern table      ($0000-$17FF, 6144 bytes)
G2_NAME         = $1800             ; Name table         ($1800-$1AFF, 768 bytes)
G2_SPR_ATTR     = $1B00             ; Sprite attributes  ($1B00-$1B7F)
G2_COLOR        = $2000             ; Colour table       ($2000-$37FF, 6144 bytes)

; --- Register 1 values (16K VRAM, VDP interrupt off) ---
R1_BLANK        = %10000000         ; Display blanked — used while loading VRAM
R1_ACTIVE       = %11000000         ; Display enabled

RND_SEED        = $1234             ; Fixed seed: the same screen every run

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
  jsr FillPatterns                  ; 768 checkerboards, one per cell
  jsr FillColors                    ; A random colour pair per pixel row
  jsr FillNames                     ; $00-$FF in each third of the screen
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
;   InitMode — Load the VDP registers for Graphics Mode II
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
  lda #<G2_SPR_ATTR
  ldx #>G2_SPR_ATTR
  jsr SetVramWrite
  lda #$D0                          ; Y = $D0 ends the sprite list
  sta VC_DATA
  rts

; =============================================================================
;   FillPatterns — The same checkerboard in all 768 pattern slots
; =============================================================================
;   6144 bytes = 3 x 256 patterns x 8 bytes.

FillPatterns:
  lda #<G2_PATTERN
  ldx #>G2_PATTERN
  jsr SetVramWrite
  lda #GFX_CELLS / 256              ; 3 thirds of 256 patterns
  sta BLOCKS
@Block:
  ldy #0                            ; 256 patterns (Y wraps to 0)
@Pattern:
  ldx #0
@Row:
  lda Checker,x
  sta VC_DATA
  inx
  cpx #8
  bne @Row
  dey
  bne @Pattern
  dec BLOCKS
  bne @Block
  rts

; =============================================================================
;   FillColors — A random foreground/background pair for every pixel row
; =============================================================================
;   6144 bytes = 24 x 256.  This is what Mode II buys you over Mode I: eight
;   independent colour pairs per cell instead of one per eight characters.

FillColors:
  lda #<G2_COLOR
  ldx #>G2_COLOR
  jsr SetVramWrite
  ldx #24                           ; 24 blocks of 256 bytes
@Block:
  ldy #0
@Byte:
  jsr RandomColor
  sta VC_DATA
  iny
  bne @Byte
  dex
  bne @Block
  rts

; =============================================================================
;   FillNames — Point each third of the screen at its own table slice
; =============================================================================
;   768 bytes = $00-$FF repeated three times, so every cell has a unique
;   pattern/colour slot.

FillNames:
  lda #<G2_NAME
  ldx #>G2_NAME
  jsr SetVramWrite
  ldx #GFX_CELLS / 256              ; 3 thirds of 256 cells
@Block:
  ldy #0
@Byte:
  tya
  sta VC_DATA
  iny
  bne @Byte
  dex
  bne @Block
  rts

; =============================================================================
;   RandomColor — Build a colour byte whose two nibbles always differ
; =============================================================================
;   Out: A = (foreground << 4) | background, foreground != background.
;   Preserves X and Y.
;
;   The background is derived as foreground XOR a non-zero delta, which
;   guarantees the two nibbles never match and so the checkerboard is always
;   visible.  Colour 0 is transparent and shows the backdrop, which is black
;   here, so it simply reads as black.

RandomColor:
  jsr Random
  sta TMP
  and #$0F
  sta FG                            ; Foreground = low nibble (0-15)
  lda TMP
  lsr a
  lsr a
  lsr a
  lsr a                             ; High nibble becomes the XOR delta
  bne @Delta
  lda #$01                          ; A zero delta would leave background = foreground
@Delta:
  eor FG                            ; Background = foreground XOR delta
  sta TMP
  lda FG
  asl a
  asl a
  asl a
  asl a
  ora TMP
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
  .byte $02                         ; R0: M3=1 (Graphics Mode II)
  .byte R1_BLANK                    ; R1: 16K, blanked
  .byte $06                         ; R2: name table         @ $1800
  .byte $FF                         ; R3: colour table       @ $2000, full mask
  .byte $03                         ; R4: pattern table      @ $0000, full mask
  .byte $36                         ; R5: sprite attributes  @ $1B00
  .byte $07                         ; R6: sprite patterns    @ $3800
  .byte TMS_BLACK                   ; R7: backdrop colour

; Every pattern is the same single-pixel checkerboard used by the Graphics Mode I
; demo, which makes the two directly comparable: identical tile, but here each
; of its eight pixel rows carries its own colour pair instead of the whole cell
; sharing one.  Both row values have four set and four clear bits, so every row
; shows both of its colours.
Checker:
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010

NoVideoMsg: .asciiz "No video card present."

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
;   TMS9918 Graphics Mode I Demo ($080C)
; =============================================================================
;   Builds a character set of 256 identical checkerboard patterns, gives the
;   colour table 32 different foreground/background pairs, and fills the
;   screen with random characters.  Waits for a key press, restores text mode,
;   and returns to BASIC.
;
;   GRAPHICS MODE I
;   ---------------
;   Selected by M1=0, M2=0, M3=0 (the plain graphics mode).  The screen is
;   32 x 24 cells of 8 x 8 pixels.  Each name table entry selects one of 256
;   patterns from the 2 KB pattern table.
;
;   Colour is coarse: the 32-byte colour table holds one entry per *group of
;   eight* patterns (high nibble = foreground, low nibble = background), so
;   characters $00-$07 share entry 0, $08-$0F share entry 1, and so on.
;   That gives exactly 32 colour combinations per screen — which is what this
;   demo shows off.  Since every pattern is the same checkerboard, the only
;   thing that varies across the screen is the colour pair.
; =============================================================================

; --- Zero page (safe user range is $3A-$FF) ---
RND             = $3A               ; 2 bytes — PRNG state (must never be $0000)

; --- Screen geometry (the graphics modes are 32 columns wide, not 40) ---
GFX_COLS        = 32
GFX_ROWS        = VID_ROWS
GFX_CELLS       = GFX_COLS * GFX_ROWS   ; 768 name table entries

; --- VRAM layout ---
G1_NAME         = $0000             ; Name table         ($0000-$02FF, 768 bytes)
G1_COLOR        = $0300             ; Colour table       ($0300-$031F, 32 bytes)
G1_SPR_ATTR     = $0700             ; Sprite attributes  ($0700-$077F)
G1_PATTERN      = $0800             ; Pattern table      ($0800-$0FFF, 2048 bytes)

; --- Register 1 values (16K VRAM, VDP interrupt off, Graphics mode) ---
R1_BLANK        = %10000000         ; Display blanked — used while loading VRAM
R1_ACTIVE       = %11000000         ; Display enabled

RND_SEED        = $C33C             ; Fixed seed: the same screen every run

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
  jsr FillPatterns                  ; 256 copies of the checkerboard
  jsr FillColors                    ; 32 foreground/background pairs
  jsr FillNames                     ; Random character in every cell
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
;   InitMode — Load the VDP registers for Graphics Mode I
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
  lda #<G1_SPR_ATTR
  ldx #>G1_SPR_ATTR
  jsr SetVramWrite
  lda #$D0                          ; Y = $D0 ends the sprite list
  sta VC_DATA
  rts

; =============================================================================
;   FillPatterns — Give all 256 characters the same checkerboard pattern
; =============================================================================
;   256 patterns x 8 bytes = 2048 bytes.

FillPatterns:
  lda #<G1_PATTERN
  ldx #>G1_PATTERN
  jsr SetVramWrite
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
  rts

; =============================================================================
;   FillColors — One foreground/background pair per group of 8 characters
; =============================================================================

FillColors:
  lda #<G1_COLOR
  ldx #>G1_COLOR
  jsr SetVramWrite
  ldx #0
@Loop:
  lda Colors,x
  sta VC_DATA
  inx
  cpx #32
  bne @Loop
  rts

; =============================================================================
;   FillNames — Put a random character in every screen cell
; =============================================================================
;   768 bytes = 3 x 256.  A random character code picks a random colour group.

FillNames:
  lda #<G1_NAME
  ldx #>G1_NAME
  jsr SetVramWrite
  ldx #GFX_CELLS / 256              ; 3 blocks of 256 bytes
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
  .byte R1_BLANK                    ; R1: 16K, blanked, Graphics Mode I
  .byte $00                         ; R2: name table         @ $0000
  .byte $0C                         ; R3: colour table       @ $0300
  .byte $01                         ; R4: pattern table      @ $0800
  .byte $0E                         ; R5: sprite attributes  @ $0700
  .byte $01                         ; R6: sprite patterns    @ $0800
  .byte TMS_BLACK                   ; R7: backdrop colour

; The one and only character: a single-pixel checkerboard filling the 8x8 cell,
; so every cell reads as one textured tile in its own two colours.
;
; The 1x1 grain matters — Multicolor mode cannot draw anything finer than a 4x4
; block, so resolving this texture at all confirms the VDP really is in Graphics
; Mode I and not falling back to Multicolor.
Checker:
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010
  .byte %01010101
  .byte %10101010

; 32 colour table entries — (foreground << 4) | background.
; Entry n colours characters (n * 8) through (n * 8 + 7).
Colors:
  .byte (TMS_WHITE     << 4) | TMS_BLACK        ; chars $00-$07
  .byte (TMS_BLACK     << 4) | TMS_WHITE        ; chars $08-$0F
  .byte (TMS_MED_GREEN << 4) | TMS_BLACK        ; chars $10-$17
  .byte (TMS_BLACK     << 4) | TMS_MED_GREEN    ; chars $18-$1F
  .byte (TMS_LT_GREEN  << 4) | TMS_DK_GREEN
  .byte (TMS_DK_GREEN  << 4) | TMS_LT_GREEN
  .byte (TMS_DK_BLUE   << 4) | TMS_LT_BLUE
  .byte (TMS_LT_BLUE   << 4) | TMS_DK_BLUE
  .byte (TMS_DK_RED    << 4) | TMS_LT_RED
  .byte (TMS_LT_RED    << 4) | TMS_DK_RED
  .byte (TMS_CYAN      << 4) | TMS_DK_BLUE
  .byte (TMS_DK_BLUE   << 4) | TMS_CYAN
  .byte (TMS_MED_RED   << 4) | TMS_LT_YELLOW
  .byte (TMS_LT_YELLOW << 4) | TMS_MED_RED
  .byte (TMS_DK_YELLOW << 4) | TMS_DK_GREEN
  .byte (TMS_DK_GREEN  << 4) | TMS_DK_YELLOW
  .byte (TMS_MAGENTA   << 4) | TMS_GRAY
  .byte (TMS_GRAY      << 4) | TMS_MAGENTA
  .byte (TMS_WHITE     << 4) | TMS_DK_BLUE
  .byte (TMS_DK_BLUE   << 4) | TMS_WHITE
  .byte (TMS_LT_GREEN  << 4) | TMS_BLACK
  .byte (TMS_BLACK     << 4) | TMS_LT_GREEN
  .byte (TMS_CYAN      << 4) | TMS_MAGENTA
  .byte (TMS_MAGENTA   << 4) | TMS_CYAN
  .byte (TMS_LT_YELLOW << 4) | TMS_DK_RED
  .byte (TMS_DK_RED    << 4) | TMS_LT_YELLOW
  .byte (TMS_GRAY      << 4) | TMS_BLACK
  .byte (TMS_BLACK     << 4) | TMS_GRAY
  .byte (TMS_LT_RED    << 4) | TMS_DK_GREEN
  .byte (TMS_DK_GREEN  << 4) | TMS_LT_RED
  .byte (TMS_WHITE     << 4) | TMS_MED_RED
  .byte (TMS_MED_RED   << 4) | TMS_WHITE        ; chars $F8-$FF

NoVideoMsg: .asciiz "No video card present."

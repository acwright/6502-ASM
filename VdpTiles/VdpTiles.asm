.setcpu "65C02"

; VDP only: this program drives the 6502-PICOVDP's registers directly, so it
; has no TMS9918A build.  6502-VDP.inc is the include for an ACE with a
; 6502-PICOVDP running BIOS 2.x.
.include "../6502-VDP.inc"

.segment "CODE"

; =============================================================================
;   VdpTiles — scrolling 4bpp tiles on the 6502-PICOVDP
; =============================================================================
;   A tour of what the PICOVDP adds to the TMS9918A, in one screen:
;
;     - VMODE picks the Graphics geometry: 32×30 cells of 8×8, 256×240
;     - L0CTRL gives layer 0 four bits per pixel and an attribute byte per cell
;     - The attribute byte picks one of the default palette's sixteen rows
;     - L0SCRX and L0SCRY scroll the whole layer, a pixel a frame
;     - One palette entry is rewritten in VRAM, and the screen follows at once
;
;   Every register write is spelled out with the include's VC_* names, so the
;   program reads as a worked example of SPEC §7-§13.
;
;   LOAD and RUN it from BASIC; press any key to return to BASIC.
;
;   VRAM, as SPEC §7 recommends for graphics:
;
;     $0000-$03BF   Layer 0 name table        960 B   L0NAME = $00
;     $0400-$07BF   Layer 0 attribute table   960 B   L0ATTR = $01
;     $4000-$407F   Layer 0 patterns (4 × 32)         L0PAT  = $08
;     $FC00-$FDFF   Palette                           VC_PALETTE
;
;   A VRAM address above $3FFF needs VBANK: the command protocol carries only
;   address bits 13:0, and bits 15:14 come from VBANK.  The BIOS 1.x Kernal
;   never writes VBANK, so this program puts it back to 0 after every address
;   above $3FFF — otherwise the key echo below would land in the palette.
; =============================================================================

; =============================================================================
;   BASIC Startup Stub
; =============================================================================
;   A tokenized BASIC line: 10 SYS 2060
;   When this program is loaded into $0800 and RUN in BASIC, the SYS command
;   jumps to the machine code entry point at $080C (decimal 2060).
;   This stub must remain at the very start of the program.

BasicStartup: .byte $0A, $08, $0A, $00, $A5, $32, $30, $36, $30, $00, $00, $00

; =============================================================================
;   Constants
; =============================================================================

COLS            = 32                    ; Graphics mode: 32×30 cells
ROWS            = 30
MAP_HEIGHT      = ROWS * 8              ; L0SCRY wraps at 240 pixels (SPEC §13)

NAME_TABLE      = $0000                 ; L0NAME = $00 (× $400)
ATTR_TABLE      = $0400                 ; L0ATTR = $01 (× $400)
PATTERN_TABLE   = $4000                 ; L0PAT  = $08 (× $800)

TILE_BYTES      = 32                    ; 4bpp: 8 rows of 4 bytes
TILE_COUNT      = 4

GREY_ROW        = 1                     ; Palette row 1: the grayscale ramp
FIRST_HUE_ROW   = 2                     ; Rows 2-13: twelve hues (SPEC §11)
HUE_ROWS        = 12

; Tile 3 draws its diamond in colour 15 of the grayscale row.  That one entry,
; palette index $1F, is the one the main loop cycles.
CYCLE_ENTRY     = VC_PALETTE + (GREY_ROW * 16 + 15) * 2

; =============================================================================
;   Start — Program entry point ($080C)
; =============================================================================

Start:
  jsr KernalVersion             ; A = major, X = minor
  cmp #2
  bcs @HaveBios2
  lda #<GuardMsg                ; Anything older has no PICOVDP support —
  ldy #>GuardMsg                ;   say so and go back to BASIC
  jsr PrintStr
  rts
@HaveBios2:

; -----------------------------------------------------------------------------
;   Set up layer 0 with the display off, so nothing half-built is ever shown
; -----------------------------------------------------------------------------

  lda #$00                      ; MODE1 without VC_MODE1_DISP: display off
  ldx #VC_REG_MODE1             ;   (M1 and M2 clear too; VMODE decides the mode)
  jsr SetReg

  lda #VC_VMODE_GRAPHICS        ; 32×30 cells of 8×8, 256×240
  ldx #VC_REG_VMODE
  jsr SetReg

  lda #(VC_LCTRL_4BPP | VC_LCTRL_ATTR_CELL | VC_LCTRL_ENABLE | VC_LCTRL_OPAQUE)
  ldx #VC_REG_L0CTRL            ; 4bpp, an attribute byte per cell, on, opaque
  jsr SetReg

  lda #(NAME_TABLE >> 10)       ; Table bases in 1 KB steps ...
  ldx #VC_REG_L0NAME
  jsr SetReg
  lda #(ATTR_TABLE >> 10)
  ldx #VC_REG_L0ATTR
  jsr SetReg
  lda #(PATTERN_TABLE >> 11)    ; ... and the pattern table in 2 KB steps
  ldx #VC_REG_L0PAT
  jsr SetReg

  lda #$00
  ldx #VC_REG_L0PAL             ; Attribute sub-palettes index rows 0-15
  jsr SetReg
  lda #$00
  ldx #VC_REG_L0SCRX            ; Start unscrolled
  jsr SetReg
  lda #$00
  ldx #VC_REG_L0SCRY
  jsr SetReg

  lda #$00                      ; Sprites off: without VC_SPRCTRL_ENABLE no
  ldx #VC_REG_SPRCTRL           ;   sprite is evaluated or drawn
  jsr SetReg

  lda #TMS_BLACK                ; Low nibble: the backdrop, palette row 0.  In
  ldx #VC_REG_COLOR             ;   Graphics mode it shows as the side borders
  jsr SetReg

; -----------------------------------------------------------------------------
;   Upload the four tiles
; -----------------------------------------------------------------------------

  lda #<PATTERN_TABLE
  ldx #>PATTERN_TABLE
  jsr SetWriteAddr              ; VBANK = 1 for $4000
  ldx #$00
@Tiles:
  lda Tiles,x
  sta VC_DATA                   ; The pointer advances by VINC (+1)
  inx
  cpx #(TILE_BYTES * TILE_COUNT)
  bne @Tiles
  jsr ClearVBank

; -----------------------------------------------------------------------------
;   Fill the name table: tiles 0-3 in a 2×2 repeat
; -----------------------------------------------------------------------------
;   Cell (col, row) shows tile (col & 1) + 2 × (row & 1).  32 and 30 are both
;   even, so the pattern wraps seamlessly when the layer scrolls.

  lda #<NAME_TABLE
  ldx #>NAME_TABLE
  jsr SetWriteAddr
  ldy #$00                      ; Y = row
@NameRow:
  ldx #$00                      ; X = column
@NameCell:
  tya
  and #$01
  asl a
  sta Temp                      ; 2 × (row & 1)
  txa
  and #$01
  ora Temp                      ; + (col & 1)
  sta VC_DATA
  inx
  cpx #COLS
  bne @NameCell
  iny
  cpy #ROWS
  bne @NameRow

; -----------------------------------------------------------------------------
;   Fill the attribute table: a sub-palette for every cell
; -----------------------------------------------------------------------------
;   Tile 3 takes the grayscale row, where its diamond is the cycling colour.
;   Every other cell takes a hue row, stepping by one every two cells across
;   and every two cells down, so the hues run in diagonal bands.  The flip,
;   priority and ninth-bit fields (VC_ATTR_*) stay 0.

  lda #<ATTR_TABLE
  ldx #>ATTR_TABLE
  jsr SetWriteAddr
  ldy #$00                      ; Y = row
@AttrRow:
  ldx #$00                      ; X = column
@AttrCell:
  txa
  and #$01
  beq @AttrHue
  tya
  and #$01
  beq @AttrHue
  lda #GREY_ROW                 ; Tile 3
  bra @AttrStore
@AttrHue:
  txa
  lsr a
  sta Temp                      ; col / 2 (0-15)
  tya
  lsr a                         ; row / 2 (0-14)
  clc
  adc Temp                      ; 0-29
@AttrMod:
  cmp #HUE_ROWS                 ; mod 12
  bcc @AttrHueRow
  sbc #HUE_ROWS                 ; C is set here
  bra @AttrMod
@AttrHueRow:
  adc #FIRST_HUE_ROW            ; C is clear here
@AttrStore:
  and #VC_ATTR_SUBPAL
  sta VC_DATA
  inx
  cpx #COLS
  bne @AttrCell
  iny
  cpy #ROWS
  bne @AttrRow

; -----------------------------------------------------------------------------
;   Display on, and run a frame at a time until a key is pressed
; -----------------------------------------------------------------------------

  stz ScrollX
  stz ScrollY
  stz FrameCount
  stz HueIndex

  lda #VC_MODE1_DISP
  ldx #VC_REG_MODE1
  jsr SetReg

  lda VC_STATUS                 ; Clear a stale end-of-frame flag
@Frame:
  lda VC_STATUS                 ; STATSEL_A is 0, so port A reads STAT0.  The
  and #VC_STAT0_F               ;   read clears F, which is set again when the
  beq @Frame                    ;   next picture ends

  inc ScrollX                   ; Graphics mode's map is 256 pixels wide, so
  lda ScrollX                   ;   the byte wraps exactly where the map does
  ldx #VC_REG_L0SCRX            ; Increasing SCRX moves the picture left
  jsr SetReg

  inc ScrollY                   ; ... but only 240 high, so wrap by hand
  lda ScrollY
  cmp #MAP_HEIGHT
  bcc @SetScrollY
  lda #$00
  sta ScrollY
@SetScrollY:
  ldx #VC_REG_L0SCRY            ; Increasing SCRY moves the picture up
  jsr SetReg

  inc FrameCount
  lda FrameCount
  and #$07                      ; Every eighth frame, the next hue
  bne @CheckKey
  jsr CycleColour

@CheckKey:
  jsr Chrin                     ; C = 1 if a key is waiting
  bcc @Frame

; -----------------------------------------------------------------------------
;   Put the card back the way the text console expects it, and return
; -----------------------------------------------------------------------------

  lda #VC_VMODE_LEGACY          ; M1/M2/M3 choose the mode again, and
  ldx #VC_REG_VMODE             ;   InitVideo selects Text through M1
  jsr SetReg
  lda #$00                      ; The scroll registers apply in the legacy
  ldx #VC_REG_L0SCRX            ;   submode too, and InitVideo doesn't
  jsr SetReg                    ;   write them
  lda #$00
  ldx #VC_REG_L0SCRY
  jsr SetReg
  lda #(VC_LCTRL_ATTR_NONE | VC_LCTRL_ENABLE | VC_LCTRL_OPAQUE)
  ldx #VC_REG_L0CTRL            ; L0CTRL's reset value, $3C
  jsr SetReg
  lda #(VC_SPRCTRL_ENABLE | VC_SPRCTRL_COLLIDE | VC_SPRCTRL_TERM | VC_SPRCTRL_4BPP)
  ldx #VC_REG_SPRCTRL           ; SPRCTRL's reset value, $27
  jsr SetReg

  lda #<CYCLE_ENTRY             ; The grayscale ramp's white, back as it was
  ldx #>CYCLE_ENTRY
  jsr SetWriteAddr
  lda #$0F                      ; %0000RRRR
  sta VC_DATA
  lda #$FF                      ; %GGGGBBBB
  sta VC_DATA
  jsr ClearVBank

  jsr InitVideo                 ; Text registers and the character set
  jsr VideoClear                ; The name table still holds tile numbers
  rts                           ; Back to BASIC

; =============================================================================
;   CycleColour — write the next hue into palette entry CYCLE_ENTRY
; =============================================================================
;   The PICOVDP watches VRAM writes to the palette window, so the new colour
;   is on screen from the next line drawn.  No reload, no dirty flag.
;   Modifies: A, X

CycleColour:
  lda HueIndex
  inc a
  cmp #HUE_ROWS
  bcc @Store
  lda #$00
@Store:
  sta HueIndex

  lda #<CYCLE_ENTRY
  ldx #>CYCLE_ENTRY
  jsr SetWriteAddr              ; VBANK = 3 for $FC3E

  lda HueIndex
  asl a
  tax                           ; X = offset of the 2-byte entry
  lda Hues,x
  sta VC_DATA                   ; %0000RRRR
  lda Hues+1,x
  sta VC_DATA                   ; %GGGGBBBB
  ; Fall through

; =============================================================================
;   ClearVBank — back to VRAM bank 0, where the BIOS 1.x Kernal expects it
; =============================================================================
;   Modifies: A, X

ClearVBank:
  lda #$00
  ldx #VC_REG_VBANK
  ; Fall through

; =============================================================================
;   SetReg — write a PICOVDP register through port A
; =============================================================================
;   In: A = value, X = register number (VC_REG_*)
;   Modifies: A

SetReg:
  sta VC_REG                    ; Payload first ...
  txa
  ora #VC_REG_WRITE             ; ... then %1rrrrrrr
  sta VC_REG
  rts

; =============================================================================
;   SetWriteAddr — point port A at a 16-bit VRAM address, for writing
; =============================================================================
;   Writes VBANK with address bits 15:14, then sends the address command, which
;   samples it.  Leaves VBANK set; ClearVBank puts it back.
;   In: A = address low, X = address high
;   Modifies: A, X

SetWriteAddr:
  pha                           ; Save the low byte
  phx                           ; Save the high byte
  txa
  lsr a                         ; Bits 15:14 down to 1:0
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  ldx #VC_REG_VBANK
  jsr SetReg
  pla                           ; High byte
  and #$3F                      ; Bits 13:8
  ora #VC_ADDR_WRITE            ; %01aaaaaa
  tax
  pla                           ; Low byte
  sta VC_REG                    ; Payload: address bits 7:0
  stx VC_REG                    ; Command
  rts

; =============================================================================
;   Data
; =============================================================================

GuardMsg:
  .byte "NEEDS BIOS 2 AND A 6502-PICOVDP", CHAR_CR, CHAR_LF, $00

; The pure hue of each row 2-13 (index 7 of each ramp, SPEC §11), as palette
; entries: %0000RRRR, %GGGGBBBB.
Hues:
  .byte $0F, $00                ; Red
  .byte $0F, $80                ; Orange
  .byte $0F, $F0                ; Yellow
  .byte $08, $F0                ; Chartreuse
  .byte $00, $F0                ; Green
  .byte $00, $F8                ; Spring green
  .byte $00, $FF                ; Cyan
  .byte $00, $8F                ; Azure
  .byte $00, $0F                ; Blue
  .byte $08, $0F                ; Violet
  .byte $0F, $0F                ; Magenta
  .byte $0F, $08                ; Rose

; Four 4bpp tiles, 32 bytes each: eight rows from the top, two pixels a byte,
; the high nibble leftmost (SPEC §8).  Each nibble is a colour within the
; cell's sub-palette row.
Tiles:
; Tile 0 — a bevelled block: light top and left edges, dark bottom and right
  .byte $DD, $DD, $DD, $DB      ; DDDDDDDB
  .byte $DB, $99, $99, $73      ; DB999973
  .byte $D9, $77, $77, $53      ; D9777753
  .byte $D9, $77, $77, $53      ; D9777753
  .byte $D9, $77, $77, $53      ; D9777753
  .byte $D9, $77, $77, $53      ; D9777753
  .byte $D7, $55, $55, $53      ; D7555553
  .byte $B3, $33, $33, $31      ; B3333331

; Tile 1 — diagonal stripes, seamless when tiled
  .byte $99, $94, $44, $44      ; 99944444
  .byte $49, $99, $44, $44      ; 49994444
  .byte $44, $99, $94, $44      ; 44999444
  .byte $44, $49, $99, $44      ; 44499944
  .byte $44, $44, $99, $94      ; 44449994
  .byte $44, $44, $49, $99      ; 44444999
  .byte $94, $44, $44, $99      ; 94444499
  .byte $99, $44, $44, $49      ; 99444449

; Tile 2 — a 2×2 checker
  .byte $66, $BB, $66, $BB      ; 66BB66BB
  .byte $66, $BB, $66, $BB      ; 66BB66BB
  .byte $BB, $66, $BB, $66      ; BB66BB66
  .byte $BB, $66, $BB, $66      ; BB66BB66
  .byte $66, $BB, $66, $BB      ; 66BB66BB
  .byte $66, $BB, $66, $BB      ; 66BB66BB
  .byte $BB, $66, $BB, $66      ; BB66BB66
  .byte $BB, $66, $BB, $66      ; BB66BB66

; Tile 3 — a diamond in colour 15, the entry the main loop cycles
  .byte $33, $33, $33, $33      ; 33333333
  .byte $33, $3F, $F3, $33      ; 333FF333
  .byte $33, $FF, $FF, $33      ; 33FFFF33
  .byte $3F, $FF, $FF, $F3      ; 3FFFFFF3
  .byte $3F, $FF, $FF, $F3      ; 3FFFFFF3
  .byte $33, $FF, $FF, $33      ; 33FFFF33
  .byte $33, $3F, $F3, $33      ; 333FF333
  .byte $33, $33, $33, $33      ; 33333333

; Working storage (the .prg is loaded into RAM, so it can live here)
ScrollX:    .byte $00
ScrollY:    .byte $00
FrameCount: .byte $00
HueIndex:   .byte $00
Temp:       .byte $00

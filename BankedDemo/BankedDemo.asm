.setcpu "65C02"

; make VDP=1 builds for an ACE with a 6502-PICOVDP on BIOS 2.x;
; the default builds for the TMS9918A on BIOS 1.x.
.ifdef VDP
.include "../6502-VDP.inc"
.else
.include "../6502.inc"
.endif

.ifndef FLASH
.error "BankedDemo is a Flash Cart only — build it with make FLASH=512K"
.endif

; =============================================================================
;   BankedDemo — eight pictures that do not fit in a cartridge
; =============================================================================
;   A gallery. Eight full-screen Graphics I pictures, one per bank, cycled with
;   a key or a joystick. It is banked because it has to be: a picture is 2,848
;   bytes, eight of them is 22,784, and a fixed cartridge has 16,378. There is
;   no `make` with no FLASH= here, because there is nothing for it to build.
;
;   THE SHAPE OF IT
;   ---------------
;   All the code is in FIXED, $E000-$FFF9, the 8 KB that is always visible.
;   All the data is in BANK00-BANK07, the 8 KB window at $C000-$DFFF, one
;   picture each. The code selects a bank and then reads $C000 as ordinary
;   memory — because that is all a selected bank is.
;
;   Every bank has the same layout, so ShowPicture reads one set of addresses
;   and works on any of them:
;
;     $C000  PIC_PATTERNS  2,048   256 patterns of 8 rows, msb leftmost
;     $C800  PIC_COLORS       32   ink << 4 | paper, one per 8 patterns
;     $C820  PIC_NAMES       768   32 x 24 cells, each naming a pattern
;
;   That uses 2,848 bytes of an 8,192-byte bank and leaves the rest $FF. A bank
;   is 8 KB whether you fill it or not.
;
;   THE PICTURES ARE GENERATED
;   --------------------------
;   Gallery.inc is written by tools/make-gallery.mjs — `make gallery` — and
;   `make check-gallery` fails on a stale copy. Graphics I gives 256 patterns
;   for 768 cells, so a picture is a mosaic and these are geometric on purpose.
;
;   WHAT TO READ IT FOR
;   -------------------
;   SetBank, and the rule that you call it from FIXED and never from inside a
;   bank. The zero-page shadow, and why it is written before the register. The
;   fact that a VDP upload out of the window is an ordinary `lda (ptr),y` and
;   nothing else. 6502-CRT's Cart.asm is the fully commented template; the
;   6502-DOCS chapter *Bigger cartridges* is the explanation.
;
;   NEEDS 6502-EMULATOR 3.4.0 OR LATER. On 3.3.0 the cartridge is dropped
;   without a word and the machine boots to BASIC instead — Cart.load() takes
;   32,768 bytes and nothing else, and says nothing about the other sizes.
; =============================================================================

; =============================================================================
;   The bank register and its shadow
; =============================================================================
;   Write-only, 8 bits, at ANY address in $E000-$FFFF; this one by convention.
;   A write latches it and reaches no flash — WEB is not asserted there — so
;   writing the register is never also a flash write. RESB clears it to 0.
;
;   It cannot be read back, so the shadow in the zero page is the only record
;   of which bank is selected. $3A is the first byte 6502.inc marks free for a
;   program that has taken the machine over, and a cartridge is such a program.
; =============================================================================

BANK      = $E000
BANKSHDW  = $3A

; The rest of this program's zero page, taken from the same free region.
SRC       = $3B                 ; 2 bytes — source pointer for CopyToVram
COUNT     = $3D                 ; 2 bytes — bytes left to copy
PICTURE   = $3F                 ; 1 byte  — which picture is on screen, 0-7

; The window, and the one layout every bank shares.
PIC_PATTERNS = $C000
PIC_COLORS   = $C800
PIC_NAMES    = $C820

PICTURE_COUNT = 8

; =============================================================================
;   Graphics I, and where its tables live in VRAM
; =============================================================================
;   The values below are what go in registers 2-6: each is the table's VRAM
;   address divided by the granularity that register has. Registers 0-7 mean
;   the same thing on the TMS9918A and on the 6502-PICOVDP, which is why this
;   program has one body and two includes.
; =============================================================================

VRAM_PATTERNS = $0000           ; R4 = $00  (x $800)
VRAM_NAMES    = $1800           ; R2 = $06  (x $400)
VRAM_SPRATTR  = $1B00           ; R5 = $36  (x $80)
VRAM_COLORS   = $2000           ; R3 = $80  (x $40)
VRAM_SPRPAT   = $3800           ; R6 = $07  (x $800)

.segment "FIXED"

; =============================================================================
;   SetBank — select which 8 KB bank appears at $C000-$DFFF
; =============================================================================
;   A = the bank value. Preserves X and Y.
;
;   Must live in FIXED, and must be CALLED from FIXED. `jsr SetBank` from code
;   at $C000-$DFFF returns to an address that no longer holds the calling code;
;   the machine does not fault, it executes whatever the new bank has there.
;
;   The shadow is written FIRST. If an interrupt lands between the two stores,
;   the handler sees a shadow one instruction ahead of the hardware rather than
;   one behind, and restoring the hardware from the shadow on the way out puts
;   the two back in agreement. The other order leaves them permanently
;   disagreed.
; =============================================================================

SetBank:
  sta BANKSHDW                  ; shadow first — see above
  sta BANK                      ; latch the register
  rts

; =============================================================================
;   CartReset — the cartridge entry point
; =============================================================================

CartReset:
  ldx #$ff
  txs                           ; Reset the stack pointer — nothing did it for us

  ; RESB clears the bank register to 0 — its /MR is on the reset line — so the
  ; shadow starts honest rather than only becoming so at the first SetBank.
  stz BANKSHDW

  jsr KernalInit                ; Probe and initialize every card (leaves IRQs off)

.ifdef VDP
  ; --- VDP build only: refuse to run on BIOS 1.x ---
  ; Built with 6502-VDP.inc, this cartridge calls 2.x Kernal entries that are
  ; bare RTS slots on 1.x. Say so and stop rather than run into them.
  jsr KernalVersion             ; A = major, X = minor
  cmp #2
  bcs @Bios2
  lda #<NeedsBios2Msg
  ldy #>NeedsBios2Msg
  jsr PrintStr
@Halt:
  bra @Halt                     ; A cartridge has nowhere to return to
@Bios2:
.endif

  cli                           ; Interrupts on, now the vectors are live.
                                ;   The keyboard and serial handlers fill the
                                ;   input ring buffer from here on, which is
                                ;   what BufferSize below reads.

  ; The console is about to be a picture rather than a screen of text, so stop
  ; the Kernal writing to the video card behind us. Input is unaffected: the
  ; keyboard reaches the ring buffer through the VIA's interrupt whatever
  ; IO_MODE says.
  lda #$01                      ; bit 0 set: console output goes to serial
  jsr SetIOMode

  jsr SetGraphicsMode

  stz PICTURE
  lda PICTURE
  jsr ShowPicture

; =============================================================================
;   The main loop — a key or a joystick moves along the gallery
; =============================================================================
;   `,` steps back and anything else steps forward; on a machine with a GPIO
;   card, so do left and right on joystick 1.
; =============================================================================

MainLoop:
  jsr BufferSize                ; A = unread bytes in the input buffer
  beq @Stick
  jsr ReadBuffer                ; A = the byte. NOT Chrin, which echoes it —
                                ;   and an echo into a screen of picture would
                                ;   redraw a cell of it as a letter.
  cmp #','
  beq @Prev
  bra @Next

@Stick:
  lda HW_PRESENT
  and #HW_GPIO
  beq MainLoop                  ; No GPIO card: the keyboard is the whole of it
  jsr ReadJoystick1             ; Active low — a held direction is a 0 bit
  tax
  and #%01000000                ; Bit 6: left
  beq @StickPrev
  txa
  and #%10000000                ; Bit 7: right
  beq @StickNext
  bra MainLoop

@StickNext:
  jsr WaitStickCentre
@Next:
  lda PICTURE
  inc a
  cmp #PICTURE_COUNT
  bcc @Show
  lda #$00
  bra @Show

@StickPrev:
  jsr WaitStickCentre
@Prev:
  lda PICTURE
  bne @Down
  lda #PICTURE_COUNT
@Down:
  dec a

@Show:
  sta PICTURE
  jsr ShowPicture
  bra MainLoop

; =============================================================================
;   WaitStickCentre — hold until joystick 1 is released
; =============================================================================
;   Without this one flick of the stick steps through the whole gallery in a
;   couple of frames. The keyboard needs no equivalent: the ring buffer already
;   gives one event per press.
; =============================================================================

WaitStickCentre:
  jsr ReadJoystick1
  cmp #$FF                      ; every line released
  bne WaitStickCentre
  rts

; =============================================================================
;   ShowPicture — put picture A on the screen
; =============================================================================
;   A = 0-7, which is BOTH the picture and the bank it lives in: the segment
;   name in Gallery.inc is the value written to the register. `.segment
;   "BANK03"` is reached with `lda #$03`.
;
;   Everything after the jsr SetBank is an ordinary read of ordinary memory.
;   That is the whole idea: once a bank is selected it is not special, and
;   CopyToVram has no notion that it is reading out of a window.
;
;   This routine is in FIXED and stays there. If it lived in a bank, SetBank's
;   rts would return into whatever the newly selected bank holds at that
;   address.
; =============================================================================

ShowPicture:
  jsr SetBank                   ; the picture is now at $C000-$DFFF

  ; The backdrop and the text colour come out of the picture's own colour
  ; table — another read straight out of the window.
  lda PIC_COLORS                ; ink << 4 | paper, the same in all 32 bytes
  ldx #7                        ; R7: text colour and backdrop
  jsr VdpSetReg

  ; Patterns: 2,048 bytes to VRAM $0000
  lda #<PIC_PATTERNS
  ldy #>PIC_PATTERNS
  jsr SetSource
  lda #<$0800
  ldy #>$0800
  jsr SetCount
  lda #<VRAM_PATTERNS
  ldy #>VRAM_PATTERNS
  jsr SetVramWrite
  jsr CopyToVram

  ; Colours: 32 bytes to VRAM $2000
  lda #<PIC_COLORS
  ldy #>PIC_COLORS
  jsr SetSource
  lda #<$0020
  ldy #>$0020
  jsr SetCount
  lda #<VRAM_COLORS
  ldy #>VRAM_COLORS
  jsr SetVramWrite
  jsr CopyToVram

  ; Names: 768 bytes to VRAM $1800
  lda #<PIC_NAMES
  ldy #>PIC_NAMES
  jsr SetSource
  lda #<$0300
  ldy #>$0300
  jsr SetCount
  lda #<VRAM_NAMES
  ldy #>VRAM_NAMES
  jsr SetVramWrite
  jsr CopyToVram

  rts

; =============================================================================
;   SetGraphicsMode — registers 0-7 for Graphics I
; =============================================================================
;   Called once. R7 is set per picture by ShowPicture, so it is left alone
;   here. The sprite tables are pointed somewhere harmless and the sprite
;   attribute list is terminated, because a Graphics I screen with nothing said
;   about sprites shows whatever VRAM happened to hold.
; =============================================================================

SetGraphicsMode:
  lda #$00                      ; R0: no external video, M3 = 0
  ldx #0
  jsr VdpSetReg
  lda #$C0                      ; R1: 16K, display on, no interrupt,
  ldx #1                        ;     M1 = M2 = 0 — Graphics I
  jsr VdpSetReg
  lda #(VRAM_NAMES >> 10)       ; R2: name table / $400
  ldx #2
  jsr VdpSetReg
  lda #(VRAM_COLORS >> 6)       ; R3: colour table / $40
  ldx #3
  jsr VdpSetReg
  lda #(VRAM_PATTERNS >> 11)    ; R4: pattern table / $800
  ldx #4
  jsr VdpSetReg
  lda #(VRAM_SPRATTR >> 7)      ; R5: sprite attributes / $80
  ldx #5
  jsr VdpSetReg
  lda #(VRAM_SPRPAT >> 11)      ; R6: sprite patterns / $800
  ldx #6
  jsr VdpSetReg

  ; $D0 in a sprite's Y byte ends the list. One is enough: no sprite after it
  ; is drawn, whatever the rest of VRAM holds.
  lda #<VRAM_SPRATTR
  ldy #>VRAM_SPRATTR
  jsr SetVramWrite
  lda #$D0
  sta VC_DATA
  rts

; =============================================================================
;   The four VDP primitives
; =============================================================================
;   A register write is the value then $80 | the register number, both to the
;   command port. A VRAM write address is the low byte then $40 | the high six
;   bits, and every byte written to the data port after that lands at the next
;   address.
;
;   The TMS9918A wants 8 us between accesses at 1 MHz. CopyToVram's loop is
;   eleven cycles, so it is inside that without a delay; a faster CPU would
;   need one.
; =============================================================================

VdpSetReg:                      ; A = value, X = register 0-7
  sta VC_REG
  txa
  ora #$80
  sta VC_REG
  rts

SetVramWrite:                   ; A = address low, Y = address high
  sta VC_REG
  tya
  and #$3F                      ; VRAM addresses are 14 bits
  ora #$40                      ; bit 6 set: the writes that follow are data
  sta VC_REG
  rts

SetSource:                      ; A = low, Y = high
  sta SRC
  sty SRC+1
  rts

SetCount:                       ; A = low, Y = high
  sta COUNT
  sty COUNT+1
  rts

; COUNT bytes from (SRC) to the data port. COUNT must not be zero.
CopyToVram:
  ldy #$00
@Loop:
  lda (SRC),y
  sta VC_DATA
  iny
  bne @NoCarry
  inc SRC+1                     ; Y wrapped: step the pointer a page on
@NoCarry:
  lda COUNT                     ; 16-bit decrement
  bne @NoBorrow
  dec COUNT+1
@NoBorrow:
  dec COUNT
  lda COUNT
  ora COUNT+1
  bne @Loop
  rts

.ifdef VDP
NeedsBios2Msg:
  .byte "NEEDS BIOS 2 AND A 6502-PICOVDP", CHAR_CR, CHAR_LF, $00
.endif

; =============================================================================
;   Interrupt trampolines
; =============================================================================
;   KernalInit has already pointed the RAM vectors at the default handlers, so
;   bouncing through them keeps keyboard and serial input working without
;   writing a handler.
;
;   Both live in FIXED, which is the rule for any handler on a banked cart: a
;   handler in a bank is reachable only while that bank happens to be selected.
;   These two touch no banked data, so they need no bank save and restore
;   either — a handler that DID would read BANKSHDW, select its own bank, and
;   put the old one back through SetBank before returning.
; =============================================================================

IrqTrampoline:
  jmp (IRQ_PTR)                 ; Dispatch through the RAM IRQ vector

NmiTrampoline:
  jmp (NMI_PTR)                 ; Dispatch through the RAM NMI vector

; =============================================================================
;   The pictures — BANK00 through BANK07
; =============================================================================

.include "Gallery.inc"

; =============================================================================
;   CPU vectors — the cartridge owns $FFFA-$FFFF, and they are in FIXED
; =============================================================================
;   This is the reason the fixed region exists. A vector in a bank would point
;   at an address whose contents depend on the bank register, and the register
;   is cleared by the very reset that reads the vector.
; =============================================================================

.segment "VECTORS"

.word   NmiTrampoline           ; NMI
.word   CartReset               ; RESET — the cartridge entry point
.word   IrqTrampoline           ; IRQ

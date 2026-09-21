.setcpu "65C02"

; make VDP=1 builds for an ACE with a 6502-PICOVDP on BIOS 2.x;
; the default builds for the TMS9918A on BIOS 1.x.
.ifdef VDP
.include "../6502-VDP.inc"
.else
.include "../6502.inc"
.endif

; make FLASH=128K|256K|512K|1M builds the same program as a banked Flash Cart
; image instead of a 32K ROM cart. Nothing here uses a bank — this cartridge
; is 60-odd bytes and the point of it is the greeting — so the whole of the
; difference is which segment the code lands in:
;
;   CART    $C000-$FFF9, the fixed cartridge's one 16 KB block
;   FIXED   $E000-$FFF9, the half of a banked cart that never moves
;
; The banked window at $C000-$DFFF is simply unused, and the image is mostly
; $FF. See BankedDemo for a cartridge that is banked because it has to be, and
; 6502-CRT's Cart.asm for the fully commented template.
.ifdef FLASH
.segment "FIXED"
.else
.segment "CART"
.endif

; =============================================================================
;   Hello World Cart — the same greeting, burned into a cartridge
; =============================================================================
;   HelloWorld in this repository is a .prg: BASIC loads it into RAM and RUN
;   reaches it. This is the same program as a cartridge ROM, which is a
;   different thing entirely — it overlays $C000-$FFFF, replacing the Monitor,
;   BASIC, Wozmon and the CPU vectors, and the machine runs it from reset.
;
;   That difference is the point of having both here:
;
;     HelloWorld       .prg   loaded into RAM at $0800, started from BASIC
;     HelloWorldCart   .crt   ROM at $C000, started by the RESET vector
;
;   There is no loader and no BASIC underneath, so nothing has initialized the
;   hardware yet and there is nothing to return to. The program sets the
;   machine up itself and then loops forever.
;
;   The Kernal ($A000-$B7FF) and character set ($B800-$BFFF) are still there
;   underneath the cartridge window, so the whole jump table is available.
;
;   Built with 6502-16K.cfg, or with 6502-128K/256K/512K/1M.cfg under FLASH=.
;   See 6502-CRT for the fully commented template.
; =============================================================================

CartReset:
  ldx #$ff
  txs                           ; Reset the stack pointer — nothing did it for us
  jsr KernalInit                ; Probe and initialize every card (leaves IRQs off)

  cli                           ; Interrupts on, now the vectors are live

  jsr VideoClear                ; Safe with no video card fitted

  lda #<HelloMsg                ; A = string address low
  ldy #>HelloMsg                ; Y = string address high
  jsr PrintStr                  ; Kernal $A090

@Loop:
  bra @Loop                     ; A cartridge has nowhere to return to

; =============================================================================
;   Data
; =============================================================================

HelloMsg:
  .byte "Hello from Cartridge!", CHAR_CR, CHAR_LF, $00

; =============================================================================
;   Interrupt trampolines
; =============================================================================
;   The cartridge owns the hardware vectors at $FFFA, but KernalInit has
;   already pointed the RAM vectors at the default handlers. Bouncing through
;   them keeps keyboard and serial input working without writing a handler.

IrqTrampoline:
  jmp (IRQ_PTR)                 ; Dispatch through the RAM IRQ vector

NmiTrampoline:
  jmp (NMI_PTR)                 ; Dispatch through the RAM NMI vector

; =============================================================================
;   CPU vectors — the cartridge owns $FFFA-$FFFF
; =============================================================================

.segment "VECTORS"

.word   NmiTrampoline           ; NMI
.word   CartReset               ; RESET — the cartridge entry point
.word   IrqTrampoline           ; IRQ

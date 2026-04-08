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

BasicStartup: .byte $0A, $08, $0A, $00, $9E, $32, $30, $36, $30, $00, $00, $00

; =============================================================================
;   Start — Program entry point ($080C)
; =============================================================================
;   The system is already fully initialized when your program runs:
;     - Hardware probed and initialized (HW_PRESENT is set)
;     - Interrupts enabled, keyboard active
;     - IO_MODE set (video or serial console)
;     - All Kernal jump table routines available
;
;   Return to BASIC with RTS.
; =============================================================================

Start:
  lda #$0D            ; CR
  jsr Chrout          ; Write char to output device
  lda #$0A            ; LF
  jsr Chrout          ; Write char to output device

  ldx #0
Print:
  lda Message,x
  beq @PrintEnd
  jsr Chrout          ; Write char to output device
  inx
  jmp Print
@PrintEnd:
  lda #$0D            ; CR
  jsr Chrout          ; Write char to output device
  lda #$0A            ; LF
  jsr Chrout          ; Write char to output device

End:
  rts                 ; Return to BASIC

; =============================================================================
;   Data
; =============================================================================

Message: .asciiz "Hello, World!"

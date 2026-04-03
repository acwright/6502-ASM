.setcpu "65C02"

.include "../6502.inc"

.segment "CODE"     

BasicStartup: .byte $0A, $08, $0A, $00, $9E, $32, $30, $36, $30, $00, $00, $00    ; BASIC = 10 SYS 2060 

Start:                ; $080C
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

Message: .asciiz "Hello, World!"

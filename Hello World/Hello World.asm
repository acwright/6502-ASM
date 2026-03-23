.setcpu "65C02"

.include "../6502.inc"

.segment "CODE"

CHROUT := $0000       ; TODO: This needs to be updated with actual CHROUT location!

Start:
  lda #$0D            ; Carriage Return
  jsr CHROUT          ; Write char to output device
  lda #$0A            ; Line feed
  jsr CHROUT          ; Write char to output device

  ldx #0
Print:
  lda message,x
  beq @PrintEnd
  jsr CHROUT          ; Write char to output device
  inx
  jmp Print
@PrintEnd:
  lda #$0D            ; Carriage Return
  jsr CHROUT          ; Write char to output device
  lda #$0A            ; Line feed
  jsr CHROUT          ; Write char to output device

Break:
  brk                 ; Break back to monitor

message: .asciiz "Hello, World!"

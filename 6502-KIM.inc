; =============================================================================
;   6502-KIM.inc — the AC6502 KIM, by name
; =============================================================================
;
;   CPU:       WDC 65C02S at 1 MHz
;   ROM:       AC6502 BIOS v1.5, with the Keypad Card overlaying the top
;   Assembler: ca65 (cc65 toolchain) — := for an address, = for a value
;
;   Every address on this machine that has a name, and nothing else.  If a
;   name is in here, you can use it; if it is not, this machine does not have
;   the hardware.  That is the whole contract.
;
;   Include it from a program's source with:
;
;       .include "../6502-KIM.inc"
;
;   THE KIM IS NOT A STOCK AC6502 MACHINE.  The Keypad Card is a cartridge
;   that overlays the top of the address space and is decoded before ROM, so
;   this machine boots into a hex monitor rather than BASIC, and several
;   things the rest of the family takes for granted are not true here.  The
;   family-wide file — 6502.inc, alongside this one — describes a fully
;   fitted machine with video, sound, storage and a VIA.  None of that is on
;   a KIM, and a few of its addresses mean something else here.  Use this
;   file for KIM programs, and 6502.inc for ACE programs and cartridges.
;
;   MEMORY MAP
;   ----------
;   $0000-$0039   Zero page — the Kernal's
;   $003A-$003F   Zero page — YOURS (6 bytes)
;   $0040-$0051   Zero page — the KC Monitor's (see SECTION 2)
;   $0052-$00FF   Zero page — YOURS (174 bytes)
;   $0100-$01FF   CPU stack
;   $0200-$027F   KC Monitor's Wozmon line buffer — LIVE, not spare RAM
;   $0280-$02FF   free (the upper half of the Kernal input ring, which is
;                 never fed on a KIM — see Chrin)
;   $0300-$03FF   Kernal variables (SECTION 3)
;   $0400-$04FF   KC Monitor's serial receive ring — LIVE, not spare RAM
;   $0500-$07FF   free on a KIM (the Kernal's FS sector buffer; no CF fitted)
;   $0800-$7FFF   PROGRAM RAM — everything you write loads at $0800
;   $9000-$93FF   io5 — Serial Card (R65C51 ACIA), optional
;   $9400-$97FF   io6 — Accessory bus: the eight LEDs
;   $A000-$A0FF   BIOS Kernal jump table (SECTION 4)
;   $A100-$B7FF   Kernal implementation
;   $B800-$BFFF   CP437 character set
;   $C000-$DFFF   PIA (65C21) — the keypad encoder and the LCD.  The KC
;                 Monitor owns it; a user program has no business here
;   $E000-$FFF9   Keypad Card ROM — the KC Monitor
;   $FFFA-$FFFF   CPU vectors — the Keypad Card's, and not writable
;
;   HOW A PROGRAM RUNS
;   ------------------
;   Key the load address on the keypad and press UP.  UP is a JSR, so a program
;   is a subroutine: end it in RTS and you land back in the live monitor.
;   ESC aborts a running program from anywhere.
;
;   FOUR THINGS THAT SURPRISE PEOPLE
;   --------------------------------
;   1. The LED latch is write-only.  You cannot read back what you wrote —
;      keep your own copy in zero page.  See LEDS.
;   2. Zero page is not all yours.  The KC Monitor is running underneath you
;      and keeps its state in the middle of it.  See SECTION 1.
;   3. Chrin never returns anything.  See SECTION 4.
;   4. The keypad's codes are not the key values.  See SECTION 2.
;
; =============================================================================


; =============================================================================
;   SECTION 1: ZERO PAGE
; =============================================================================
;   The KC Monitor is live underneath every program you run, and it keeps its
;   own state in zero page:
;
;       $40-$45   the keypad monitor — current address, mode, scratch, and
;                 the key mailbox below
;       $46-$51   the serial Wozmon parser and its receive ring indices
;
;   So what is actually free on a running KIM is $3A-$3F and $52-$FF.  Put a
;   variable at $40 and the monitor overwrites it between one frame and the
;   next, or your program breaks the keypad — usually both, usually
;   intermittently, which is the worst way to find out.

ZP_FREE_LO          = $3A                ; First free byte below the monitor's
ZP_FREE_LO_END      = $3F                ; Last one — 6 bytes in all
ZP_FREE_HI          = $52                ; First free byte above it
ZP_FREE_HI_END      = $FF                ; Last one — 174 bytes


; =============================================================================
;   SECTION 2: THE KEYPAD
; =============================================================================
;   Reading the keypad from a user program does NOT go through the Kernal.  The
;   Keypad Card's own interrupt handler, KeyIrq, drops each press into a
;   one-deep mailbox in zero page, and that mailbox is the interface:
;
;       lda KEY_READY          ; anything waiting?
;       beq @NoKey
;       lda KEY_CODE           ; take it...
;       stz KEY_READY          ; ...and empty the box
;
;   DRAIN IT EVERY FRAME, HIT OR MISS.  It is a latch, not a queue, and
;   nothing in it expires.  A press you ignore is still sitting there three
;   frames later, and it will be delivered at the worst possible moment.

KEY_CODE            := $44               ; Encoder code of the press waiting
KEY_READY           := $45               ; Non-zero when a press is waiting

;   THE CODES ARE NOT THE KEY VALUES.  They come off the MM74C922 encoder in
;   the order the switches are wired on the board, not in the order they are
;   printed on the keys.  0 is $0A, not $00; $00 is the LEFT arrow; and C
;   through F run backward.  Use these names and the problem disappears.
;
;   The authority is `6502-kim dbg key --list`, which prints the live keypad.
;
;       ESC  $10   INS  $11   PGUP $12   A    $13
;       UP   $14   DEL  $15   PGDN $16   B    $17
;       7    $07   8    $08   9    $09   C    $0F
;       4    $04   5    $05   6    $06   D    $0E
;       1    $01   2    $02   3    $03   E    $0D
;       LEFT $00   0    $0A   RGHT $0B   F    $0C

KEY_LEFT            = $00                ; ◄
KEY_1               = $01
KEY_2               = $02
KEY_3               = $03
KEY_4               = $04
KEY_5               = $05
KEY_6               = $06
KEY_7               = $07
KEY_8               = $08
KEY_9               = $09
KEY_0               = $0A                ; Not $00 — this is the one to watch for
KEY_RIGHT           = $0B                ; ►
KEY_F               = $0C                ; C-F run backward from here...
KEY_E               = $0D
KEY_D               = $0E
KEY_C               = $0F                ; ...to here
KEY_ESC             = $10                ; Aborts a running program
KEY_INS             = $11
KEY_PGUP            = $12
KEY_A               = $13
KEY_UP              = $14                ; Runs the program at the shown address
KEY_DEL             = $15
KEY_PGDN            = $16
KEY_B               = $17


; =============================================================================
;   SECTION 3: KERNAL VARIABLES ($0300-$03FF)
; =============================================================================

;   The interrupt vectors are in RAM, which is what makes them yours to
;   change.  $FFFE is the Keypad Card's and cannot be written; it holds
;   $E49C, and $E49C is one instruction — JMP ($0300).  So a handler goes in
;   IRQ_PTR, and three things follow from that jump being direct:
;
;     - NOTHING IS SAVED.  Your handler is entered with A, X and Y exactly as
;       the interrupted code left them.  Save what you touch.
;     - CHAIN, DO NOT REPLACE.  KeyIrq is what clears the PIA, delivers ESC,
;       and fills the key mailbox.  End your handler with JMP through the old
;       vector, not RTI, and hand the stack over exactly as it arrived.
;     - GIVE IT BACK.  ESC does not unhook IRQ_PTR for you.  Restore the old
;       vector before your RTS, or the next program loaded at $0800 becomes
;       this machine's interrupt handler.

IRQ_PTR             := $0300             ; 2 bytes — IRQ handler vector
BRK_PTR             := $0302             ; 2 bytes — BRK handler vector
NMI_PTR             := $0304             ; 2 bytes — NMI handler vector

;   What the boot probe actually found.  On a KIM with the Serial Card fitted
;   this reads $10, and on one without it reads $00.  It never reads anything
;   else, because the other seven cards cannot be present on this machine —
;   the Keypad Card is in the slot.  Test it before calling anything that
;   needs the serial port:
;
;       lda HW_PRESENT
;       and #HW_SC
;       beq @NoSerial

HW_PRESENT          := $030D             ; 1 byte — hardware present bitmask

HW_SC               = %00010000          ; Serial Card — the only bit a KIM sets
; The rest of the bitmask, so a $10 on screen is legible.  None of these can
; ever be set on a KIM:
HW_RAM_L            = %00000001          ; Banked RAM low
HW_RAM_H            = %00000010          ; Banked RAM high
HW_RTC              = %00000100          ; Real-time clock
HW_CF               = %00001000          ; CompactFlash storage
HW_GPIO             = %00100000          ; GPIO / VIA — NOT the accessory bus
HW_SID              = %01000000          ; Sound
HW_VID              = %10000000          ; Video


; =============================================================================
;   SECTION 4: KERNAL JUMP TABLE ($A000-$A0FF)
; =============================================================================
;   Stable 3-byte JMPs in ROM.  Call them with JSR.  A jump table exists so
;   that these addresses stay put across BIOS versions while the code behind
;   them moves — which is why you call $A000 and not wherever Chrout actually
;   lives this month.
;
;   These are the entries a KIM can use.  The full table has more, and every
;   one of them drives hardware this machine does not have; see SECTION 5.
;
;   WHAT A ROUTINE DOES TO YOUR REGISTERS IS PART OF THE CONTRACT.  Read the
;   "Modifies" line before you put a loop counter in X.

Chrout              := $A000             ; Output one character
                                         ;   In: A = character
                                         ;   Preserves: A, X, Y
                                         ;   Goes to the serial port.  There is
                                         ;   no video on a KIM, and the LCD is
                                         ;   the monitor's — so on a machine
                                         ;   with no Serial Card this does
                                         ;   nothing at all, quietly

Chrin               := $A003             ; Input one character — DOES NOT WORK
                                         ;   HERE.  It polls the Kernal's ring
                                         ;   buffer at $0200, and on a fitted
                                         ;   KIM nothing ever fills it: the
                                         ;   Keypad Card repoints IRQ_PTR at
                                         ;   its own KeyIrq, which never calls
                                         ;   WriteBuffer.  Returns C=0 for
                                         ;   ever.  Read the keypad through the
                                         ;   mailbox in SECTION 2 instead.
                                         ;   The characters you may see at
                                         ;   $0200 are the monitor's line
                                         ;   buffer, not this ring: Chrin is
                                         ;   decided by the indices at $00 and
                                         ;   $01, which stay zero

WriteBuffer         := $A006             ; Put a byte in the Kernal ring buffer
                                         ;   In: A = byte.  Modifies: X
                                         ;   The call KeyIrq does not make

SysDelay            := $A075             ; Wait, in centiseconds (10 ms units)
                                         ;   In: A = low byte, X = high byte
                                         ;   Modifies: A, X, Y — X AND Y COME
                                         ;   BACK ZEROED.  A counter kept in
                                         ;   either is a counter that never
                                         ;   counts down; keep it in zero page
                                         ;   On a KIM this is a software
                                         ;   counting loop (there is no VIA
                                         ;   timer), and it runs about 3% long:
                                         ;   10,296 cycles per centisecond
                                         ;   rather than 10,000

KernalVersion       := $A07B             ; Get the BIOS version
                                         ;   Out: A = major, X = minor

SerialChrout        := $A051             ; Straight to the serial port
                                         ;   In: A = character
                                         ;   Blocks until the transmitter is
                                         ;   empty.  Chrout is the one to use;
                                         ;   this is here for when you want to
                                         ;   bypass it

InitSC              := $A04E             ; Initialize the Serial Card
                                         ;   8-N-1, 19200 baud.  Modifies: A
                                         ;   The boot probe already did this

PrintStr            := $A090             ; Print a NUL-terminated string
                                         ;   In: A = address low, Y = high
                                         ;       (lda #<Msg / ldy #>Msg)
                                         ;   Modifies: A, Y — X is preserved

PrintCRLF           := $A093             ; Print CR then LF
                                         ;   Modifies: A

PrintDecU16         := $A096             ; Print a 16-bit value as decimal
                                         ;   In: A = value low, X = value high
                                         ;   No leading zeros
                                         ;   Modifies: A, X, Y


; =============================================================================
;   SECTION 5: HARDWARE
; =============================================================================

; --- The accessory bus (io6, $9400-$97FF) ---
;   Eight LEDs behind a 74HC373 latch.  A write ANYWHERE in the window
;   latches; the address below is simply the bottom of it.
;
;   IT IS WRITE-ONLY.  A 74HC373 has no read strobe, so reading it gives you
;   whatever the bus happens to be holding — not the byte you wrote.  Keep a
;   shadow copy in zero page and treat that as the truth:
;
;       lda Shadow
;       ora #%00000001
;       sta Shadow             ; the copy that is real...
;       sta LEDS               ; ...and the copy the eye can see
;
;   Note that this is NOT the family's GPIO window.  On a fully fitted
;   AC6502 machine $9400 is a 65C22 VIA; here it is a latch and eight lamps,
;   which is exactly why the BIOS probe correctly leaves HW_GPIO clear.

LEDS                := $9400             ; Write-only — eight LEDs

; --- Serial Card (io5, $9000-$9003, optional) ---
;   R65C51 ACIA.  Use Chrout and PrintStr rather than these; they are here
;   for the episode that looks underneath.

SC_DATA             := $9000             ; R/W — data register
SC_STATUS           := $9001             ; Read — status register
SC_RESET            := $9001             ; Write — programmatic reset
SC_CMD              := $9002             ; R/W — command register
SC_CTRL             := $9003             ; R/W — control register

SC_STATUS_TDRE      = %00010000          ; Transmitter empty — ready to send
SC_STATUS_RDRF      = %00001000          ; Receiver full — a byte is waiting

; --- What this machine does not have ---
;   No video card, no sound, no storage, no real-time clock, no VIA, no
;   joysticks, and no banked RAM.  The Kernal entries that drive them are
;   still in ROM and still safe to call — they check HW_PRESENT and return —
;   but they will do nothing, so there is no reason to call them, and no
;   reason for their names to be in this file.
;
;   The 16x2 LCD is real, but it belongs to the KC Monitor, which drives it
;   through the PIA at $C000.  This series never writes to it.


; =============================================================================
;   SECTION 6: CONSTANTS
; =============================================================================

CHAR_BS             = $08                ; Backspace
CHAR_LF             = $0A                ; Line feed
CHAR_CR             = $0D                ; Carriage return
CHAR_ESC            = $1B                ; Escape
CHAR_SPACE          = $20                ; Space

TARGET = VdpTiles
EIGHTTHREE = VDPTILES
CONFIG = 6502

# VDP only: VdpTiles drives the 6502-PICOVDP's registers directly, so there is
# no TMS9918A build and its outputs carry no -VDP suffix.
# ROM=path runs the build on that BIOS image instead of the bundled one.
VDP = 1
OUT      = $(TARGET)
ASFLAGS  = --asm-define VDP
RUNFLAGS =                    # the PICOVDP card option arrives with 6502-EMULATOR 3.x
RUNFLAGS += $(if $(ROM),--rom $(ROM))

.PHONY: all build view run woz cf clean

all: build woz cf

build: $(TARGET).asm
	cl65 -t none $(ASFLAGS) -C ../$(CONFIG).cfg -l $(OUT).lst -o $(OUT).prg $(TARGET).asm

view:
	hexdump -C $(OUT).prg

run:
	6502 run $(RUNFLAGS) $(OUT).prg

woz:
	bin2woz -a 0x0800 $(OUT).prg > $(OUT).woz

cf:
	cffs create $(OUT).img --size 1M
	mkdir -p .cf
	cp -f $(OUT).prg .cf/$(EIGHTTHREE).PRG
	cffs add $(OUT).img .cf/$(EIGHTTHREE).PRG
	rm -rf .cf

clean:
	rm -rf .cf
	rm -f $(OUT).prg $(OUT).woz $(OUT).lst $(OUT).img

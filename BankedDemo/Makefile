TARGET = BankedDemo

# VDP=1 builds for an ACE with a 6502-PICOVDP and BIOS 2.x (6502-VDP.inc).
# The default builds for BIOS 1.x and the TMS9918A (6502.inc).
# ROM=path runs the build on that BIOS image instead of the bundled one.
VDP ?= 0
ifeq ($(VDP),1)
  SUFFIX   = -VDP
  ASFLAGS  = --asm-define VDP
  # --vdp picovdp needs 6502-EMULATOR 3.x or later
  RUNFLAGS = --vdp picovdp
else
  SUFFIX   =
  ASFLAGS  =
  RUNFLAGS =
endif

# This cartridge is banked or it is nothing: eight pictures of 2,848 bytes is
# 22,784, and a fixed cartridge has 16,378. So FLASH= is not optional here the
# way it is in HelloWorldCart, and it defaults to the part the demo is written
# for. 128K holds the eight banks just as well and is the cheaper chip:
#
#     make               the 512K part, SST39SF040
#     make FLASH=128K    the 128K part, SST39SF010A — same eight pictures
#
# 256K and 1M build too; they are the same image in a bigger chip.
FLASH_TARGETS = 128K 256K 512K 1M
FLASH ?= 512K
ifeq ($(filter $(FLASH),$(FLASH_TARGETS)),)
  $(error FLASH=$(FLASH) is not a cart target — use one of: $(FLASH_TARGETS))
endif

CONFIG   = 6502-$(FLASH)
ASFLAGS += --asm-define FLASH
OUT      = $(TARGET)$(SUFFIX)-$(FLASH)

RUNFLAGS += $(if $(ROM),--rom $(ROM))

.PHONY: all build all-flash gallery check-gallery view run eeprom flash clean

all: build

build: $(TARGET).asm Gallery.inc
	cl65 -t none $(ASFLAGS) -C ../$(CONFIG).cfg -l $(OUT).lst -o $(OUT).crt $(TARGET).asm

# Every flash target for the current VDP setting, one after the other.
all-flash:
	@for t in $(FLASH_TARGETS); do \
	  $(MAKE) --no-print-directory build FLASH=$$t VDP=$(VDP) || exit 1; \
	done

# The eight pictures are generated, and committed so the cartridge builds with
# nothing but cc65 installed.
gallery:
	node tools/make-gallery.mjs

check-gallery:
	node tools/make-gallery.mjs --check

view:
	hexdump -C $(OUT).crt

# Needs 6502-EMULATOR 3.4.0 or later. On 3.3.0 the cartridge is dropped without
# a word and the machine boots to BASIC.
run:
	6502 run $(RUNFLAGS) --cart $(OUT).crt

# There is no EEPROM path from here: the smallest image this project produces
# is four times a 28C256.
eeprom:
	@echo "BankedDemo has no 32K build — it is 22,784 bytes of pictures alone." >&2
	@echo "Burn it with make flash, through the Flash Helper." >&2
	@exit 1

# Burn a Flash Cart through the Flash Helper. `6502-flash program` reads the
# .crt and nothing else — there is no flag that folds a .sav into what it
# writes, by design (6502-VCS PLAN.md §4).
flash:
	6502-flash program $(OUT).crt

clean:
	@for t in $(FLASH_TARGETS); do \
	  rm -f $(TARGET)-$$t.crt $(TARGET)-$$t.lst; \
	  rm -f $(TARGET)-VDP-$$t.crt $(TARGET)-VDP-$$t.lst; \
	done

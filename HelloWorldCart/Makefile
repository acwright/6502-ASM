TARGET = HelloWorldCart

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

# FLASH=128K|256K|512K|1M builds a banked Flash Cart image instead of a 32K ROM
# cart: a byte-exact SST39SF0x0 image, switchable 8 KB banks at $C000-$DFFF and
# a fixed bank at $E000-$FFFF. The naming is 6502-VCS PLAN.md §1 — -VDP first,
# then the target — so `make VDP=1 FLASH=1M` is HelloWorldCart-VDP-1M.crt,
# never HelloWorldCart-1M-VDP.crt.
#
# The config name is the one asymmetry with 6502-CRT: the fixed config is
# 6502-16K here and 6502 there. Every project in this tree names 6502-16K, so
# it keeps its name.
FLASH_TARGETS = 128K 256K 512K 1M
FLASH ?=
ifeq ($(FLASH),)
  CONFIG = 6502-16K
else
  ifeq ($(filter $(FLASH),$(FLASH_TARGETS)),)
    $(error FLASH=$(FLASH) is not a cart target — use one of: $(FLASH_TARGETS))
  endif
  SUFFIX  := $(SUFFIX)-$(FLASH)
  CONFIG   = 6502-$(FLASH)
  ASFLAGS += --asm-define FLASH
endif

OUT = $(TARGET)$(SUFFIX)

RUNFLAGS += $(if $(ROM),--rom $(ROM))

.PHONY: all build all-flash view run eeprom flash clean

all: build

build: $(TARGET).asm
	cl65 -t none $(ASFLAGS) -C ../$(CONFIG).cfg -l $(OUT).lst -o $(OUT).crt $(TARGET).asm

# Every flash target for the current VDP setting, one after the other.
all-flash:
	@for t in $(FLASH_TARGETS); do \
	  $(MAKE) --no-print-directory build FLASH=$$t VDP=$(VDP) || exit 1; \
	done

view:
	hexdump -C $(OUT).crt

# A banked image needs 6502-EMULATOR 3.4.0 or later. On 3.3.0 the cartridge is
# dropped without a word and the machine boots to BASIC.
run:
	6502 run $(RUNFLAGS) --cart $(OUT).crt

# The EEPROM path belongs to the 32K ROM cart alone. A 512K image silently
# truncated into a 28C256 is a confusing afternoon, so refuse and say where to
# go instead.
eeprom:
	@if [ -n "$(FLASH)" ]; then \
	  echo "make eeprom writes a 28C256, which holds 32K — a $(FLASH) image does not fit." >&2; \
	  echo "A Flash Cart is burnt through the Flash Helper: make flash FLASH=$(FLASH)" >&2; \
	  exit 1; \
	fi
	minipro -p AT28C256 -w $(OUT).crt

# Burn a Flash Cart through the Flash Helper. `6502-flash program` reads the
# .crt and nothing else — there is no flag that folds a .sav into what it
# writes, by design (6502-VCS PLAN.md §4).
flash:
	@if [ -z "$(FLASH)" ]; then \
	  echo "make flash needs a cart target, as in: make flash FLASH=512K" >&2; \
	  echo "The 32K ROM cart is burnt with make eeprom." >&2; \
	  exit 1; \
	fi
	6502-flash program $(OUT).crt

clean:
	rm -f $(TARGET).crt $(TARGET).lst
	rm -f $(TARGET)-VDP.crt $(TARGET)-VDP.lst
	@for t in $(FLASH_TARGETS); do \
	  rm -f $(TARGET)-$$t.crt $(TARGET)-$$t.lst; \
	  rm -f $(TARGET)-VDP-$$t.crt $(TARGET)-VDP-$$t.lst; \
	done

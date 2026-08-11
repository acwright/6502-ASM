TARGET = Bit\ Rally
CONFIG = 6502
LOAD = 0x0800

.PHONY: all build view run woz clean

all: build woz

build: $(TARGET).asm
	cl65 -t none -C ../$(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).bin $(TARGET).asm

view:
	hexdump -C $(TARGET).bin

run:
	6502-kim run --bin $(LOAD)=$(TARGET).bin

woz:
	bin2woz -a $(LOAD) $(TARGET).bin > $(TARGET).woz

clean:
	rm -f $(TARGET).bin $(TARGET).woz $(TARGET).lst

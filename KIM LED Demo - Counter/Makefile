TARGET = KIM\ LED\ Demo\ -\ Counter
EIGHTTHREE = KIMCOUNT
CONFIG = 6502

.PHONY: all clean

all: build woz

build: $(TARGET).asm
	cl65 -t none -C ../$(CONFIG).cfg -l $(TARGET).lst -o $(TARGET).prg $(TARGET).asm 
	
view:
	hexdump -C $(TARGET).prg

run:
	6502 run $(TARGET).prg

woz:
	bin2woz -a 0x0800 $(TARGET).prg > $(TARGET).woz

clean:
	rm $(TARGET).prg
	rm $(TARGET).woz
	rm $(TARGET).lst
	rm $(TARGET).img

# gb-unix — Game Boy Unix filesystem ROM
# Uses the bundled RGBDS in tools/rgbds (falls back to $PATH).

AS := rgbasm -I src
LD := rgblink
FIX := rgbfix

ROM := gb-unix.gb
SRC := $(wildcard src/*.asm)
HDR := src/hardware.inc src/fs.inc
OBJ := $(SRC:.asm=.o)

.PHONY: all clean tools

all: $(ROM)

$(ROM): $(OBJ)
	$(LD) -o $@ -n gb-unix.sym -m gb-unix.map $(OBJ)
	$(FIX) -v -m 0x03 -r 0x02 -p 0xFF -t "GBUNIX" -i "GU" $@

%.o: %.asm $(HDR)
	$(AS) -o $@ $<

src/fontdata.asm: tools/genfont.py
	python3 tools/genfont.py

src/logodata.asm: tools/genlogo.py
	python3 tools/genlogo.py

src/fsdata.asm: tools/genfs.py
	python3 tools/genfs.py

tools:
	if [ ! -x $(AS) ]; then \
		echo "RGBDS not found in $(RGBDS_DIR); trying \$\$PATH"; \
	fi

clean:
	rm -f src/*.o $(ROM) gb-unix.sym gb-unix.map

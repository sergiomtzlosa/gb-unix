# gb-unix — Game Boy Unix filesystem ROM
# Assembly uses the bundled RGBDS in tools/rgbds (falls back to $PATH).
# The C modules (src/*.c) are compiled by SDCC to RGBDS-syntax assembly
# (--asm=rgbds) and assembled with rgbasm, so the whole ROM links with
# rgblink alone. C artifacts are kept in build/ so make's built-in
# %.o: %.c rule and the src/*.asm wildcard never see SDCC's outputs.

AS := rgbasm -I src
CC := sdcc -msm83 --asm=rgbds --no-peep
LD := rgblink
FIX := rgbfix

BUILD := build
ROM := gb-unix.gb
SRC := $(wildcard src/*.asm)
CSRC := $(wildcard src/*.c)
HDR := src/hardware.inc src/fs.inc
OBJ := $(SRC:src/%.asm=$(BUILD)/%.o) $(CSRC:src/%.c=$(BUILD)/%.o)

.PHONY: all clean tools

all: $(ROM)

$(ROM): $(OBJ)
	$(LD) -o $@ -n gb-unix.sym -m gb-unix.map $(OBJ)
	$(FIX) -v -m 0x03 -r 0x02 -p 0xFF -t "GBUNIX" -i "GU" $@

$(BUILD)/%.o: src/%.asm $(HDR)
	@mkdir -p $(BUILD)
	$(AS) -o $@ $<

$(BUILD)/%_sdcc.s: src/%.c
	@mkdir -p $(BUILD)
	$(CC) -S $< -o $@

$(BUILD)/%.o: $(BUILD)/%_sdcc.s
	rgbasm -o $@ $<

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
	rm -rf $(BUILD) $(ROM) gb-unix.sym gb-unix.map

# gb-unix — Game Boy Unix filesystem ROM
# Assembly uses the bundled RGBDS in tools/rgbds by default; override AS/LD/FIX
# to use a system install. The C modules (src/*.c) are compiled by SDCC to
# RGBDS-syntax assembly (--asm=rgbds) and assembled with rgbasm. If SDCC is not
# installed, a pre-generated assembly file is used so RGBDS alone can build.
# C artifacts are kept in build/ so make's built-in %.o: %.c rule and the
# src/*.asm wildcard never see SDCC's outputs.

RGBDS_DIR ?= tools/rgbds
AS := $(RGBDS_DIR)/rgbasm
ASFLAGS := -I src
LD := $(RGBDS_DIR)/rgblink
FIX := $(RGBDS_DIR)/rgbfix
CC := sdcc
CCFLAGS := -msm83 --asm=rgbds --no-peep

BUILD := build
ROM := gb-unix.gb
SRC := $(wildcard src/*.asm)
CSRC := $(wildcard src/*.c)
HDR := src/hardware.inc src/fs.inc
OBJ := $(SRC:src/%.asm=$(BUILD)/%.o) $(CSRC:src/%.c=$(BUILD)/%.o)
SHCMD_ASM := src/generated/shcmd_sdcc.asm
SDCC_FOUND := $(shell command -v sdcc >/dev/null 2>&1 && echo 1)

.PHONY: all clean shcmd

all: $(ROM)

$(ROM): $(OBJ)
	$(LD) -o $@ -n gb-unix.sym -m gb-unix.map $(OBJ)
	$(FIX) -v -m 0x03 -r 0x02 -p 0xFF -t "GBUNIX" -i "GU" $@

$(BUILD)/%.o: src/%.asm $(HDR)
	@mkdir -p $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<

ifeq ($(SDCC_FOUND),1)
$(BUILD)/shcmd_sdcc.s: src/shcmd.c
	@mkdir -p $(BUILD)
	$(CC) $(CCFLAGS) -S $< -o $@

$(BUILD)/shcmd.o: $(BUILD)/shcmd_sdcc.s
	$(AS) $(ASFLAGS) -o $@ $<
else
$(info note: sdcc not found; using pre-generated $(SHCMD_ASM))
$(BUILD)/shcmd.o: $(SHCMD_ASM) $(HDR)
	@mkdir -p $(BUILD)
	$(AS) $(ASFLAGS) -o $@ $<
endif

# Regenerate the RGBDS assembly for the C module (requires SDCC 4.2+).
shcmd:
	$(CC) $(CCFLAGS) -S src/shcmd.c -o $(SHCMD_ASM)

src/fontdata.asm: tools/genfont.py
	python3 tools/genfont.py

src/logodata.asm: tools/genlogo.py
	python3 tools/genlogo.py

src/fsdata.asm: tools/genfs.py
	python3 tools/genfs.py

clean:
	rm -rf $(BUILD) $(ROM) gb-unix.sym gb-unix.map

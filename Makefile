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

.DEFAULT_GOAL := all
.PHONY: all clean shcmd help

help:
	@echo "gb-unix - available commands"
	@echo ""
	@echo "Build targets:"
	@echo "  make, make all   Build gb-unix.gb (default)"
	@echo "  make clean       Remove build/, the ROM, symbol and map files"
	@echo "  make shcmd       Regenerate src/generated/shcmd_sdcc.asm (needs SDCC)"
	@echo "  make help        Show this help"
	@echo ""
	@echo "gbsh commands (run inside the ROM shell):"
	@echo "  help             List commands and shell key bindings"
	@echo "  history          Show the last 8 commands, oldest first"
	@echo "  ls [-l] [PATH]   List a directory or file"
	@echo "  cd [PATH]        Change directory (default /home/user)"
	@echo "  pwd              Print the current directory"
	@echo "  cat FILE...      Print one or more files"
	@echo "  echo [TEXT...]   Print text; echo TEXT > FILE writes a file"
	@echo "  mkdir DIR        Create a directory"
	@echo "  rmdir DIR        Remove an empty directory"
	@echo "  rm FILE          Remove a file"
	@echo "  touch FILE       Create an empty file"
	@echo "  gbedit FILE      Edit or create a file"
	@echo "  clear            Clear the terminal"
	@echo "  whoami           Print the current user"
	@echo "  uname            Print the system name"
	@echo "  uptime           Print time since boot"
	@echo "  top              Open the live system monitor"
	@echo "  motd             Print the message of the day"
	@echo "  exit             Log out to the splash screen"

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

# gb-unix — Game Boy Unix filesystem ROM
# Assembly uses the bundled RGBDS for this OS/CPU (tools/rgbds/<os>-<arch>)
# by default; if no matching build is bundled, rgbasm/rgblink/rgbfix from PATH
# are used. Override RGBDS_DIR (or AS/LD/FIX) to use another install.
# The C modules (src/*.c) are compiled by SDCC to
# RGBDS-syntax assembly (--asm=rgbds) and assembled with rgbasm. If SDCC 4.2+
# is not available, a pre-generated assembly file is used so RGBDS alone can
# build. C artifacts are kept in build/ so make's built-in %.o: %.c rule and
# the src/*.asm wildcard never see SDCC's outputs. `make shcmd` downloads a
# prebuilt SDCC for Linux/macOS when the system compiler is missing or too old,
# then regenerates the assembly.

# Bundled binaries live in per-platform directories named after
# `uname -s`/`uname -m`, lowercased, with amd64/aarch64 normalized.
UNAME_S := $(shell uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')
UNAME_M := $(shell uname -m 2>/dev/null)
ifeq ($(UNAME_M),amd64)
UNAME_M := x86_64
endif
ifeq ($(UNAME_M),aarch64)
UNAME_M := arm64
endif
RGBDS_PLATFORM := $(UNAME_S)-$(UNAME_M)
RGBDS_DIR ?= $(if $(wildcard tools/rgbds/$(RGBDS_PLATFORM)/rgbasm),tools/rgbds/$(RGBDS_PLATFORM),)
AS := $(if $(RGBDS_DIR),$(RGBDS_DIR)/rgbasm,rgbasm)
ASFLAGS := -I src
LD := $(if $(RGBDS_DIR),$(RGBDS_DIR)/rgblink,rgblink)
FIX := $(if $(RGBDS_DIR),$(RGBDS_DIR)/rgbfix,rgbfix)
CC := sdcc
CCFLAGS := -msm83 --asm=rgbds --no-peep

BUILD := build
ROM := gb-unix.gb
SRC := $(wildcard src/*.asm)
CSRC := $(wildcard src/*.c)
HDR := src/hardware.inc src/fs.inc
OBJ := $(SRC:src/%.asm=$(BUILD)/%.o) $(CSRC:src/%.c=$(BUILD)/%.o)
SHCMD_ASM := src/generated/shcmd_sdcc.asm

# SDCC 4.2+ is required for --asm=rgbds. If the system compiler is missing or
# too old, `make shcmd` downloads a prebuilt SDCC from the GBDK-2020 project
# into .cache/sdcc. Normal builds never download anything.
SDCC_LOCAL := .cache/sdcc
SDCC_LOCAL_BIN := $(SDCC_LOCAL)/bin/sdcc
SDCC_LOCAL_INC := -I $(SDCC_LOCAL)/include
SDCC_OK := $(shell { command -v "$(CC)" >/dev/null 2>&1 || [ -x "$(CC)" ]; } && "$(CC)" -v 2>&1 | sed -n 's/.* \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1 | awk -F. '$$1 > 4 || ($$1 == 4 && $$2 >= 2) { print 1 }')
SDCC_LOCAL_OK := $(shell [ -x "$(SDCC_LOCAL_BIN)" ] && echo 1)
SDCC_FOUND := $(if $(SDCC_OK)$(SDCC_LOCAL_OK),1,)

ifeq ($(SDCC_OK),1)
SDCC_CMD := $(CC)
SDCC_INC :=
else
SDCC_CMD := $(SDCC_LOCAL_BIN)
SDCC_INC := $(SDCC_LOCAL_INC)
endif

.DEFAULT_GOAL := all
.PHONY: all clean shcmd help install-sdcc sdcc-download

help:
	@echo "gb-unix - available commands"
	@echo ""
	@echo "Build targets:"
	@echo "  make, make all   Build gb-unix.gb (default)"
	@echo "  make clean       Remove build/, the ROM, symbol and map files"
	@echo "  make install-sdcc  Download prebuilt SDCC for Linux/macOS if needed"
	@echo "  make shcmd       Download SDCC if needed, then regenerate C-to-RGBDS assembly"
	@echo "  make help        Show this help"
	@echo ""
	@echo "Using RGBDS: $(AS)"
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
	$(SDCC_CMD) $(CCFLAGS) $(SDCC_INC) -S $< -o $@

$(BUILD)/shcmd.o: $(BUILD)/shcmd_sdcc.s
	$(AS) $(ASFLAGS) -o $@ $<
else
$(BUILD)/shcmd.o: $(SHCMD_ASM) $(HDR)
	@mkdir -p $(BUILD)
	@echo "note: SDCC 4.2+ not found; using pre-generated $(SHCMD_ASM)"
	$(AS) $(ASFLAGS) -o $@ $<
endif

# Download a prebuilt SDCC when the system compiler is missing or older than 4.2.
ifeq ($(SDCC_OK),1)
sdcc-download:
	@echo "SDCC 4.2+ is already available; no download needed"
else ifeq ($(SDCC_LOCAL_OK),1)
sdcc-download:
	@echo "using prebuilt SDCC in $(SDCC_LOCAL)"
else
sdcc-download:
	@set -e; \
	if [ -x "$(SDCC_LOCAL_BIN)" ]; then \
		echo "using prebuilt SDCC in $(SDCC_LOCAL)"; \
		exit 0; \
	fi; \
	os=$$(uname -s 2>/dev/null || echo unknown); \
	arch=$$(uname -m 2>/dev/null || echo unknown); \
	case "$$os-$$arch" in \
	Linux-x86_64|Linux-amd64) \
		url="https://github.com/gbdk-2020/gbdk-2020/releases/download/4.3.0/gbdk-linux64.tar.gz"; \
		sha="5032e4e4edcef3f0ed232c895bbd211973963329304ff2c030ea34d0b2d964a4"; \
		;; \
	Linux-aarch64|Linux-arm64) \
		url="https://github.com/gbdk-2020/gbdk-2020/releases/download/4.4.0/gbdk-linux-arm64.tar.gz"; \
		sha="4b1c2546ecdee56d622c0c48b843bd7efc2a14fc5a1ac61837c0467006b10fe2"; \
		;; \
	Darwin-x86_64|Darwin-amd64) \
		url="https://github.com/gbdk-2020/gbdk-2020/releases/download/4.3.0/gbdk-macos.tar.gz"; \
		sha="c796089c03f64153cf67c49568416ce05ac1865d2eac59ae4c58445b974eb619"; \
		;; \
	Darwin-arm64|Darwin-aarch64) \
		url="https://github.com/gbdk-2020/gbdk-2020/releases/download/4.3.0/gbdk-macos-arm64.tar.gz"; \
		sha="d8300880ef65e291b226db6c82e116f669aff294f1bea506c41729e8cc86a1f6"; \
		;; \
	*) \
		echo "error: no prebuilt SDCC for $$os-$$arch" >&2; \
		echo "install SDCC 4.2+ manually and put it on PATH" >&2; \
		exit 1; \
		;; \
	esac; \
	mkdir -p .cache; \
	archive=".cache/gbdk-sdcc.tar.gz"; \
	part="$$archive.part"; \
	tmp=".cache/sdcc.tmp"; \
	rm -f "$$part"; \
	rm -rf "$$tmp"; \
	mkdir -p "$$tmp"; \
	echo "Downloading prebuilt SDCC for $$os-$$arch..."; \
	if command -v curl >/dev/null 2>&1; then \
		curl -L --fail --retry 3 -o "$$part" "$$url" || { rm -f "$$part"; exit 1; }; \
	elif command -v wget >/dev/null 2>&1; then \
		wget -O "$$part" "$$url" || { rm -f "$$part"; exit 1; }; \
	else \
		echo "error: curl or wget is required to download SDCC" >&2; \
		rm -f "$$part"; exit 1; \
	fi; \
	if command -v sha256sum >/dev/null 2>&1; then \
		sum=$$(sha256sum "$$part" | awk '{print $$1}'); \
	elif command -v shasum >/dev/null 2>&1; then \
		sum=$$(shasum -a 256 "$$part" | awk '{print $$1}'); \
	else \
		echo "error: sha256sum or shasum is required to verify SDCC" >&2; \
		rm -f "$$part"; exit 1; \
	fi; \
	if [ "$$sum" != "$$sha" ]; then \
		echo "error: SDCC download checksum mismatch" >&2; \
		echo "  expected $$sha" >&2; \
		echo "  got      $$sum" >&2; \
		rm -f "$$part"; exit 1; \
	fi; \
	if ! tar -xzf "$$part" -C "$$tmp" --strip-components=1; then \
		echo "error: could not extract SDCC archive" >&2; \
		rm -f "$$part"; rm -rf "$$tmp"; exit 1; \
	fi; \
	if [ ! -x "$$tmp/bin/sdcc" ]; then \
		echo "error: extracted SDCC archive has no bin/sdcc" >&2; \
		rm -f "$$part"; rm -rf "$$tmp"; exit 1; \
	fi; \
	rm -rf "$(SDCC_LOCAL)"; \
	mv "$$tmp" "$(SDCC_LOCAL)"; \
	if [ ! -x "$(SDCC_LOCAL_BIN)" ]; then \
		echo "error: could not install SDCC in $(SDCC_LOCAL)" >&2; \
		exit 1; \
	fi; \
	if ! "$(SDCC_LOCAL_BIN)" -v >/dev/null 2>&1; then \
		echo "error: downloaded SDCC cannot run on this system" >&2; \
		rm -rf "$(SDCC_LOCAL)"; rm -f "$$part"; \
		exit 1; \
	fi; \
	rm -f "$$part"; \
	echo "Installed prebuilt SDCC in $(SDCC_LOCAL)"; \
	"$(SDCC_LOCAL_BIN)" -v 2>&1 | head -n 1
endif

install-sdcc: sdcc-download

# Regenerate the RGBDS assembly for the C module (requires SDCC 4.2+).
shcmd:
	@$(MAKE) --no-print-directory sdcc-download || true
	@if [ -x "$(SDCC_CMD)" ] || command -v "$(SDCC_CMD)" >/dev/null 2>&1; then \
		ver=$$($(SDCC_CMD) -v 2>&1 | sed -n 's/.* \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1); \
		major=$${ver%%.*}; rest=$${ver#*.}; minor=$${rest%%.*}; \
		if [ -z "$$ver" ] || [ "$$major" -lt 4 ] || { [ "$$major" -eq 4 ] && [ "$$minor" -lt 2 ]; }; then \
			echo "note: SDCC $$ver is too old (4.2+ required); keeping $(SHCMD_ASM)" >&2; \
			exit 0; \
		fi; \
		tmp=$$(mktemp "$${TMPDIR:-/tmp}/gbunix-shcmd.XXXXXX") || exit 1; \
		if $(SDCC_CMD) $(CCFLAGS) $(SDCC_INC) -S src/shcmd.c -o "$$tmp"; then \
			if { \
				echo '; shcmd_sdcc.asm — generated from src/shcmd.c by SDCC.'; \
				echo ';'; \
				echo '; Used when no SDCC 4.2+ compiler is available, so the ROM can still be'; \
				echo '; built with just the bundled RGBDS. Regenerate with `make shcmd`.'; \
				echo ''; \
				sed 's/[[:space:]]*$$//' "$$tmp"; \
			} > "$$tmp.new" && mv "$$tmp.new" $(SHCMD_ASM); then \
				rm -f "$$tmp"; \
				echo "regenerated $(SHCMD_ASM)"; \
			else \
				rm -f "$$tmp" "$$tmp.new"; \
				echo "note: could not write $(SHCMD_ASM); keeping the old file" >&2; \
			fi; \
		else \
			rm -f "$$tmp"; \
			echo "note: SDCC could not regenerate the assembly; keeping $(SHCMD_ASM)" >&2; \
		fi; \
	else \
		echo "note: SDCC 4.2+ not available; keeping the checked-in $(SHCMD_ASM)" >&2; \
		echo "      run 'make install-sdcc' or install SDCC manually" >&2; \
	fi

src/fontdata.asm: tools/genfont.py
	python3 tools/genfont.py

src/logodata.asm: tools/genlogo.py
	python3 tools/genlogo.py

src/fsdata.asm: tools/genfs.py
	python3 tools/genfs.py

clean:
	rm -rf $(BUILD) $(ROM) gb-unix.sym gb-unix.map

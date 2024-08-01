; sram.asm — battery-backed SRAM: live filesystem state
;
; Cartridge: MBC1 + 8KB SRAM + battery (cart type 0x03, RAM size 0x02).
; With 8KB SRAM the whole chip is always visible at $A000-$BFFF (MBC1 RAM
; bank 0), so we never switch RAM banks — just enable/disable the SRAM gate.
; Emulators persist this to a .sav next to the ROM automatically.
;
; Layout:
;   $A000-$A003  magic "GBUX"
;   $A004        format version
;   $A005        reserved
;   $A006-$A007  heap free pointer (u16)
;   $A010-...    inode table: NODE_COUNT nodes x 20 bytes
;   NODE_HEAP-.. user file contents (bump allocator)

include "hardware.inc"
include "fs.inc"

section "sram", rom0

; sram_enable:: open the SRAM gate.
sram_enable::
	push af
	ld a, $0A
	ld [$0000], a
	pop af
	ret

; sram_init:: enable SRAM; format from ROM if magic/version mismatch.
; Returns a = 1 if freshly formatted, 0 if save loaded.
sram_init::
	call sram_enable
	ld hl, SRAM_MAGIC
	ld a, [hl+]
	cp 'G'
	jr nz, .fresh
	ld a, [hl+]
	cp 'B'
	jr nz, .fresh
	ld a, [hl+]
	cp 'U'
	jr nz, .fresh
	ld a, [hl+]
	cp 'X'
	jr nz, .fresh
	ld a, [SRAM_VER]
	cp FS_VERSION
	jr nz, .fresh
	xor a
	ret
.fresh:
	call sram_format
	ld a, 1
	ret

; sram_format:: write header + copy pristine tree from ROM + reset heap.
sram_format::
	ld hl, SRAM_MAGIC
	ld [hl], 'G'
	inc hl
	ld [hl], 'B'
	inc hl
	ld [hl], 'U'
	inc hl
	ld [hl], 'X'
	inc hl
	ld a, FS_VERSION
	ld [hl], a
	; copy the ROM inode table into SRAM
	ld hl, fs_rom_nodes
	ld de, SRAM_NODES
	ld bc, NODE_COUNT * NODE_SIZE
	call mem_copy
	; heap pointer = NODE_HEAP
	ld hl, NODE_HEAP
	ld a, l
	ld [SRAM_HEAP_PTR], a
	ld a, h
	ld [SRAM_HEAP_PTR+1], a
	ret

; heap_alloc:: allocate bc bytes in SRAM heap.
; in:  bc = size
; out: de = address, CF clear = ok, CF set = out of space
heap_alloc::
	push hl
	ld hl, SRAM_HEAP_PTR
	ld a, [hl+]
	ld e, a
	ld a, [hl]
	ld d, a             ; de = current free pointer
	push de
	pop hl              ; hl = de
	add hl, bc          ; new pointer
	; check hl <= HEAP_END
	ld a, h
	cp HEAP_END >> 8
	jr c, .ok
	jr nz, .fail
	ld a, l
	cp HEAP_END & $FF
	jr c, .ok
	jr nz, .fail
.ok:
	ld a, l
	ld [SRAM_HEAP_PTR], a
	ld a, h
	ld [SRAM_HEAP_PTR+1], a
	or a                ; clear carry = success
	pop hl
	ret
.fail:
	scf
	pop hl
	ret

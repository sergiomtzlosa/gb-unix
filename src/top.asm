; top.asm — a tiny top-style system monitor for gbsh
;
; gb-unix has one cooperative task (the main loop), so this is a snapshot of
; the machine rather than a scheduler: uptime, inode use and SRAM heap use.
; The uptime line refreshes once per second while the screen is open.

include "hardware.inc"
include "fs.inc"

section "topw", wram0

top_last_sec::  db
top_used::      db
top_files::     db
top_dirs::      db
top_heap_used:: ds 2
top_heap_free:: ds 2

section "top", rom0

top_enter::
	ld a, MODE_TOP
	ld [mode], a
	xor a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	ld a, $FF
	ld [invert_row], a
	call txt_clear
	call top_scan_fs
	call top_calc_heap
	call top_draw
	jp top_print_uptime

top_update::
	ld a, [joy_pressed]
	and J_A | J_B | J_START
	jp nz, shell_enter
	ld a, [upt_secs]
	ld b, a
	ld a, [top_last_sec]
	cp b
	ret z
	jp top_print_uptime

; top_scan_fs:: count used inodes and how many are files/directories.
top_scan_fs:
	xor a
	ld [top_used], a
	ld [top_files], a
	ld [top_dirs], a
	ld hl, SRAM_NODES
	ld b, NODE_COUNT
.loop:
	ld a, [hl]
	or a
	jr z, .next
	ld a, [top_used]
	inc a
	ld [top_used], a
	ld a, [hl]
	cp N_FILE
	jr nz, .dir
	ld a, [top_files]
	inc a
	ld [top_files], a
	jr .next
.dir:
	cp N_DIR
	jr nz, .next
	ld a, [top_dirs]
	inc a
	ld [top_dirs], a
.next:
	ld de, NODE_SIZE
	add hl, de
	dec b
	jr nz, .loop
	ret

; top_calc_heap:: used/free bytes in the SRAM content heap.
top_calc_heap:
	ld a, [SRAM_HEAP_PTR]
	ld e, a
	ld a, [SRAM_HEAP_PTR+1]
	ld d, a
	; used = heap pointer - start of heap
	ld a, e
	sub NODE_HEAP & $FF
	ld l, a
	ld a, d
	sbc NODE_HEAP >> 8
	ld h, a
	ld a, l
	ld [top_heap_used], a
	ld a, h
	ld [top_heap_used+1], a
	; free = end of heap - heap pointer
	ld a, HEAP_END & $FF
	sub e
	ld l, a
	ld a, HEAP_END >> 8
	sbc d
	ld h, a
	ld a, l
	ld [top_heap_free], a
	ld a, h
	ld [top_heap_free+1], a
	ret

; top_print_uptime:: refresh the "up Nm Ns" line and remember the second.
top_print_uptime:
	ld a, 1
	call txt_clear_row
	ld a, 1
	ld c, 0
	call txt_goto
	ld hl, str_top_up
	call txt_print_z
	ld a, [upt_secs]
	ld e, a
	ld a, [upt_secs+1]
	ld d, a
	push de
	pop hl
	ld c, 60
	call div_hl_c
	push af
	call txt_print_u16
	ld hl, str_top_m
	call txt_print_z
	pop af
	ld l, a
	ld h, 0
	call txt_print_u16
	ld hl, str_top_s
	call txt_print_z
	ld a, [upt_secs]
	ld [top_last_sec], a
	ret

; top_print_u8:: print a byte count as decimal.
top_print_u8:
	ld l, a
	ld h, 0
	jp txt_print_u16

; top_draw:: draw the static dashboard; uptime is drawn separately.
top_draw:
	xor a
	ld c, 0
	call txt_goto
	ld hl, str_top_title
	call txt_print_z

	ld a, 2
	ld c, 0
	call txt_goto
	ld hl, str_top_sep
	call txt_print_z

	ld a, 3
	ld c, 0
	call txt_goto
	ld hl, str_top_head
	call txt_print_z

	ld a, 4
	ld c, 0
	call txt_goto
	ld hl, str_top_task
	call txt_print_z

	ld a, 5
	ld c, 0
	call txt_goto
	ld hl, str_top_tasks
	call txt_print_z

	ld a, 6
	ld c, 0
	call txt_goto
	ld hl, str_top_sep
	call txt_print_z

	; inodes: used / total
	ld a, 7
	ld c, 0
	call txt_goto
	ld hl, str_top_inodes
	call txt_print_z
	ld a, [top_used]
	call top_print_u8
	ld hl, str_top_slash
	call txt_print_z
	ld a, NODE_COUNT
	call top_print_u8

	; files / dirs
	ld a, 8
	ld c, 0
	call txt_goto
	ld hl, str_top_files
	call txt_print_z
	ld a, [top_files]
	call top_print_u8
	ld hl, str_top_dirs
	call txt_print_z
	ld a, [top_dirs]
	call top_print_u8

	; heap: used / total
	ld a, 9
	ld c, 0
	call txt_goto
	ld hl, str_top_heap
	call txt_print_z
	ld a, [top_heap_used]
	ld l, a
	ld a, [top_heap_used+1]
	ld h, a
	call txt_print_u16
	ld hl, str_top_slash
	call txt_print_z
	ld hl, HEAP_END - NODE_HEAP
	call txt_print_u16
	ld hl, str_top_b
	call txt_print_z

	; free heap bytes
	ld a, 10
	ld c, 0
	call txt_goto
	ld hl, str_top_free
	call txt_print_z
	ld a, [top_heap_free]
	ld l, a
	ld a, [top_heap_free+1]
	ld h, a
	call txt_print_u16
	ld hl, str_top_b
	call txt_print_z

	ld a, 11
	ld c, 0
	call txt_goto
	ld hl, str_top_sram
	call txt_print_z

	ld a, 12
	ld c, 0
	call txt_goto
	ld hl, str_top_sep
	call txt_print_z

	ld a, 13
	ld c, 0
	call txt_goto
	ld hl, str_top_back
	jp txt_print_z

str_top_title:  db "GB-UNIX top", 0
str_top_sep:    db "--------------------", 0
str_top_head:   db " PID STAT COMMAND", 0
str_top_task:   db "  1  R  main loop", 0
str_top_tasks:  db "tasks: 1 running", 0
str_top_inodes: db "inodes: ", 0
str_top_slash:  db "/", 0
str_top_files:  db "files: ", 0
str_top_dirs:   db "  dirs: ", 0
str_top_heap:   db "heap: ", 0
str_top_free:   db "free: ", 0
str_top_b:      db " B", 0
str_top_sram:   db "SRAM: 8 KB", 0
str_top_back:   db "A/B/START: back", 0
str_top_up:     db "up ", 0
str_top_m:      db "m ", 0
str_top_s:      db "s", 0

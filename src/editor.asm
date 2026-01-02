; editor.asm — gbedit: tiny line-based text editor
;
; Layout:
;   row 0      header: "gbedit <name>" + '*' when modified
;   rows 1-9   text (one logical line per row, horizontally scrolled)
;   row 10     key hint
;   row 11     key hint / error message
;   rows 12-17 on-screen keyboard (shared with the shell)
;
; Controls:
;   D-pad      move keyboard cursor     A     insert selected key
;   B          backspace                B+A   insert newline
;   B+dpad     move text cursor         SELECT shift layer
;   START      save and quit            SELECT+START quit without saving

include "hardware.inc"
include "fs.inc"

def ED_CAP        equ 2048       ; text buffer capacity
def ED_TEXT_TOP   equ 1
def ED_TEXT_ROWS  equ 9
def ED_HINT1_ROW  equ 10
def ED_HINT2_ROW  equ 11

section "editorw", wram0

ed_len::        dw              ; bytes used in ed_buf
ed_line::       dw              ; cursor line
ed_col::        dw              ; cursor column
ed_top::        dw              ; first visible line
ed_xoff::       dw              ; first visible column
ed_idx::        dw              ; scratch buffer offset
ed_row::        db              ; scratch screen row
ed_node::       db
ed_dirty::      db
ed_b_armed::    db
ed_b_combo::    db
ed_buf::        ds ED_CAP

section "editor", rom0

MACRO LD_HL_VAR
	ld a, [\1]
	ld l, a
	ld a, [\1+1]
	ld h, a
ENDM

MACRO LD_DE_VAR
	ld a, [\1]
	ld e, a
	ld a, [\1+1]
	ld d, a
ENDM

MACRO ST_HL_VAR
	ld a, l
	ld [\1], a
	ld a, h
	ld [\1+1], a
ENDM

MACRO ST_BC_VAR
	ld a, c
	ld [\1], a
	ld a, b
	ld [\1+1], a
ENDM

; ---- low-level helpers ------------------------------------------------

; ed_ptr_add:: hl = ed_buf + hl. Preserves de.
ed_ptr_add:
	push de
	ld de, ed_buf
	add hl, de
	pop de
	ret

; ed_hl_ge_len:: CF set if hl >= ed_len. Clobbers a.
ed_hl_ge_len:
	ld a, [ed_len+1]
	cp h
	jr c, .ge
	jr nz, .lt
	ld a, [ed_len]
	cp l
	jr c, .ge
	jr z, .ge
.lt:
	and a               ; clear carry
	ret
.ge:
	scf
	ret

; ed_line_start:: hl = line number -> hl = byte offset of its first char.
; Returns ed_len when the line is past the end. Clobbers a, bc, de.
ed_line_start:
	ld d, h
	ld e, l             ; de = lines still to skip
	; bc = ed_buf + ed_len (end pointer)
	ld a, [ed_len]
	ld c, a
	ld a, [ed_len+1]
	ld b, a
	ld hl, ed_buf
	add hl, bc
	ld b, h
	ld c, l             ; bc = end pointer
	ld hl, ed_buf       ; current pointer
.next:
	ld a, d
	or e
	jr z, .found
.scan:
	ld a, h
	cp b
	jr c, .read
	jr nz, .at_end
	ld a, l
	cp c
	jr nc, .at_end
.read:
	ld a, [hl+]
	cp $0A
	jr z, .newline
	jr .scan
.newline:
	dec de
	jr .next
.at_end:
	; hl is already the end pointer
.found:
	ld de, ed_buf
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	ret

; ed_line_len:: hl = line offset -> bc = length (without newline).
; Clobbers a, de, hl.
ed_line_len:
	ld d, h
	ld e, l             ; de = current offset
	ld bc, 0
.loop:
	ld a, [ed_len+1]
	cp d
	jr c, .done
	jr nz, .read
	ld a, [ed_len]
	cp e
	jr c, .done
	jr z, .done
.read:
	push bc
	push de
	ld h, d
	ld l, e
	call ed_ptr_add
	ld a, [hl]
	pop de
	pop bc
	cp $0A
	jr z, .done
	inc de
	inc bc
	jr .loop
.done:
	ret

; ed_cur_idx:: hl = buffer offset of the cursor. Clobbers a, bc, de.
ed_cur_idx:
	LD_HL_VAR ed_line
	call ed_line_start
	LD_DE_VAR ed_col
	add hl, de
	ret

; ed_mark_dirty:: flag the buffer as modified.
ed_mark_dirty:
	ld a, 1
	ld [ed_dirty], a
	ret

; ---- entry / load -----------------------------------------------------

; editor_enter:: open node a in the editor. CF set on error (fs_errno set).
editor_enter::
	ld [ed_node], a
	call fs_node_addr
	ld a, [hl]
	cp N_FILE
	jp nz, .isdir
	; ROM files are immutable: refuse before loading
	push hl
	ld de, N_ATTRS
	add hl, de
	bit 0, [hl]
	pop hl
	jr z, .eperm
	; reject files that do not fit the edit buffer
	push hl
	ld de, N_SIZE
	add hl, de
	ld a, [hl+]
	ld c, a
	ld a, [hl]
	ld b, a
	pop hl
	ld a, b
	cp ED_CAP >> 8
	jr c, .size_ok
	jr nz, .toobig
	ld a, c
	cp ED_CAP & $FF
	jr nc, .toobig
.size_ok:
	xor a
	ld [ed_len], a
	ld [ed_len+1], a
	ld [ed_line], a
	ld [ed_line+1], a
	ld [ed_col], a
	ld [ed_col+1], a
	ld [ed_top], a
	ld [ed_top+1], a
	ld [ed_xoff], a
	ld [ed_xoff+1], a
	ld [ed_dirty], a
	ld [ed_b_armed], a
	ld [ed_b_combo], a
	; load file bytes
	ld a, [ed_node]
	call fs_read_open
	ld hl, ed_buf
	ld bc, 0
.load:
	call fread_next
	jr nc, .loaded
	ld [hl+], a
	inc bc
	jr .load
.loaded:
	ST_BC_VAR ed_len
	; switch screens
	ld a, MODE_EDITOR
	ld [mode], a
	xor a
	ld [scr_top], a
	ld a, SCREEN_H - 1
	ld [scr_bot], a
	ld a, $FF
	ld [invert_row], a
	call kb_reset
	call txt_clear
	call editor_render_all
	or a
	ret
.isdir:
	ld a, FS_E_ISDIR
	jr .err
.eperm:
	ld a, FS_E_EPERM
	jr .err
.toobig:
	ld a, FS_E_TOOBIG
.err:
	ld [fs_errno], a
	scf
	ret

; ---- rendering --------------------------------------------------------

editor_render_all:
	call editor_render
	jp shell_render_kb

editor_render:
	call ed_ensure_visible
	call ed_draw_header
	call ed_draw_text
	jp ed_draw_hints

ed_draw_header:
	xor a
	call txt_clear_row
	xor a
	ld c, 0
	call txt_goto
	ld hl, ed_hdr_prefix
	call txt_print_z
	ld a, [ed_node]
	call fs_node_addr
	inc hl
	call txt_print_z
	ld a, [ed_dirty]
	or a
	ret z
	xor a
	ld c, SCREEN_W - 1
	call txt_goto
	ld a, '*'
	jp txt_putc

ed_draw_hints:
	ld a, ED_HINT1_ROW
	call txt_clear_row
	ld a, ED_HINT1_ROW
	ld c, 0
	call txt_goto
	ld hl, ed_hint1
	call txt_print_z
	ld a, ED_HINT2_ROW
	call txt_clear_row
	ld a, ED_HINT2_ROW
	ld c, 0
	call txt_goto
	ld hl, ed_hint2
	jp txt_print_z

; ed_draw_text:: draw the visible logical lines, then the cursor.
ed_draw_text:
	ld a, 1
	ld [scr_full], a     ; nine rows change together
	; clear text rows
	ld b, ED_TEXT_TOP
.clear:
	push bc
	ld a, b
	call txt_clear_row
	pop bc
	inc b
	ld a, b
	cp ED_TEXT_TOP + ED_TEXT_ROWS
	jr c, .clear
	xor a
	ld [ed_row], a
.row_loop:
	ld a, [ed_row]
	cp ED_TEXT_ROWS
	jr nc, .done
	; hl = offset of (ed_top + ed_row)
	LD_HL_VAR ed_top
	ld a, [ed_row]
	ld e, a
	ld d, 0
	add hl, de
	call ed_line_start
	ST_HL_VAR ed_idx
	call ed_line_len
	; bc = length; skip ed_xoff columns
	LD_DE_VAR ed_xoff
	ld a, c
	sub e
	ld c, a
	ld a, b
	sbc d
	ld b, a
	jr c, .nextrow      ; line shorter than xoff
	ld a, b
	or c
	jr z, .nextrow      ; nothing left to show
	; cap at the screen width
	ld a, b
	or a
	jr nz, .cap
	ld a, c
	cp SCREEN_W
	jr c, .copy_setup
.cap:
	ld bc, SCREEN_W
.copy_setup:
	; source = ed_buf + ed_idx + ed_xoff
	LD_HL_VAR ed_idx
	LD_DE_VAR ed_xoff
	add hl, de
	call ed_ptr_add
	push hl             ; save source
	ld a, [ed_row]
	add ED_TEXT_TOP
	call txt_row_addr   ; hl = destination row
	ld d, h
	ld e, l
	pop hl              ; hl = source
.copy:
	ld a, b
	or c
	jr z, .nextrow
	ld a, [hl+]
	cp $20
	jr c, .dot
	cp $7F
	jr c, .store
.dot:
	ld a, '.'
.store:
	sub $20
	ld [de], a
	inc de
	dec bc
	jp .copy
.nextrow:
	ld a, [ed_row]
	inc a
	ld [ed_row], a
	jp .row_loop
.done:
	jp ed_draw_cursor

; ed_draw_cursor:: invert the tile under the cursor.
ed_draw_cursor:
	LD_HL_VAR ed_line
	LD_DE_VAR ed_top
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	jr c, .ret
	ld a, h
	or a
	jr nz, .ret
	ld a, l
	cp ED_TEXT_ROWS
	jr nc, .ret
	ld b, a             ; screen row index
	LD_HL_VAR ed_col
	LD_DE_VAR ed_xoff
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	jr c, .ret
	ld a, h
	or a
	jr nz, .ret
	ld a, l
	cp SCREEN_W
	jr nc, .ret
	ld c, a             ; screen column
	push bc
	call ed_cur_idx
	call ed_hl_ge_len
	jr c, .space
	call ed_ptr_add
	ld a, [hl]
	cp $0A
	jr z, .space
	cp $20
	jr c, .space
	cp $7F
	jr c, .tile
.space:
	xor a
.tile:
	pop bc
	add INVERT_BASE
	push af
	ld a, b
	add ED_TEXT_TOP
	call txt_row_addr
	pop af
	ld e, c
	ld d, 0
	add hl, de
	ld [hl], a
.ret:
	ret

; ed_ensure_visible:: keep the cursor inside the viewport.
ed_ensure_visible:
	LD_HL_VAR ed_line
	LD_DE_VAR ed_top
	ld a, h
	cp d
	jr c, .set_top
	jr nz, .check_bottom
	ld a, l
	cp e
	jr c, .set_top
.check_bottom:
	LD_DE_VAR ed_top
	ld a, e
	add ED_TEXT_ROWS
	ld e, a
	ld a, d
	adc 0
	ld d, a
	LD_HL_VAR ed_line
	ld a, h
	cp d
	jr c, .horizontal
	jr nz, .set_bottom
	ld a, l
	cp e
	jr c, .horizontal
.set_bottom:
	LD_HL_VAR ed_line
	ld de, ED_TEXT_ROWS - 1
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc 0
	ld h, a
	ST_HL_VAR ed_top
	jr .horizontal
.set_top:
	LD_HL_VAR ed_line
	ST_HL_VAR ed_top
.horizontal:
	LD_HL_VAR ed_col
	LD_DE_VAR ed_xoff
	ld a, h
	cp d
	jr c, .set_x
	jr nz, .check_right
	ld a, l
	cp e
	jr c, .set_x
.check_right:
	LD_DE_VAR ed_xoff
	ld a, e
	add SCREEN_W
	ld e, a
	ld a, d
	adc 0
	ld d, a
	LD_HL_VAR ed_col
	ld a, h
	cp d
	jr c, .done
	jr nz, .set_right
	ld a, l
	cp e
	jr c, .done
.set_right:
	LD_HL_VAR ed_col
	ld de, SCREEN_W - 1
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc 0
	ld h, a
	ST_HL_VAR ed_xoff
	jr .done
.set_x:
	LD_HL_VAR ed_col
	ST_HL_VAR ed_xoff
.done:
	ret

ed_hdr_prefix:  db "gbedit ", 0
ed_hint1:       db "A:ins B:del B+A:nl", 0
ed_hint2:       db "B+pad:mv ST:save+Q", 0

; ---- buffer editing ---------------------------------------------------

; ed_insert:: insert character a at the cursor. CF set if the buffer is full.
ed_insert::
	push af
	LD_HL_VAR ed_len
	ld a, h
	cp (ED_CAP - 1) >> 8
	jr c, .room
	jr nz, .full
	ld a, l
	cp (ED_CAP - 1) & $FF
	jr nc, .full
.room:
	call ed_cur_idx
	ST_HL_VAR ed_idx
	; bc = ed_len - ed_cur
	LD_HL_VAR ed_len
	LD_DE_VAR ed_idx
	ld a, l
	sub e
	ld c, a
	ld a, h
	sbc d
	ld b, a
	; shift [cur..len) one byte to the right
	LD_HL_VAR ed_len
	call ed_ptr_add
	ld d, h
	ld e, l
	inc de
.shift:
	ld a, b
	or c
	jr z, .store
	dec hl
	dec de
	ld a, [hl]
	ld [de], a
	dec bc
	jr .shift
.store:
	pop af
	push af
	LD_HL_VAR ed_idx
	call ed_ptr_add
	pop af
	ld [hl], a
	LD_HL_VAR ed_len
	inc hl
	ST_HL_VAR ed_len
	call ed_mark_dirty
	or a
	ret
.full:
	pop af
	scf
	ret

; ed_type_char:: insert a and advance the column.
ed_type_char:
	call ed_insert
	ret c
	LD_HL_VAR ed_col
	inc hl
	ST_HL_VAR ed_col
	ret

; ed_newline:: insert a newline and move to the next line.
ed_newline:
	ld a, $0A
	call ed_insert
	ret c
	LD_HL_VAR ed_line
	inc hl
	ST_HL_VAR ed_line
	xor a
	ld [ed_col], a
	ld [ed_col+1], a
	ret

; ed_delete_at:: delete the byte at offset hl.
ed_delete_at:
	LD_DE_VAR ed_len
	ld a, h
	cp d
	jr c, .ok
	jr nz, .ret
	ld a, l
	cp e
	jr nc, .ret
.ok:
	ST_HL_VAR ed_idx
	; bc = ed_len - idx - 1
	LD_HL_VAR ed_len
	LD_DE_VAR ed_idx
	ld a, l
	sub e
	ld c, a
	ld a, h
	sbc d
	ld b, a
	dec bc
	; dest = ed_buf+idx, src = dest+1
	LD_HL_VAR ed_idx
	call ed_ptr_add
	ld d, h
	ld e, l
	inc hl
.copy:
	ld a, b
	or c
	jr z, .done
	ld a, [hl+]
	ld [de], a
	inc de
	dec bc
	jr .copy
.done:
	LD_HL_VAR ed_len
	dec hl
	ST_HL_VAR ed_len
.ret:
	ret

; ed_backspace:: delete before the cursor; joins lines at column 0.
ed_backspace:
	LD_HL_VAR ed_col
	ld a, h
	or l
	jr z, .line_start
	call ed_cur_idx
	dec hl
	call ed_delete_at
	LD_HL_VAR ed_col
	dec hl
	ST_HL_VAR ed_col
	call ed_mark_dirty
	ret
.line_start:
	LD_HL_VAR ed_line
	ld a, h
	or l
	ret z
	dec hl
	call ed_line_start
	ST_HL_VAR ed_idx
	call ed_line_len
	push bc
	LD_HL_VAR ed_idx
	pop de
	add hl, de          ; newline at the end of the previous line
	call ed_delete_at
	LD_HL_VAR ed_line
	dec hl
	ST_HL_VAR ed_line
	LD_HL_VAR ed_idx
	call ed_line_len
	ST_BC_VAR ed_col
	call ed_mark_dirty
	ret

; ed_clamp_col:: clamp ed_col to the line length in bc.
ed_clamp_col:
	LD_HL_VAR ed_col
	ld a, h
	cp b
	jr c, .ok
	jr nz, .set
	ld a, l
	cp c
	jr c, .ok
.set:
	ld h, b
	ld l, c
.ok:
	ST_HL_VAR ed_col
	ret

; ---- cursor movement -------------------------------------------------

ed_move_left:
	LD_HL_VAR ed_col
	ld a, h
	or l
	jr z, .prev_line
	dec hl
	ST_HL_VAR ed_col
	ret
.prev_line:
	LD_HL_VAR ed_line
	ld a, h
	or l
	ret z
	dec hl
	ST_HL_VAR ed_line
	call ed_line_start
	call ed_line_len
	ST_BC_VAR ed_col
	ret

ed_move_right:
	LD_HL_VAR ed_line
	call ed_line_start
	call ed_line_len
	LD_HL_VAR ed_col
	ld a, h
	cp b
	jr c, .inc
	jr nz, .newline
	ld a, l
	cp c
	jr c, .inc
.newline:
	call ed_cur_idx
	call ed_hl_ge_len
	ret c
	call ed_ptr_add
	ld a, [hl]
	cp $0A
	ret nz
	LD_HL_VAR ed_line
	inc hl
	ST_HL_VAR ed_line
	xor a
	ld [ed_col], a
	ld [ed_col+1], a
	ret
.inc:
	LD_HL_VAR ed_col
	inc hl
	ST_HL_VAR ed_col
	ret

ed_move_up:
	LD_HL_VAR ed_line
	ld a, h
	or l
	ret z
	dec hl
	ST_HL_VAR ed_line
	call ed_line_start
	call ed_line_len
	jp ed_clamp_col

ed_move_down:
	LD_HL_VAR ed_line
	call ed_line_start
	ST_HL_VAR ed_idx
	call ed_line_len
	; end = line start + length
	LD_HL_VAR ed_idx
	ld d, b
	ld e, c
	add hl, de
	; no next line when end >= ed_len
	LD_DE_VAR ed_len
	ld a, h
	cp d
	jr c, .next
	jr nz, .ret
	ld a, l
	cp e
	jr nc, .ret
.next:
	LD_HL_VAR ed_line
	inc hl
	ST_HL_VAR ed_line
	call ed_line_start
	call ed_line_len
	jp ed_clamp_col
.ret:
	ret

; ---- saving ----------------------------------------------------------

; ed_store_size:: write ed_len to the current node's size field.
ed_store_size:
	ld a, [ed_node]
	call fs_node_addr
	ld bc, N_SIZE
	add hl, bc
	ld a, [ed_len]
	ld [hl+], a
	ld a, [ed_len+1]
	ld [hl], a
	ret

; ed_store_data_size:: write de as data and ed_len as size.
ed_store_data_size:
	ld a, [ed_node]
	call fs_node_addr
	ld bc, N_DATA
	add hl, bc
	ld a, e
	ld [hl+], a
	ld a, d
	ld [hl], a
	jp ed_store_size

; ed_save_file:: write ed_buf back to the current file. CF set on error.
ed_save_file:
	ld a, [ed_node]
	call fs_node_addr
	ld a, [hl]
	cp N_FILE
	jp nz, .eperm
	push hl
	ld de, N_ATTRS
	add hl, de
	bit 0, [hl]
	pop hl
	jr z, .eperm
	; old size -> bc, old data -> de
	push hl
	ld de, N_SIZE
	add hl, de
	ld a, [hl+]
	ld c, a
	ld a, [hl]
	ld b, a
	pop hl
	push hl
	ld de, N_DATA
	add hl, de
	ld a, [hl+]
	ld e, a
	ld a, [hl]
	ld d, a
	pop hl
	; does the new text fit in the old allocation?
	ld a, [ed_len+1]
	cp b
	jr c, .fits
	jr nz, .alloc
	ld a, [ed_len]
	cp c
	jr c, .fits
	jr z, .fits
.alloc:
	; de currently holds the old data pointer; it stays leaked
	ld a, [ed_len]
	ld c, a
	ld a, [ed_len+1]
	ld b, a
	ld a, b
	or c
	jr z, .zero
	call heap_alloc
	jr c, .full
	; de = new data; copy the buffer there
	push de
	ld a, [ed_len]
	ld c, a
	ld a, [ed_len+1]
	ld b, a
	ld hl, ed_buf
	call mem_copy
	pop de
	call ed_store_data_size
	xor a
	ld [ed_dirty], a
	or a
	ret
.fits:
	ld a, [ed_len]
	or a
	jr nz, .copy_fits
	ld a, [ed_len+1]
	or a
	jr z, .zero
.copy_fits:
	; de = old data; copy ed_len bytes in place
	push de
	ld a, [ed_len]
	ld c, a
	ld a, [ed_len+1]
	ld b, a
	ld hl, ed_buf
	call mem_copy
	pop de
	call ed_store_size
	xor a
	ld [ed_dirty], a
	or a
	ret
.zero:
	call ed_store_size
	xor a
	ld [ed_dirty], a
	or a
	ret
.eperm:
	ld a, FS_E_EPERM
	jr .err
.full:
	ld a, FS_E_FULL
.err:
	ld [fs_errno], a
	scf
	ret

; ---- status / exits --------------------------------------------------

; ed_show_msg:: print a zero-terminated message on the second hint row.
ed_show_msg:
	push hl
	ld a, ED_HINT2_ROW
	call txt_clear_row
	ld a, ED_HINT2_ROW
	ld c, 0
	call txt_goto
	pop hl
	ld b, SCREEN_W
.loop:
	ld a, [hl]
	or a
	ret z
	call txt_putc
	inc hl
	dec b
	jr nz, .loop
	ret

ed_show_save_error:
	ld a, [fs_errno]
	cp FS_E_EPERM
	jr z, .eperm
	cp FS_E_FULL
	jr z, .full
	ld hl, str_ed_save_failed
	jr ed_show_msg
.eperm:
	ld hl, str_ed_readonly
	jr ed_show_msg
.full:
	ld hl, str_ed_nospace
	jr ed_show_msg

editor_save:
	call ed_save_file
	jr nc, .ok
	call ed_show_save_error
	ret
.ok:
	jp shell_enter

editor_abort:
	jp shell_enter

; ---- input -----------------------------------------------------------

; ed_b_held:: Z set unless B was pressed and is still held.
ed_b_held:
	ld a, [ed_b_armed]
	or a
	ret z
	ld a, [joy_held]
	and J_B
	ret

editor_update::
	; SELECT+START abandons the editor
	ld a, [joy_held]
	and J_SELECT | J_START
	cp J_SELECT | J_START
	jp z, editor_abort
	; remember a fresh B press so release can mean backspace
	ld a, [joy_pressed]
	and J_B
	jr z, .b_release
	ld a, 1
	ld [ed_b_armed], a
	xor a
	ld [ed_b_combo], a
.b_release:
	ld a, [joy_released]
	and J_B
	jr z, .start
	ld a, [ed_b_armed]
	or a
	jr z, .start
	xor a
	ld [ed_b_armed], a
	ld a, [ed_b_combo]
	or a
	jr nz, .combo_consumed
	call ed_backspace
	call editor_render
	ret
.combo_consumed:
	xor a
	ld [ed_b_combo], a
	ret
.start:
	ld a, [joy_pressed]
	and J_START
	jr z, .select
	jp editor_save
.select:
	ld a, [joy_pressed]
	and J_SELECT
	jr z, .up
	ld a, [shift_on]
	xor 1
	ld [shift_on], a
	call shell_render_kb
.up:
	ld a, [joy_pressed]
	and J_UP
	jr z, .down
	call ed_b_held
	jr z, .kb_up
	call ed_move_up
	ld a, 1
	ld [ed_b_combo], a
	call editor_render
	ret
.kb_up:
	jp kb_move_up
.down:
	ld a, [joy_pressed]
	and J_DOWN
	jr z, .left
	call ed_b_held
	jr z, .kb_down
	call ed_move_down
	ld a, 1
	ld [ed_b_combo], a
	call editor_render
	ret
.kb_down:
	jp kb_move_down
.left:
	ld a, [joy_pressed]
	and J_LEFT
	jr z, .right
	call ed_b_held
	jr z, .kb_left
	call ed_move_left
	ld a, 1
	ld [ed_b_combo], a
	call editor_render
	ret
.kb_left:
	jp kb_move_left
.right:
	ld a, [joy_pressed]
	and J_RIGHT
	jr z, .a
	call ed_b_held
	jr z, .kb_right
	call ed_move_right
	ld a, 1
	ld [ed_b_combo], a
	call editor_render
	ret
.kb_right:
	jp kb_move_right
.a:
	ld a, [joy_pressed]
	and J_A
	ret z
	call ed_b_held
	jr z, .type_char
	call ed_newline
	jr c, .full
	ld a, 1
	ld [ed_b_combo], a
	call editor_render
	ret
.type_char:
	ld a, [kb_row]
	ld b, a
	ld a, [kb_col]
	ld c, a
	call kb_char
	call ed_type_char
	jr c, .full
	call editor_render
	ret
.full:
	ld hl, str_ed_full
	jp ed_show_msg

str_ed_full:        db "buffer full", 0
str_ed_save_failed: db "save failed", 0
str_ed_readonly:    db "read-only file", 0
str_ed_nospace:     db "no space left", 0

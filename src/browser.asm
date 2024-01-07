; browser.asm — file browser mode (ls-style listing)

include "hardware.inc"
include "fs.inc"

def LIST_ROWS    equ 16          ; visible entries (screen rows 1-16)

section "browserw", wram0

list_offset::   db              ; first visible entry index
list_cursor::   db              ; cursor row (0..LIST_ROWS-1)
long_mode::     db              ; 0 = names, 1 = ls -l style
sel_node::      db              ; node under cursor, $FF = none
b_combo::       db              ; B held while a dpad jump fired
b_armed::       db              ; B press started in the browser

section "browser", rom0

browser_enter::
	xor a
	ld [list_offset], a
	ld [list_cursor], a
	ld [long_mode], a
	ld [b_combo], a
	ld [b_armed], a
	; fallthrough
browser_refresh::                   ; re-list cwd and redraw everything
	xor a
	ld [list_offset], a
	ld [list_cursor], a
	call fs_get_cwd
	call fs_list
	jp browser_render

; browser_render:: full redraw of the browser screen.
browser_render::
	call txt_clear
	xor a
	ld c, 0
	call txt_goto
	call fs_get_cwd
	call fs_pwd_str
	call print_cwd_header
	call browser_draw_entries
	jp browser_light

; print_cwd_header:: print cwd path truncated to 20 cols.
print_cwd_header::
	ld hl, pwd_buf
	call strlen_hl
	ld a, b
	cp SCREEN_W
	jr c, .full
	; too long: ".." + last 18 chars
	ld hl, pwd_buf
	ld a, b
	sub SCREEN_W - 2
	ld e, a
	ld d, 0
	add hl, de
	ld a, '.'
	call txt_putc
	ld a, '.'
	call txt_putc
	call txt_print_z
	ret
.full:
	ld hl, pwd_buf
	call txt_print_z
	ret

; browser_draw_entries:: redraw rows 1-16 from list_offset.
browser_draw_entries::
	ld a, 1
	ld [scr_full], a    ; 16 rows change at once: redraw atomically
	ld c, 1             ; c = screen row
.row:
	push bc
	ld a, c
	call txt_clear_row
	pop bc
	; entry index = offset + (c - 1)
	push bc
	ld a, c
	dec a
	ld e, a
	ld a, [list_offset]
	add e
	ld e, a
	ld a, [list_count]
	cp e
	jr c, .skip
	jr z, .skip
	ld a, c
	ld c, 0
	call txt_goto
	ld d, 0
	ld hl, list_entries
	add hl, de
	ld a, [hl]
	call browser_print_entry
.skip:
	pop bc
	inc c
	ld a, c
	cp 1 + LIST_ROWS
	jr c, .row
	ret

; browser_print_entry:: print one entry at cursor. a = node.
browser_print_entry::
	ld [fs_tmp], a
	call fs_node_addr
	ld a, [hl]          ; type
	ld [fs_prev], a
	inc hl
	push hl             ; name
	ld a, [long_mode]
	or a
	jr z, .name_short
	; long mode: perms + space + name[:9]
	ld a, [fs_prev]
	ld hl, perms_dir
	cp N_DIR
	jr z, .p
	ld hl, perms_file
.p:
	call txt_print_z
	ld a, ' '
	call txt_putc
	pop hl
	call txt_print_z
	jr .maybe_slash
.name_short:
	pop hl
	call txt_print_z
.maybe_slash:
	ld a, [long_mode]
	or a
	ret nz              ; long mode: perms already show d, no room for /
	ld a, [fs_prev]
	cp N_DIR
	ret nz
	ld a, '/'
	jp txt_putc

; browser_light:: redraw footer + cursor highlight + sel_node.
browser_light::
	; un-highlight the previous cursor row (it must be redrawn normal)
	ld a, [invert_row]
	cp $FF
	jr z, .no_old_hl
	ld e, a
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
.no_old_hl:
	; compute sel_node FIRST so the footer shows the current selection
	ld a, [list_count]
	or a
	jr z, .none
	call browser_sel_idx
	ld e, a
	ld d, 0
	ld hl, list_entries
	add hl, de
	ld a, [hl]
	jr .set
.none:
	ld a, $FF
.set:
	ld [sel_node], a
	call browser_draw_footer
	; highlight row = cursor screen row
	ld a, [sel_node]
	cp $FF
	ld a, $FF
	jr z, .inv
	ld a, [list_cursor]
	inc a
.inv:
	ld [invert_row], a
	cp $FF
	ret z
	ld e, a
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	ret

; browser_sel_idx:: a = absolute index under cursor (offset + cursor).
browser_sel_idx::
	ld a, [list_offset]
	ld e, a
	ld a, [list_cursor]
	add e
	ret

; browser_draw_footer:: redraw screen row 17 with selected entry info.
browser_draw_footer::
	ld a, SCREEN_H - 1
	call txt_clear_row  ; fill row 17 with spaces (no cursor advance/wrap)
	ld a, SCREEN_H - 1
	ld c, 0
	call txt_goto
	ld a, [list_count]
	or a
	jr z, .empty
	ld a, [sel_node]
	call fs_node_addr
	push hl             ; node base
	inc hl
	call txt_print_z
	ld a, ' '
	call txt_putc
	pop hl
	ld a, [hl]
	cp N_DIR
	jr z, .dir_info
	; file: size + (ro|rw)
	ld a, [sel_node]
	call fs_node_addr
	ld bc, N_SIZE
	add hl, bc
	ld a, [hl+]
	ld e, a
	ld a, [hl]
	ld d, a
	push de
	pop hl
	call txt_print_u16
	ld a, 'B'
	call txt_putc
	ld a, [sel_node]
	call fs_node_addr
	ld bc, N_ATTRS
	add hl, bc
	ld a, [hl]
	and 1
	ld hl, str_ro
	or a
	jr z, .p_rw
	ld hl, str_rw
.p_rw:
	call txt_print_z
	ret
.dir_info:
	ld a, [sel_node]
	call fs_count_children
	ld h, 0
	ld l, a
	call txt_print_u16
	ld a, ' '
	call txt_putc
	ld hl, str_items
	call txt_print_z
	ret
.empty:
	ld hl, str_empty
	call txt_print_z
	ret

; browser_update:: handle input (joy_pressed already fresh).
browser_update::
	; SELECT+START opens the key help (fresh press of either key, both held)
	ld a, [joy_pressed]
	and J_SELECT | J_START
	jr z, .no_help
	ld a, [joy_held]
	and J_SELECT | J_START
	cp J_SELECT | J_START
	jp z, help_enter
.no_help:
	; a B press that started in the browser is a tap candidate
	ld a, [joy_pressed]
	and J_B
	jr z, .b_press_done
	ld a, 1
	ld [b_armed], a
	xor a
	ld [b_combo], a
.b_press_done:
	; B acts on release, so B + dpad can jump without also going up a dir
	ld a, [joy_released]
	and J_B
	jr z, .keys
	ld a, [b_armed]
	or a
	jr z, .keys         ; B was pressed in another mode (pager close)
	xor a
	ld [b_armed], a
	ld a, [b_combo]
	or a
	jr nz, .combo_done
	ld a, [cwd_depth]
	or a
	jr z, .keys
	call fs_get_cwd
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld a, [hl]
	call fs_set_cwd
	call browser_refresh
	ret
.combo_done:
	xor a
	ld [b_combo], a
	ret
.keys:
	ld a, [joy_pressed]
	and J_UP
	jp nz, .up
	ld a, [joy_pressed]
	and J_DOWN
	jp nz, .down
	ld a, [joy_pressed]
	and J_LEFT
	jp nz, .left
	ld a, [joy_pressed]
	and J_RIGHT
	jp nz, .right
	ld a, [joy_pressed]
	and J_A
	jp nz, .a_key
	ld a, [joy_pressed]
	and J_START
	jp nz, .start_key
	ld a, [joy_pressed]
	and J_SELECT
	jp nz, .select_key
	ret
.up:
	ld a, [b_armed]
	or a
	jr z, .up_move
	ld a, [joy_held]
	and J_B
	jr nz, .jump_root
.up_move:
	call browser_sel_idx
	or a
	ret z
	ld a, [list_cursor]
	or a
	jr z, .up_page
	dec a
	ld [list_cursor], a
	jp browser_light
.up_page:
	ld a, [list_offset]
	dec a
	ld [list_offset], a
	jp .redraw
.jump_root:
	ld a, 1
	ld [b_combo], a
	xor a
	call fs_set_cwd
	jp browser_refresh
.down:
	ld a, [b_armed]
	or a
	jr z, .down_move
	ld a, [joy_held]
	and J_B
	jr nz, .jump_home
.down_move:
	call browser_sel_idx
	ld e, a
	ld a, [list_count]
	dec a
	cp e
	ret z               ; already at last entry
	ret c               ; past last entry (defensive)
	ld a, [list_cursor]
	cp LIST_ROWS - 1
	jr z, .down_page
	inc a
	ld [list_cursor], a
	jp browser_light
.down_page:
	ld a, [list_offset]
	inc a
	ld [list_offset], a
	jp .redraw
.jump_home:
	ld a, 1
	ld [b_combo], a
	ld de, str_home_dir
	call fs_resolve
	cp $FF
	ret z
	call fs_set_cwd
	jp browser_refresh
.left:
	ld a, [list_offset]
	or a
	ret z
	sub 16
	jr nc, .l_ok
	xor a
.l_ok:
	ld [list_offset], a
	jp .redraw
.right:
	ld a, [list_count]
	dec a
	cp 16
	jr c, .r_zero       ; single page
	sub 15              ; max offset = count - 16
	ld d, a
	ld a, [list_offset]
	add 16
	cp d
	jr c, .r_ok
	jr z, .r_ok
	ld a, d
.r_ok:
	ld [list_offset], a
	jp .redraw
.r_zero:
	ret
.a_key:
	ld a, [sel_node]
	cp $FF
	ret z
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr z, .enter_dir
	ld a, [sel_node]
	jp pager_open
.enter_dir:
	ld a, [sel_node]
	call fs_set_cwd
	jp browser_refresh
.start_key:
	jp shell_enter
.select_key:
	ld a, [long_mode]
	cpl
	ld [long_mode], a
	call browser_draw_entries
	jp browser_light
.redraw:
	call browser_draw_entries
	call browser_fix_cursor
	jp browser_light

; browser_fix_cursor:: keep cursor/selection consistent after page scroll.
browser_fix_cursor::
	ld a, [list_offset]
	ld e, a             ; e = offset
	ld a, [list_cursor]
	add e               ; a = sel
	ld c, a
	ld a, [list_count]
	dec a
	cp c
	jr nc, .in_range
	ld c, a             ; clamp sel to count-1
.in_range:
	ld a, c
	sub e               ; cursor = sel - offset
	jr nc, .c_ok
	xor a
.c_ok:
	cp LIST_ROWS - 1
	jr c, .c_set
	ld a, LIST_ROWS - 1
.c_set:
	ld [list_cursor], a
	ret

perms_dir::     db "drwxr-xr-x", 0
perms_file::    db "-rw-r--r--", 0
str_ro:         db " ro", 0
str_rw:         db " rw", 0
str_items:      db "items", 0
str_home_dir:   db "/home/user", 0
str_empty:      db "empty", 0

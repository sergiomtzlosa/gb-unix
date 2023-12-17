; shell.asm — gbsh: mini shell with tokenizer + command table

include "hardware.inc"
include "fs.inc"

def SH_INPUT_MAX equ 30
def TERM_BOT     equ 10          ; last terminal row (input line is row 11)

section "shellw2", wram0

sh_input::      ds SH_INPUT_MAX + 2
sh_len::        db
sh_argc::
_sh_argc::      db
sh_args::
_sh_args::      ds 8            ; up to 4 zstr pointers
sh_cmd_buf::    ds 12           ; lower-cased command name
sh_wr_idx::     db              ; echo > file: filename arg index
sh_used::       db              ; 1 once a character has been typed
sh_promptbuf::  ds 14
echo_buf::      ds 34
ls_long::       db              ; h_ls -l flag (scratch)

section "shell", rom0

; ---- entry / rendering ------------------------------------------------

shell_enter::
	ld a, MODE_SHELL
	ld [mode], a
	ld a, $FF
	ld [invert_row], a
	xor a
	ld [scr_top], a
	ld [sh_len], a      ; clear input length FIRST (a is clobbered below)
	ld a, TERM_BOT
	ld [scr_bot], a
	xor a
	ld [sh_used], a
	call kb_reset
	call txt_clear
	ld hl, sh_banner
	call txt_print_z
	call shell_set_prompt
	call shell_render_input
	call shell_render_kb
	ret

; shell_set_prompt:: build "<cwd>$ " (full path when it fits, else basename).
shell_set_prompt::
	; prefer the full path when it fits the 14-byte prompt buffer
	call fs_get_cwd
	call fs_pwd_str
	ld hl, pwd_buf
	call strlen_hl
	ld a, b
	cp 12               ; path + "$ " + NUL must fit in 14 bytes
	jr nc, .basename
	ld hl, pwd_buf
	ld de, sh_promptbuf
.cp_path:
	ld a, [hl+]
	ld [de], a
	inc de
	or a
	jr nz, .cp_path
	dec de
	ld hl, str_prompt_tail
	ld a, [hl+]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	xor a
	ld [de], a
	ret
.basename:
	call fs_get_cwd
	or a
	jr nz, .named
	ld hl, str_root_prompt
	ld de, sh_promptbuf
	ld bc, 4
	call mem_copy
	ret
.named:
	ld [fs_tmp], a
	call fs_node_addr
	inc hl              ; name
	ld de, sh_promptbuf
.cp:
	ld a, [hl+]
	ld [de], a
	inc de
	or a
	jr nz, .cp
	dec de
	ld hl, str_prompt_tail
	ld a, [hl+]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	xor a
	ld [de], a
	ret

; shell_render_input:: redraw row 11: prompt + input tail + block cursor.
shell_render_input::
	ld a, TERM_BOT + 1
	call txt_clear_row  ; fill row 11 with spaces (no cursor advance/wrap)
	ld a, TERM_BOT + 1
	ld c, 0
	call txt_goto
	ld hl, sh_promptbuf
	call txt_print_z
	; available input columns = 19 - prompt length
	ld hl, sh_promptbuf
	call strlen_hl
	ld a, SCREEN_W - 1
	sub b
	ld [fs_tmp2], a     ; avail
	; start = max(0, sh_len - avail)
	ld a, [fs_tmp2]     ; c = avail
	ld c, a
	ld a, [sh_len]
	sub c               ; a = sh_len - avail
	jr nc, .st
	xor a
.st:
	ld c, a             ; c = start
	ld a, [sh_len]
	sub c
	ld [fs_tmp2], a     ; count
	; hl = sh_input + start
	ld a, c
	ld e, a
	ld d, 0
	ld hl, sh_input
	add hl, de
	ld a, [fs_tmp2]
	ld d, a             ; d = count
.pr:
	ld a, d
	or a
	jr z, .cursor
	ld a, [hl+]
	call txt_putc
	dec d
	jr .pr
.cursor:
	; block cursor at current column (inverted space tile)
	ld a, [cur_col]
	ld e, a
	ld d, 0
	ld hl, screen_buf + TERM_BOT * SCREEN_W + SCREEN_W
	add hl, de
	ld [hl], 95         ; inverted space
	ld e, TERM_BOT + 1
	ld d, 0
	ld hl, dirty_rows
	add hl, de
	ld [hl], 1
	; empty line: remind how to execute it (skip if the prompt is long)
	ld a, [sh_len]
	or a
	ret nz
	ld hl, sh_promptbuf
	call strlen_hl
	ld a, b
	cp 10
	ret nc
	ld a, TERM_BOT + 1
	ld c, 10
	call txt_goto
	ld hl, str_run_hint
	call txt_print_z
	ret

; ---- tokenizing -------------------------------------------------------

; sh_tokenize:: split sh_input into up to 4 space-separated tokens.
sh_tokenize::
	xor a
	ld [sh_argc], a
	ld hl, sh_input
.loop:
	ld a, [hl]
	or a
	ret z
	cp ' '
	jr nz, .tok_start
	inc hl
	jr .loop
.tok_start:
	ld a, [sh_argc]
	cp 4
	ret nc
	push hl             ; token start
	ld a, [sh_argc]
	add a, a            ; 2 bytes per pointer
	ld e, a
	ld d, 0
	ld bc, sh_args
	push bc
	pop hl              ; hl = sh_args
	add hl, de          ; hl = &args[argc]
	pop de              ; de = token start
	ld [hl], e
	inc hl
	ld [hl], d
	ld a, [sh_argc]
	inc a
	ld [sh_argc], a
	ld l, e
	ld h, d
.scan:
	ld a, [hl]
	or a
	ret z               ; NUL ends token and input
	cp ' '
	jr z, .cut
	inc hl
	jr .scan
.cut:
	xor a
	ld [hl+], a         ; terminate token
	jr .loop

; sh_arg_hl:: a = arg index (0-3) -> hl = argument pointer.
sh_arg_hl::
	add a, a
	ld e, a
	ld d, 0
	ld hl, sh_args
	add hl, de
	ld a, [hl+]
	ld h, [hl]
	ld l, a
	ret

; sh_arg_de:: a = arg index -> de = argument pointer.
sh_arg_de::
	call sh_arg_hl
	ld e, l
	ld d, h
	ret

; ---- dispatch ---------------------------------------------------------

; sh_exec:: run command in args[0] (case-insensitive).
sh_exec::
	ld a, [sh_argc]
	or a
	ret z
	ld a, [sh_args]
	ld e, a
	ld a, [sh_args+1]
	ld d, a             ; de = arg0
	; "/bin/pwd", "./ls" or "bin/cd" run the built-in named after the
	; last path component, so the binaries in /bin are runnable by path
	ld h, d
	ld l, e
.scan_slash:
	ld a, [hl]
	or a
	jr z, .scan_done
	cp '/'
	jr nz, .scan_next
	ld d, h
	ld e, l
	inc de              ; de = candidate after this slash
.scan_next:
	inc hl
	jr .scan_slash
.scan_done:
	; fold A-Z to a-z so PWD == pwd on the on-screen keyboard
	ld hl, sh_cmd_buf
	ld c, 11
.fold:
	ld a, [de]
	inc de
	or a
	jr z, .fold_end
	cp 'A'
	jr c, .fold_st
	cp 'Z' + 1
	jr nc, .fold_st
	add 'a' - 'A'
.fold_st:
	ld [hl+], a
	dec c
	jr nz, .fold
	xor a
.fold_end:
	ld [hl], a
	ld de, sh_cmd_buf
	ld hl, sh_cmds
.search:
	ld a, [hl+]
	ld c, a
	ld a, [hl+]
	ld b, a             ; bc = name ptr
	ld a, b
	or c
	jr z, .not_found    ; end of table
	push hl
	push de
	push bc
	pop hl              ; hl = name
	call strcmp_z
	pop de
	pop hl
	jr z, .found
	inc hl
	inc hl
	jr .search
.not_found:
	ld hl, str_not_found
	call txt_print_z
	ld a, [sh_args]
	ld e, a
	ld a, [sh_args+1]
	ld d, a
	ld h, d
	ld l, e
	call txt_print_z
	ld a, $0A
	call txt_putc
	jp sh_suggest

.found:
	ld a, [hl+]
	ld c, a
	ld a, [hl]
	ld b, a
	push bc
	ret

; sh_suggest:: if arg0 is one letter away from a known command, hint it.
; A one-key slip on the on-screen keyboard (e.g. "ped" for "pwd") otherwise
; looks like the command ran and printed nothing.
sh_suggest:
	ld de, sh_cmd_buf
	ld hl, sh_cmds
.loop:
	ld a, [hl+]
	ld c, a
	ld a, [hl+]
	ld b, a
	ld a, b
	or c
	ret z               ; end of table: no suggestion
	push hl
	push de
	push bc
	call sh_one_off     ; de = typed, bc = name -> z if one mismatch
	pop bc
	pop de
	pop hl
	jr nz, .next
	ld hl, str_did_mean
	call txt_print_z
	ld h, b
	ld l, c
	call txt_print_z
	ld a, $0A
	jp txt_putc
.next:
	inc hl
	inc hl
	jr .loop

; sh_one_off:: z if zstrs de and bc have equal length and differ in exactly
; one position. Clobbers a, b, c, hl, de (callers restore what they need).
sh_one_off:
	ld h, b
	ld l, c             ; hl = name
	ld c, 0             ; c = differing positions
.loop:
	ld a, [de]
	ld b, [hl]
	or b
	jr z, .done         ; both strings ended together
	ld a, [de]
	or a
	jr z, .no           ; typed is longer
	ld a, [hl]
	or a
	jr z, .no           ; name is longer
	ld a, [de]
	cp b
	jr z, .same
	inc c
	ld a, c
	cp 2
	jr nc, .no          ; two or more differences
.same:
	inc de
	inc hl
	jr .loop
.done:
	ld a, c
	cp 1
	ret
.no:
	ld a, 1
	or a
	ret

; ---- error printing ---------------------------------------------------

; sh_err_print:: print "error: <message>" for current fs_errno.
sh_err_print::
	push af
	ld hl, str_err
	call txt_print_z
	ld a, [fs_errno]
	call fs_err_str
	call txt_print_z
	ld a, $0A
	call txt_putc
	pop af
	ret

; ---- input handling ---------------------------------------------------

shell_update::
	; SELECT+START leaves the shell (fresh press of either key, both held)
	ld a, [joy_pressed]
	and J_SELECT | J_START
	jr z, .no_back
	ld a, [joy_held]
	and J_SELECT | J_START
	cp J_SELECT | J_START
	jp z, h_exit
.no_back:
	ld a, [joy_pressed]
	and J_UP
	jp nz, .kb_up
	ld a, [joy_pressed]
	and J_DOWN
	jp nz, .kb_down
	ld a, [joy_pressed]
	and J_LEFT
	jp nz, .kb_left
	ld a, [joy_pressed]
	and J_RIGHT
	jp nz, .kb_right
	ld a, [joy_pressed]
	and J_A
	jp nz, .key_a
	ld a, [joy_pressed]
	and J_B
	jp nz, .key_b
	ld a, [joy_pressed]
	and J_START
	jp nz, .key_start
	ld a, [joy_pressed]
	and J_SELECT
	jp nz, .key_select
	ret
.kb_up:
	call kb_clear_cell
	ld a, [kb_row]
	or a
	jr nz, .u
	ld a, KB_ROWS
.u:
	dec a
	ld [kb_row], a
	call kb_draw_cell
	ret
.kb_down:
	call kb_clear_cell
	ld a, [kb_row]
	inc a
	cp KB_ROWS
	jr c, .d
	xor a
.d:
	ld [kb_row], a
	call kb_draw_cell
	ret
.kb_left:
	call kb_clear_cell
	ld a, [kb_col]
	or a
	jr nz, .l
	ld a, KB_COLS
.l:
	dec a
	ld [kb_col], a
	call kb_draw_cell
	ret
.kb_right:
	call kb_clear_cell
	ld a, [kb_col]
	inc a
	cp KB_COLS
	jr c, .r
	xor a
.r:
	ld [kb_col], a
	call kb_draw_cell
	ret
.key_a:
	ld a, [kb_row]
	ld b, a
	ld a, [kb_col]
	ld c, a
	call kb_char
	ld e, a             ; char
	ld a, [sh_len]
	cp SH_INPUT_MAX
	ret nc
	ld l, a
	ld h, 0
	ld bc, sh_input
	add hl, bc
	ld [hl], e
	inc hl
	xor a
	ld [hl], a          ; terminate
	ld a, [sh_len]
	inc a
	ld [sh_len], a
	ld a, 1
	ld [sh_used], a
	call shell_render_input
	ret
.key_b:
	ld a, [sh_len]
	or a
	ret z
	dec a
	ld [sh_len], a
	ld l, a
	ld h, 0
	ld bc, sh_input
	add hl, bc
	xor a
	ld [hl], a
	call shell_render_input
	ret
.key_start:
	; terminate input
	ld a, [sh_len]
	ld l, a
	ld h, 0
	ld bc, sh_input
	add hl, bc
	xor a
	ld [hl], a
	; echo command line into terminal
	; cursor position is preserved from previous command's output,
	; but may be on row 11 if this is the first command after shell_enter
	ld a, [cur_row]
	cp TERM_BOT + 1
	jr c, .print_command
	; cursor is on UI row 11, need to move it back into scrolling region
	; use row 10 col 0 as a safe starting point
	ld a, TERM_BOT
	ld [cur_row], a
	xor a
	ld [cur_col], a
.print_command:
	; a mid-line cursor (previous output left without a trailing newline)
	; would merge the echoed command into that output and clobber it:
	; always start the echoed line on a fresh line
	ld a, [cur_col]
	or a
	jr z, .echo
	ld a, $0A
	call txt_putc
.echo:
	ld hl, sh_promptbuf
	call txt_print_z
	ld hl, sh_input
	call txt_print_z
	ld a, $0A
	call txt_putc
	; first run with nothing typed: explain the on-screen keyboard
	ld a, [sh_len]
	or a
	jr nz, .kb_hint_done
	ld a, [sh_used]
	or a
	jr nz, .kb_hint_done
	ld hl, str_typing_hint
	call txt_print_z
.kb_hint_done:
	; execute
	call sh_tokenize
	call sh_exec
	; a command may have left the shell (exit -> splash); do not redraw the
	; shell input line over the title screen
	ld a, [mode]
	cp MODE_SHELL
	ret nz
	; save terminal cursor position before rendering input UI
	ld a, [cur_row]
	push af
	ld a, [cur_col]
	push af
	xor a
	ld [sh_len], a
	call shell_render_input
	; restore terminal cursor position
	pop af
	ld [cur_col], a
	pop af
	ld [cur_row], a
	; guarantee the command's output reaches the screen atomically: the
	; next VBlank does one full LCD-off redraw of every dirty row (the
	; same path the browser's big redraws use) instead of spreading the
	; update over several budgeted partial blits
	ld a, 1
	ld [scr_full], a
	ret
.key_select:
	ld a, [shift_on]
	cpl
	ld [shift_on], a
	call shell_render_kb
	ret

; ---- path creation ----------------------------------------------------

; sh_create_path:: create a file/dir at a path (supports dirs in path).
; in:  de = path zstr, b = type (N_FILE/N_DIR), hl = content zstr ($0000=none)
; out: CF clear = ok, CF set = failed (fs_errno set)
sh_create_path::
	ld a, l
	ld [fs_content], a
	ld a, h
	ld [fs_content+1], a
	; copy path into fs_path_buf
	push de
	ld hl, fs_path_buf
.cp:
	ld a, [de]
	ld [hl+], a
	inc de
	or a
	jr nz, .cp
	pop de
	; find last '/'
	ld hl, fs_path_buf
	ld de, $0000        ; last slash ptr (0 = none)
.scan:
	ld a, [hl]
	or a
	jr z, .found
	cp '/'
	jr nz, .next
	ld e, l
	ld d, h
.next:
	inc hl
	jr .scan
.found:
	ld a, d
	or e
	jr nz, .slash
	; no slash: parent = cwd, name = whole path
	call fs_get_cwd
	ld de, fs_path_buf
	push de
	jp .create
.slash:
	; terminate prefix at slash
	ld h, d
	ld l, e
	ld [hl], 0
	inc hl
	push hl             ; name ptr
	; resolve prefix ("/..." at start -> root)
	ld a, e
	cp fs_path_buf & $FF
	jr nz, .res
	xor a               ; leading slash: parent is root
	jp .create
.res:
	ld de, fs_path_buf
	call fs_resolve
	cp $FF
	jp z, .err_pop
	; fallthrough with a = parent
.create:
	pop de              ; name
	call fs_create      ; a = parent, de = name, b = type
	cp $FF
	jr nz, .created
	; already exists? an "echo ... > file" redirect overwrites the content
	ld a, [fs_errno]
	cp FS_E_EXISTS
	jr nz, .err
	ld a, [fs_content]
	ld hl, fs_content + 1
	or [hl]
	jr z, .err
	ld a, [fs_par_parent]
	ld de, fs_name_buf
	call fs_get_child
	cp $FF
	jr z, .err
	push af
	call fs_node_addr
	ld a, [hl]
	cp N_FILE
	jr nz, .exists_dir
	; ROM files (attrs bit0 = 0) cannot be overwritten
	push hl
	REPT N_ATTRS
	inc hl
	ENDR
	bit 0, [hl]
	pop hl
	jr nz, .overwrite
	pop af
	ld a, FS_E_EPERM
	ld [fs_errno], a
	scf
	ret
.overwrite:
	pop af
.created:
	ld [fs_tmp], a
	ld a, [fs_content]
	ld l, a
	ld a, [fs_content+1]
	ld h, a
	ld a, h
	or l
	jr z, .ok
	ld a, [fs_tmp]
	call fs_write_new
	jp nc, .ok
	ld a, FS_E_FULL
	ld [fs_errno], a
	scf
	ret
.exists_dir:
	pop af
.err:
	scf
	ret
.ok:
	or a
	ret
.err_pop:
	pop hl              ; discard value
	scf
	ret

; ---- commands ---------------------------------------------------------

h_help::
	call h_clear         ; full 10-line help must fit the 11-row terminal
	ld hl, txt_help
	jp txt_print_z

h_ls::
	xor a
	ld [ls_long], a
	ld a, [sh_argc]
	cp 2
	jr c, .cwd
	; arg1 == "-l"?
	ld a, 1
	call sh_arg_hl
	push hl
	ld de, str_dashl
	call strcmp_z
	pop hl
	jr nz, .path1
	ld a, 1
	ld [ls_long], a
	ld a, [sh_argc]
	cp 3
	jr c, .cwd
	ld a, 2
	call sh_arg_de
	jr .resolve
.path1:
	ld a, 1
	call sh_arg_de
.resolve:
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	ld [fs_tmp], a
	jr .have
.cwd:
	call fs_get_cwd
	ld [fs_tmp], a
.have:
	ld a, [fs_tmp]
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr z, .dir
	inc hl
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret
.dir:
	ld a, [fs_tmp]
	call fs_list
	ld b, 0
.loop:
	ld a, [list_count]
	cp b
	ret z
	push bc
	ld e, b
	ld d, 0
	ld hl, list_entries
	add hl, de
	ld a, [hl]
	ld [fs_tmp2], a     ; node index
	call fs_node_addr
	ld a, [hl]
	ld [fs_prev], a
	inc hl
	push hl             ; name
	ld a, [ls_long]
	or a
	jr z, .short
	ld a, [fs_prev]
	ld hl, perms_dir
	cp N_DIR
	jr z, .p
	ld hl, perms_file
.p:
	call txt_print_z
	ld a, ' '
	call txt_putc
	; regular files: size in bytes
	ld a, [fs_prev]
	cp N_DIR
	jr z, .short
	ld a, [fs_tmp2]
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
	ld a, ' '
	call txt_putc
.short:
	pop hl
	call txt_print_z
	ld a, [fs_prev]
	cp N_DIR
	jr nz, .nl
	ld a, '/'
	call txt_putc
.nl:
	ld a, $0A
	call txt_putc
	pop bc
	inc b
	jr .loop

h_cd::
	ld a, [sh_argc]
	cp 2
	jr c, .home
	ld a, 1
	call sh_arg_de
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	ld [fs_tmp], a
	jr .check
.home:
	ld de, str_home
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	ld [fs_tmp], a
.check:
	ld a, [fs_tmp]
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr z, .go
	ld a, FS_E_NOTDIR
	ld [fs_errno], a
	call sh_err_print
	ret
.go:
	ld a, [fs_tmp]
	call fs_set_cwd
	call shell_set_prompt
	call shell_render_input
	ret

h_pwd::
	; output goes through the SDCC-compiled C path (src/shcmd.c): an
	; independent implementation of the text output for this command
	jp _shc_pwd

h_cat::
	ld a, [sh_argc]
	cp 2
	jr c, .done
	ld b, 1
.loop:
	ld a, [sh_argc]
	ld e, a
	ld a, b
	cp e
	jr nc, .done
	push bc
	ld a, b
	call sh_arg_de
	call fs_resolve
	cp $FF
	jr z, .err_pop
	ld [fs_tmp], a
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr z, .isdir
	ld a, [fs_tmp]
	call fs_read_open
.rd:
	call fread_next
	jr nc, .rdone
	call txt_putc
	jr .rd
.rdone:
	ld a, $0A
	call txt_putc
	pop bc
	inc b
	jr .loop
.isdir:
	ld a, FS_E_ISDIR
	ld [fs_errno], a
.err_pop:
	pop bc
	call sh_err_print
	inc b
	jr .loop
.done:
	ret

h_echo::
	ld b, 1
.scan:
	ld a, [sh_argc]
	ld e, a
	ld a, b
	cp e
	jr z, .no_redir
	ld a, b
	call sh_arg_hl
	push hl
	ld de, str_gt
	call strcmp_z
	pop hl
	jr z, .found
	inc b
	jr .scan
.found:
	inc b               ; b = filename arg index
	ld a, [sh_argc]
	ld e, a
	ld a, b
	cp e
	jr c, .have_file
	ld hl, str_syntax
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret
.have_file:
	; build content: args 1..b-2 space-joined + \n
	ld hl, echo_buf
	ld c, 1
.eb:
	ld a, c
	inc a
	cp b
	jr nc, .eb_done
	ld a, c
	cp 1
	jr z, .eb_arg
	ld a, ' '
	ld [hl+], a
.eb_arg:
	push hl
	ld a, c
	call sh_arg_hl
	pop de
.eb_cp:
	ld a, [hl+]
	ld [de], a
	inc de
	or a
	jr nz, .eb_cp
	dec de
	ld h, d
	ld l, e
	inc c
	jr .eb
.eb_done:
	ld [hl], $0A
	inc hl
	xor a
	ld [hl], a
	ld a, b
	ld [sh_wr_idx], a
	call sh_arg_de
	ld b, N_FILE
	ld hl, echo_buf
	call sh_create_path
	jp c, sh_err_print
	ld hl, str_wrote
	call txt_print_z
	ld a, [sh_wr_idx]
	call sh_arg_hl
	call txt_print_z
	ld a, $0A
	jp txt_putc
.no_redir:
	; plain output goes through the SDCC-compiled C path (src/shcmd.c)
	jp _shc_echo_plain

h_mkdir::
	ld a, [sh_argc]
	cp 2
	jr c, .usage
	ld a, 1
	call sh_arg_de
	ld b, N_DIR
	ld hl, $0000
	call sh_create_path
	jp c, sh_err_print
	ld hl, str_created
	call txt_print_z
	ld a, 1
	call sh_arg_hl
	call txt_print_z
	ld a, $0A
	jp txt_putc
.usage:
	ld hl, str_usage_mkdir
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_touch::
	ld a, [sh_argc]
	cp 2
	jr c, .usage
	ld a, 1
	call sh_arg_de
	call fs_resolve
	cp $FF
	jr z, .create
	ret                 ; exists -> noop
.create:
	ld b, N_FILE
	ld hl, $0000
	call sh_create_path
	jp c, sh_err_print
	ld hl, str_created
	call txt_print_z
	ld a, 1
	call sh_arg_hl
	call txt_print_z
	ld a, $0A
	jp txt_putc
.usage:
	ld hl, str_usage_touch
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_rmdir::
	ld a, [sh_argc]
	cp 2
	jr c, .usage
	ld a, 1
	call sh_arg_de
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	ld [fs_tmp], a
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr z, .del
	ld a, FS_E_NOTDIR
	ld [fs_errno], a
	call sh_err_print
	ret
.del:
	ld a, [fs_tmp]
	call fs_delete
	jp c, sh_err_print
	ld hl, str_removed
	call txt_print_z
	ld a, 1
	call sh_arg_hl
	call txt_print_z
	ld a, $0A
	jp txt_putc
.usage:
	ld hl, str_usage_rm
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_rm::
	ld a, [sh_argc]
	cp 2
	jr c, .usage
	ld a, 1
	call sh_arg_de
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	ld [fs_tmp], a
	call fs_node_addr
	ld a, [hl]
	cp N_DIR
	jr nz, .del
	ld a, FS_E_ISDIR
	ld [fs_errno], a
	call sh_err_print
	ret
.del:
	ld a, [fs_tmp]
	call fs_delete
	jp c, sh_err_print
	ld hl, str_removed
	call txt_print_z
	ld a, 1
	call sh_arg_hl
	call txt_print_z
	ld a, $0A
	jp txt_putc
.usage:
	ld hl, str_usage_rm
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_clear::
	xor a
	ld c, a
.loop:
	push bc
	call txt_clear_row
	pop bc
	inc c
	ld a, c
	cp TERM_BOT + 1
	jr c, .loop
	xor a
	ld [cur_col], a
	ld [cur_row], a
	ret

h_whoami::
	ld hl, str_whoami
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_uname::
	ld hl, str_uname
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_uptime::
	ld hl, str_up
	call txt_print_z
	ld a, [upt_secs]
	ld e, a
	ld a, [upt_secs+1]
	ld d, a
	push de
	pop hl
	ld c, 60
	call div_hl_c       ; hl = minutes, a = seconds
	push af
	call txt_print_u16
	pop af
	push af
	ld hl, str_min
	call txt_print_z
	pop af
	ld l, a
	ld h, 0
	call txt_print_u16
	ld hl, str_sec
	call txt_print_z
	ld a, $0A
	call txt_putc
	ret

h_motd::
	ld de, str_etc_motd
	call fs_resolve
	cp $FF
	jp z, sh_err_print
	call fs_read_open
.m:
	call fread_next
	ret nc
	call txt_putc
	jr .m

h_exit::
	jp title_enter      ; exit = log out, back to the splash screen

; ---- data -------------------------------------------------------------

sh_banner:
	db "D-PAD pick, A types", $0A
	db "START runs the line", $0A
	db "help for cmds", $0A, 0

str_typing_hint:
	db "D-PAD picks a key", $0A
	db "A types it", $0A
	db "START runs it", $0A, 0

sh_cmds:
	dw cmd_help, h_help
	dw cmd_ls, h_ls
	dw cmd_cd, h_cd
	dw cmd_pwd, h_pwd
	dw cmd_cat, h_cat
	dw cmd_echo, h_echo
	dw cmd_mkdir, h_mkdir
	dw cmd_rmdir, h_rmdir
	dw cmd_rm, h_rm
	dw cmd_touch, h_touch
	dw cmd_clear, h_clear
	dw cmd_whoami, h_whoami
	dw cmd_uname, h_uname
	dw cmd_uptime, h_uptime
	dw cmd_motd, h_motd
	dw cmd_exit, h_exit
	dw $0000, $0000

cmd_help:   db "help", 0
cmd_ls:     db "ls", 0
cmd_cd:     db "cd", 0
cmd_pwd:    db "pwd", 0
cmd_cat:    db "cat", 0
cmd_echo:   db "echo", 0
cmd_mkdir:  db "mkdir", 0
cmd_rmdir:  db "rmdir", 0
cmd_rm:     db "rm", 0
cmd_touch:  db "touch", 0
cmd_clear:  db "clear", 0
cmd_whoami: db "whoami", 0
cmd_uname:  db "uname", 0
cmd_uptime: db "uptime", 0
cmd_motd:   db "motd", 0
cmd_exit:   db "exit", 0

txt_help:
	db "commands:", $0A
	db " help ls cd pwd cat", $0A
	db " echo mkdir rmdir", $0A
	db " rm touch clear", $0A
	db " whoami uname", $0A
	db " uptime motd exit", $0A
	db "A type  B backspace", $0A
	db "START run", $0A
	db "SELECT shift", $0A
	db "SELECT+START back", $0A, 0

str_err:            db "error: ", 0
str_home:           db "/home/user", 0
str_etc_motd:       db "/etc/motd", 0
str_gt:             db ">", 0
str_dashl:          db "-l", 0
str_syntax:         db "usage: echo text > file", 0
str_not_found:      db "not found: ", 0
str_did_mean:       db "did you mean: ", 0
str_run_hint:       db "START runs", 0
str_created:        db "created ", 0
str_removed:        db "removed ", 0
str_wrote:          db "wrote ", 0
str_usage_mkdir:    db "usage: mkdir <dir>", 0
str_usage_touch:    db "usage: touch <file>", 0
str_usage_rm:       db "usage: rm|rmdir <path>", 0
str_root_prompt:    db "/$ ", 0
str_prompt_tail:    db "$ ", 0
str_whoami:         db "user", 0
str_uname:          db "GB-UNIX 1.0.0 sm83", 0
str_up:             db "up ", 0
str_min:            db " min ", 0
str_sec:            db " sec", 0

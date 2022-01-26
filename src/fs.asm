; fs.asm — filesystem engine over the SRAM inode table
;
; Node layout (20 bytes, defined by tools/genfs.py, copied to SRAM):
;   0        type     0=free, 1=file, 2=dir
;   1-11     name     10 chars + NUL
;   12       parent   node index ($FF for root)
;   13       child    first child ($FF if none)
;   14       sibling  next sibling ($FF if last)
;   15       attrs    bit0: 0=ROM (immutable), 1=SRAM (mutable)
;   16-17    data     content address (ROM addr or SRAM addr)
;   18-19    size     content length

include "hardware.inc"
include "fs.inc"

section "fsw", wram0

cwd_stack::     ds 16
cwd_depth::     db
token_buf::     ds 12
fs_name_buf::   ds 12
pwd_buf::       ds 24
tmp_stack::     ds 16
list_entries::  ds 96
list_count::    db
fread_src::     ds 2
fread_rem::     ds 2
fs_errno::      db
fs_tmp::        db
fs_tmp2::       db
fs_prev::       db
fs_par_parent:: db
fs_par_type::   db
fs_path_buf::   ds 32
fs_content::    ds 2            ; sh_create_path: content zstr ptr

section "fs", rom0

; ---- low-level node access --------------------------------------------

; fs_node_addr:: hl = &sram_nodes[a]. Preserves a, de. Clobbers bc.
fs_node_addr::
	push bc
	push de
	ld l, a
	ld h, 0
	add hl, hl          ; x2
	ld e, l
	ld d, h
	add hl, hl          ; x4
	add hl, hl          ; x8
	add hl, de          ; x8 + x2 = x10
	add hl, hl          ; x20
	ld bc, SRAM_NODES
	add hl, bc
	pop de
	pop bc
	ret

; strcmp_z:: compare zstrings hl vs de. Z set if equal.
strcmp_z::
	ld a, [de]
	cp [hl]
	jr nz, .ne
	or a
	ret z               ; both ended, equal
	inc de
	inc hl
	jr strcmp_z
.ne:
	ret

; fs_get_child:: find child of dir a by name.
; in:  a = dir node, de = name zstr
; out: a = child node or $FF
fs_get_child::
	push bc
	push de
	push hl
	call fs_node_addr
	REPT N_CHILD
	inc hl
	ENDR
	ld b, [hl]          ; b = current child
.loop:
	ld a, b
	cp $FF
	jr z, .none
	push bc
	push de
	ld a, b
	call fs_node_addr
	inc hl              ; name field
	call strcmp_z
	pop de
	pop bc
	jr z, .found
	ld a, b
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld b, [hl]          ; b = sibling (fs_node_addr clobbers bc, reloaded here)
	jr .loop
.found:
	ld a, b
	pop hl
	pop de
	pop bc
	ret
.none:
	ld a, $FF
	pop hl
	pop de
	pop bc
	ret

; ---- paths ------------------------------------------------------------

; fs_get_cwd:: a = current directory node (0 = root).
fs_get_cwd::
	ld a, [cwd_depth]
	or a
	ret z
	dec a
	push de
	push hl
	ld e, a
	ld d, 0
	ld hl, cwd_stack
	add hl, de
	ld a, [hl]
	pop hl
	pop de
	ret

; fs_set_cwd:: rebuild cwd_stack by walking parents from node a.
fs_set_cwd::
	push af
	push bc
	push de
	push hl
	ld hl, tmp_stack
	ld b, 0
.walk:
	or a
	jr z, .rev
	ld e, a             ; e = current node
	ld a, b
	cp 16
	jr nc, .rev
	ld a, e
	ld [hl+], a
	inc b
	push hl
	push bc
	ld a, e
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld a, [hl]
	pop bc
	pop hl
	jr .walk
.rev:
	ld c, b             ; save chain length before reverse loop eats b
	; hl is already one past the last stored entry (ld [hl+] pre-increments)
	ld de, cwd_stack
.rev_loop:
	ld a, b
	or a
	jr z, .done
	dec hl
	ld a, [hl]
	ld [de], a
	inc de
	dec b
	jr .rev_loop
.done:
	ld a, c             ; c = chain length (b is 0 here)
	ld [cwd_depth], a
	pop hl
	pop de
	pop bc
	pop af
	ret

; fs_pwd_str:: write path of node a into pwd_buf as zstr.
fs_pwd_str::
	push bc
	push de
	push hl
	or a
	jr nz, .walk
	ld hl, pwd_buf
	ld [hl], '/'
	inc hl
	xor a
	ld [hl], a
	jr .end
.walk:
	; build chain (excluding root) into tmp_stack: [deepest ... toplevel]
	ld hl, tmp_stack
	ld b, 0
	ld e, a
.loop:
	ld a, e
	or a
	jr z, .emit
	ld a, b
	cp 16
	jr nc, .emit
	ld a, e
	ld [hl+], a
	inc b
	push hl
	push bc
	ld a, e
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld a, [hl]
	pop bc
	pop hl
	ld e, a
	jr .loop
.emit:
	; walk tmp_stack backwards, appending "/name"
	; (hl is already one past the last stored entry; ld [hl+] pre-increments)
	ld de, pwd_buf
.emit_loop:
	ld a, b
	or a
	jr z, .emit_done
	; guard: write ptr de >= pwd_buf+20 -> bail
	ld a, d
	sub pwd_buf >> 8
	jr nz, .emit_done
	ld a, e
	sub (pwd_buf + 20) & $FF
	jr nc, .emit_done
	dec hl              ; hl = chain node idx
	ld a, [hl]
	push hl
	push bc
	call fs_node_addr
	inc hl              ; hl = name
	push hl             ; name
	ld l, e
	ld h, d             ; hl = write ptr
	pop de              ; de = name
	ld [hl], '/'
	inc hl
.cpname:
	ld a, [de]
	ld [hl+], a
	inc de
	or a
	jr nz, .cpname
	dec hl              ; hl = NUL slot, overwritten next iteration
	ld d, h
	ld e, l             ; de = write ptr (NUL slot)
	pop bc
	pop hl              ; restore chain pointer
	dec b
	jr .emit_loop
.emit_done:
	xor a
	ld [de], a
.end:
	pop hl
	pop de
	pop bc
	ret

; fs_resolve:: resolve a path zstr to a node.
; in:  de = path zstr (absolute with leading /, or relative)
; out: a = node or $FF (fs_errno set)
fs_resolve::
	push bc
	push de
	push hl
	ld a, [de]
	cp '/'
	jr nz, .from_cwd
	xor a               ; absolute -> root
	inc de
	jr .start_set
.from_cwd:
	call fs_get_cwd
.start_set:
	ld b, a             ; b = current node
.comp_loop:
	ld a, [de]
	or a
	jr z, .done
	cp '/'
	jr nz, .got_tok
	inc de
	jr .comp_loop
.got_tok:
	; copy one component into token_buf (de advances past the component)
	ld hl, token_buf
	ld c, 11            ; room incl NUL
.tok_copy:
	ld a, [de]
	or a
	jr z, .tok_end
	cp '/'
	jr z, .tok_end
	dec c
	jr z, .toolong_pop
	ld [hl+], a
	inc de
	jr .tok_copy
.tok_end:
	xor a
	ld [hl], a          ; de now points past the component
	; handle "." and ".."
	ld hl, token_buf
	ld a, [hl+]
	cp '.'
	jr nz, .lookup
	ld a, [hl]
	or a
	jr z, .comp_loop    ; "."
	cp '.'
	jr nz, .lookup
	inc hl              ; advance to the third char before testing it
	ld a, [hl]
	or a
	jr nz, .lookup
	; ".." -> parent (stay at root if already there)
	ld a, b
	or a
	jr z, .comp_loop
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld b, [hl]
	jr .comp_loop
.lookup:
	push de
	ld a, b
	ld de, token_buf
	call fs_get_child
	pop de
	cp $FF
	jr z, .noent
	ld b, a
	jr .comp_loop
.done:
	ld a, b
	pop hl
	pop de
	pop bc
	ret
.noent:
	ld a, FS_E_NOENT
	ld [fs_errno], a
	ld a, $FF
	pop hl
	pop de
	pop bc
	ret
.toolong_pop:
	ld a, FS_E_NAMETOOLONG
	ld [fs_errno], a
	ld a, $FF
	pop hl
	pop de
	pop bc
	ret

; fs_list:: fill list_entries with children of dir a; sets list_count.
fs_list::
	push bc
	push de
	push hl
	call fs_node_addr
	REPT N_CHILD
	inc hl
	ENDR
	ld b, [hl]          ; first child
	ld hl, list_entries
	ld c, 0
.loop:
	ld a, c
	cp 16               ; list_entries buffer is 16 — never overrun
	jr z, .done
	ld a, b
	cp $FF
	jr z, .done
	ld [hl+], a
	inc c
	push hl
	ld a, b
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld b, [hl]
	pop hl
	jr .loop
.done:
	ld a, c
	ld [list_count], a
	pop hl
	pop de
	pop bc
	ret

; fs_count_children:: a = node -> a = number of children.
fs_count_children::
	call fs_node_addr
	REPT N_CHILD
	inc hl
	ENDR
	ld b, [hl]          ; first child
	ld c, 0
.loop:
	ld a, b
	cp $FF
	jr z, .done
	inc c
	ld a, b
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld b, [hl]
	jr .loop
.done:
	ld a, c
	ret

; fs_read_open:: set up sequential read of file a (fread_src/fread_rem).
fs_read_open::
	push hl
	call fs_node_addr
	REPT N_ATTRS
	inc hl
	ENDR
	ld a, [hl+]         ; attrs
	ld e, [hl]          ; data lo
	inc hl
	ld d, [hl]          ; data hi
	inc hl
	ld c, [hl]          ; size lo
	inc hl
	ld b, [hl]          ; size hi
	ld hl, fread_src
	ld a, e
	ld [hl+], a
	ld a, d
	ld [hl+], a
	ld a, c
	ld [hl+], a
	ld a, b
	ld [hl], a
	pop hl
	ret

; fread_next:: next byte -> a, carry set. EOF -> carry clear.
; Preserves bc, de, hl.
fread_next::
	push bc
	push de
	push hl
	ld a, [fread_rem]
	ld c, a
	ld a, [fread_rem+1]
	ld b, a
	or c
	jr z, .eof
	dec bc
	ld a, c
	ld [fread_rem], a
	ld a, b
	ld [fread_rem+1], a
	ld a, [fread_src]
	ld e, a
	ld a, [fread_src+1]
	ld d, a
	ld a, [de]
	push af
	inc de
	ld a, e
	ld [fread_src], a
	ld a, d
	ld [fread_src+1], a
	pop af
	scf
	pop hl
	pop de
	pop bc
	ret
.eof:
	pop hl
	pop de
	pop bc
	or a                ; carry clear
	ret

; fs_create:: create a node in the SRAM table.
; in:  a = parent node, de = name zstr, b = type (N_FILE/N_DIR)
; out: a = new node or $FF (fs_errno set)
fs_create::
	ld [fs_par_parent], a
	ld a, b
	ld [fs_par_type], a
	; copy name, zero-padded, into fs_name_buf (11 bytes)
	push de
	ld hl, fs_name_buf
	ld c, 11
.cp:
	ld a, [de]
	or a
	jr z, .term
	dec c
	jr z, .toolong_pop
	ld [hl+], a
	inc de
	jr .cp
.term:
	xor a
	ld [hl], a
	pop de
	jr .have_name
.toolong_pop:
	pop de
	ld a, FS_E_NAMETOOLONG
	ld [fs_errno], a
	ld a, $FF
	ret
.have_name:
	; must not exist yet
	ld a, [fs_par_parent]
	ld de, fs_name_buf
	call fs_get_child
	cp $FF
	jr nz, .exists
	; find a free inode
	ld a, 1
.scan:
	cp NODE_COUNT
	jr nc, .full
	push af
	call fs_node_addr
	ld a, [hl]
	or a
	pop bc              ; b = slot index (flags preserved for the test below)
	jr nz, .next
	; free slot: b = index, hl = address
	ld a, b
	ld [fs_tmp], a
	ld a, [fs_par_type]
	ld [hl+], a         ; N_TYPE
	; name: copy 11 bytes
	ld de, fs_name_buf
	ld c, 11
.cpn:
	ld a, [de]
	ld [hl+], a
	inc de
	dec c
	jr nz, .cpn
	; parent
	ld a, [fs_par_parent]
	ld [hl+], a         ; N_PARENT
	ld a, $FF
	ld [hl+], a         ; N_CHILD = FF (empty dir / file)
	; link: new.sibling = parent.child; parent.child = new
	ld a, [fs_par_parent]
	call fs_node_addr
	REPT N_CHILD
	inc hl
	ENDR
	ld e, [hl]          ; old first child
	ld a, [fs_tmp]
	ld [hl], a          ; parent.child = new
	; new.sibling = e
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld [hl], e
	; attrs = SRAM, data = 0, size = 0
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_ATTRS
	inc hl
	ENDR
	ld a, 1
	ld [hl+], a         ; attrs = SRAM storage
	xor a
	ld [hl+], a         ; data lo
	ld [hl+], a         ; data hi
	ld [hl+], a         ; size lo
	ld [hl], a          ; size hi
	ld a, [fs_tmp]
	ret
.next:
	ld a, b
	inc a
	jr .scan
.exists:
	ld a, FS_E_EXISTS
	ld [fs_errno], a
	ld a, $FF
	ret
.full:
	ld a, FS_E_FULL
	ld [fs_errno], a
	ld a, $FF
	ret

; fs_delete:: remove file or empty dir from the tree.
; in:  a = node
; out: CF clear = ok, CF set = failed (fs_errno set)
fs_write_new::   ; write content into a fresh SRAM file.
; in:  fs_tmp = node idx, hl = content zstr
; out: CF clear = ok, CF set = failed (fs_errno set)
	push hl
	call strlen_hl
	ld a, b
	ld [fs_tmp2], a     ; len
	ld c, b
	ld b, 0
	pop hl
	push bc
	push hl
	call heap_alloc     ; de = SRAM address
	pop hl
	pop bc
	jr c, .fail
	push de
	call mem_copy       ; copy bc bytes hl -> de
	pop hl              ; hl = SRAM address
	; node.data = hl
	push hl
	ld a, [fs_tmp]
	call fs_node_addr
	pop de
	ld bc, N_DATA
	add hl, bc
	ld a, e
	ld [hl+], a
	ld a, d
	ld [hl], a
	; node.size = len
	ld a, [fs_tmp]
	call fs_node_addr
	ld bc, N_SIZE
	add hl, bc
	ld a, [fs_tmp2]
	ld [hl+], a
	xor a
	ld [hl], a
	or a                ; clear carry
	ret
.fail:
	ld a, FS_E_FULL
	ld [fs_errno], a
	scf
	ret

fs_delete::
	ld [fs_tmp], a
	or a
	jr nz, .real
	ld a, FS_E_EPERM
	ld [fs_errno], a
	scf
	ret
.real:
	call fs_node_addr
	ld a, [hl]
	or a
	jr z, .ok           ; already free
	; ROM nodes (attrs bit0 = 0) are immutable: rm/rmdir must fail
	push hl
	REPT N_ATTRS
	inc hl
	ENDR
	bit 0, [hl]
	pop hl
	jr nz, .mutable
	ld a, FS_E_EPERM
	ld [fs_errno], a
	scf
	ret
.mutable:
	cp N_DIR
	jr nz, .unlink
	REPT N_CHILD
	inc hl
	ENDR
	ld a, [hl]
	cp $FF
	jr z, .unlink
	ld a, FS_E_NOTEMPTY
	ld [fs_errno], a
	scf
	ret
.ok:
	xor a
	ret
.unlink:
	; find predecessor in parent's child chain
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld a, [hl]          ; parent idx
	call fs_node_addr   ; hl = parent
	REPT N_CHILD
	inc hl
	ENDR
	ld c, [hl]          ; cur = first child
	ld a, $FF
	ld [fs_prev], a
.walk:
	ld a, c
	ld e, a
	ld a, [fs_tmp]
	cp e
	jr z, .found
	ld a, c
	ld [fs_prev], a
	ld a, c
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld c, [hl]
	jr .walk
.found:
	ld a, [fs_prev]
	cp $FF
	jr nz, .mid
	; was first child: parent.child = node.sibling
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_PARENT
	inc hl
	ENDR
	ld a, [hl]          ; parent
	call fs_node_addr
	REPT N_CHILD
	inc hl
	ENDR
	push hl             ; &parent.child
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld a, [hl]          ; sibling of deleted node
	pop hl
	ld [hl], a
	jr .free_node
.mid:
	; prev.sibling = node.sibling
	ld a, [fs_prev]
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	push hl
	ld a, [fs_tmp]
	call fs_node_addr
	REPT N_SIBLING
	inc hl
	ENDR
	ld a, [hl]
	pop hl
	ld [hl], a
.free_node:
	ld a, [fs_tmp]
	call fs_node_addr
	xor a
	ld [hl], a          ; type = free
	ret

; fs_err_str:: a = errno -> hl = message zstr
fs_err_str::
	ld hl, .table
	dec a
	add a, a            ; *2 (entries are dw)
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl+]
	ld h, [hl]
	ld l, a
	ret

.table:
	dw .m_noent, .m_notdir, .m_isdir, .m_notempty
	dw .m_exists, .m_full, .m_nametoolong, .m_eperm
.m_noent:        db "no such file or directory", 0
.m_notdir:       db "not a directory", 0
.m_isdir:        db "is a directory", 0
.m_notempty:     db "directory not empty", 0
.m_exists:       db "file exists", 0
.m_full:         db "no space left on device", 0
.m_nametoolong:  db "name too long", 0
.m_eperm:        db "operation not permitted", 0

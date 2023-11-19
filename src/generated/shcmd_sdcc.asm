; shcmd_sdcc.asm — pre-generated SDCC output for src/shcmd.c.
;
; This file is only used when `sdcc` is not on $PATH, so the ROM can still
; be built with just the bundled RGBDS. Regenerate it with SDCC 4.2+:
;
;   sdcc -msm83 --asm=rgbds --no-peep -S src/shcmd.c \
;        -o src/generated/shcmd_sdcc.asm
;
;--------------------------------------------------------
; File Created by SDCC : free open source ANSI-C Compiler
; Version 4.2.0 #13081 (Linux)
;--------------------------------------------------------
	; MODULE shcmd
	; Generated using the rgbds tokens.

;--------------------------------------------------------
; Public variables in this module
;--------------------------------------------------------
	EXPORT _shc_echo_plain
	EXPORT _shc_pwd
	EXPORT _shc_puts
	EXPORT _shc_putc
	EXPORT _shc_load
	EXPORT _shc_store
	EXPORT _fs_pwd_str
	EXPORT _fs_get_cwd
;--------------------------------------------------------
; special function registers
;--------------------------------------------------------
;--------------------------------------------------------
; ram data
;--------------------------------------------------------
	SECTION FRAGMENT "src/shcmd.c_DATA",WRAMX
_s_c:
	DS 1
_s_i:
	DS 1
_s_r:
	DS 1
_s_src:
	DS 2
_s_dst:
	DS 2
_s_base:
	DS 2
;--------------------------------------------------------
; ram data
;--------------------------------------------------------
	SECTION FRAGMENT "_INITIALIZED",ROM0
;--------------------------------------------------------
; absolute external ram data
;--------------------------------------------------------
	SECTION FRAGMENT "_DABS (ABS)",ROM0
;--------------------------------------------------------
; global & static initialisations
;--------------------------------------------------------
	SECTION FRAGMENT "_HOME",ROM0
	SECTION FRAGMENT "_GSINIT",ROM0
	SECTION FRAGMENT "_GSFINAL",ROM0
	SECTION FRAGMENT "_GSINIT",ROM0
;--------------------------------------------------------
; Home
;--------------------------------------------------------
	SECTION FRAGMENT "src/shcmd.c_HOME",ROM0
	SECTION FRAGMENT "src/shcmd.c_HOME",ROM0
;--------------------------------------------------------
; code
;--------------------------------------------------------
	SECTION FRAGMENT "src/shcmd.c_CODE",ROMX
;src/shcmd.c:58: static uint16_t off_row(uint8_t r)
;	---------------------------------
; Function off_row
; ---------------------------------
_off_row:
	ld	c, a
;src/shcmd.c:60: return ((uint16_t)r << 4) + ((uint16_t)r << 2);
	ld	b, $00
	ld	l, c
	ld	h, b
	add	hl, hl
	add	hl, hl
	add	hl, hl
	add	hl, hl
	sla	c
	rl	b
	sla	c
	rl	b
	add	hl, bc
	ld	c, l
	ld	b, h
.l00101:
;src/shcmd.c:61: }
	ret
;src/shcmd.c:64: static void shc_scroll(void)
;	---------------------------------
; Function shc_scroll
; ---------------------------------
_shc_scroll:
;src/shcmd.c:66: s_c = scr_top + 1;
	ld	hl, _scr_top
	ld	a, [hl]
	inc	a
	ld	hl, _s_c
	ld	[hl], a
;src/shcmd.c:68: while (scr_bot >= s_c) {
.l00102:
	ld	hl, _scr_bot
	ld	a, [hl]
	ld	hl, _s_c
	sub	a, [hl]
	jp	C, .l00104
;src/shcmd.c:69: s_src = off_row(s_c);
	ld	a, [hl]
	call	_off_row
	ld	hl, _s_src
	ld	[hl], c
	inc	hl
	ld	[hl], b
;src/shcmd.c:70: s_dst = s_src - SCREEN_W;
	dec	hl
	ld	a, [hl]
	inc	hl
	ld	b, [hl]
	add	a, $EC
	ld	c, a
	ld	a, b
	adc	a, $FF
	ld	hl, _s_dst
	ld	[hl], c
	inc	hl
	ld	[hl], a
;src/shcmd.c:71: for (s_i = 0; s_i < SCREEN_W; s_i++)
	ld	hl, _s_i
	ld	[hl], $00
.l00107:
;src/shcmd.c:73: shc_load((uint16_t)screen_buf + s_src + s_i));
	ld	a, LOW(_screen_buf)
	ld	hl, _s_src
	add	a, [hl]
	ld	c, a
	ld	a, HIGH(_screen_buf)
	inc	hl
	adc	a, [hl]
	ld	b, a
	ld	hl, _s_i
	ld	l, [hl]
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, bc
	ld	e, l
	ld	d, h
	call	_shc_load
	ld	c, a
;src/shcmd.c:72: shc_store((uint16_t)screen_buf + s_dst + s_i,
	ld	a, LOW(_screen_buf)
	ld	hl, _s_dst
	add	a, [hl]
	ld	e, a
	ld	a, HIGH(_screen_buf)
	inc	hl
	adc	a, [hl]
	ld	d, a
	ld	hl, _s_i
	ld	l, [hl]
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, de
	ld	e, l
	ld	d, h
	ld	a, c
	call	_shc_store
;src/shcmd.c:71: for (s_i = 0; s_i < SCREEN_W; s_i++)
	ld	hl, _s_i
	inc	[hl]
	ld	a, [hl]
	sub	a, $14
	jp	C, .l00107
;src/shcmd.c:74: s_c++;
	ld	hl, _s_c
	inc	[hl]
	jp	.l00102
.l00104:
;src/shcmd.c:76: s_base = off_row(scr_bot);
	ld	hl, _scr_bot
	ld	a, [hl]
	call	_off_row
	ld	hl, _s_base
	ld	[hl], c
	inc	hl
	ld	[hl], b
;src/shcmd.c:77: for (s_i = 0; s_i < SCREEN_W; s_i++)
	ld	hl, _s_i
	ld	[hl], $00
.l00109:
;src/shcmd.c:78: shc_store((uint16_t)screen_buf + s_base + s_i, 0); /* tile 0 = space */
	ld	a, LOW(_screen_buf)
	ld	hl, _s_base
	add	a, [hl]
	ld	c, a
	ld	a, HIGH(_screen_buf)
	inc	hl
	adc	a, [hl]
	ld	b, a
	ld	hl, _s_i
	ld	l, [hl]
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, bc
	ld	e, l
	ld	d, h
	xor	a, a
	call	_shc_store
;src/shcmd.c:77: for (s_i = 0; s_i < SCREEN_W; s_i++)
	ld	hl, _s_i
	inc	[hl]
	ld	a, [hl]
	sub	a, $14
	jp	C, .l00109
;src/shcmd.c:79: for (s_r = scr_top; scr_bot >= s_r; s_r++)
	ld	hl, _scr_top
	ld	a, [hl]
	ld	hl, _s_r
	ld	[hl], a
.l00112:
	ld	hl, _scr_bot
	ld	a, [hl]
	ld	hl, _s_r
	sub	a, [hl]
	jp	C, .l00114
;src/shcmd.c:80: shc_store((uint16_t)dirty_rows + s_r, 1);
	ld	bc, _dirty_rows
	ld	l, [hl]
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, bc
	ld	e, l
	ld	d, h
	ld	a, $01
	call	_shc_store
;src/shcmd.c:79: for (s_r = scr_top; scr_bot >= s_r; s_r++)
	ld	hl, _s_r
	inc	[hl]
	jp	.l00112
.l00114:
;src/shcmd.c:81: }
	ret
;src/shcmd.c:84: static void shc_newline(void)
;	---------------------------------
; Function shc_newline
; ---------------------------------
_shc_newline:
;src/shcmd.c:86: cur_col = 0;
	ld	hl, _cur_col
	ld	[hl], $00
;src/shcmd.c:87: if ((uint8_t)(cur_row + 1) > scr_bot) {
	ld	hl, _cur_row
	ld	c, [hl]
	inc	c
	ld	b, c
	ld	hl, _scr_bot
	ld	a, [hl]
	sub	a, b
	jp	NC, .l00102
;src/shcmd.c:88: shc_scroll();
	call	_shc_scroll
;src/shcmd.c:89: cur_row = scr_bot;
	ld	hl, _scr_bot
	ld	a, [hl]
	ld	hl, _cur_row
	ld	[hl], a
	jp	.l00104
.l00102:
;src/shcmd.c:91: cur_row = cur_row + 1;
	ld	hl, _cur_row
	ld	[hl], c
.l00104:
;src/shcmd.c:93: }
	ret
;src/shcmd.c:96: void shc_putc(char c_in)
;	---------------------------------
; Function shc_putc
; ---------------------------------
_shc_putc::
	dec	sp
	ld	c, a
;src/shcmd.c:98: uint8_t ch = (uint8_t)c_in;
	ld	hl, sp+0
	ld	[hl], c
;src/shcmd.c:102: if (ch == '\n') {
	ld	a, c
	sub	a, $0A
	jp	NZ,.l00125
	jp	.l00126
.l00125:
	jp	.l00102
.l00126:
;src/shcmd.c:103: shc_newline();
	inc	sp
	jp	_shc_newline
;src/shcmd.c:104: return;
	jp	.l00108
.l00102:
;src/shcmd.c:106: if (ch < 0x20u || ch >= 0x7Fu)
	ld	a, c
	sub	a, $20
	jp	C, .l00103
	ld	a, c
	sub	a, $7F
	jp	C, .l00104
.l00103:
;src/shcmd.c:107: ch = '.';                          /* control bytes render as '.' */
	ld	hl, sp+0
	ld	[hl], $2E
.l00104:
;src/shcmd.c:108: if (cur_col >= SCREEN_W)
	ld	hl, _cur_col
	ld	a, [hl]
	sub	a, $14
	jp	C, .l00107
;src/shcmd.c:109: shc_newline();                     /* resolve pending wrap */
	call	_shc_newline
.l00107:
;src/shcmd.c:110: r = cur_row;
	ld	hl, _cur_row
	ld	e, [hl]
;src/shcmd.c:111: off = off_row(r) + cur_col;
	push	de
	ld	a, e
	call	_off_row
	pop	de
	ld	hl, _cur_col
	ld	l, [hl]
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, bc
	ld	c, l
	ld	b, h
;src/shcmd.c:112: shc_store((uint16_t)screen_buf + off, ch - 0x20u);
	ld	hl, sp+0
	ld	a, [hl]
	add	a, $E0
	ld	d, a
	ld	hl, _screen_buf
	add	hl, bc
	push	de
	ld	a, d
	ld	e, l
	ld	d, h
	call	_shc_store
	pop	de
;src/shcmd.c:113: shc_store((uint16_t)dirty_rows + r, 1);
	ld	hl, _dirty_rows
	ld	d, $00
	add	hl, de
	ld	e, l
	ld	d, h
	ld	a, $01
	call	_shc_store
;src/shcmd.c:114: cur_col++;
	ld	hl, _cur_col
	inc	[hl]
.l00108:
;src/shcmd.c:115: }
	inc	sp
	ret
;src/shcmd.c:118: void shc_puts(const char *s)
;	---------------------------------
; Function shc_puts
; ---------------------------------
_shc_puts::
.l00104:
;src/shcmd.c:121: char c = *s;
	ld	a, [de]
	ld	c, a
;src/shcmd.c:122: if (c == 0)
	or	a, a
	jp	NZ, .l00102
;src/shcmd.c:123: return;
	jp	.l00106
.l00102:
;src/shcmd.c:124: shc_putc(c);
	push	de
	ld	a, c
	call	_shc_putc
	pop	de
;src/shcmd.c:125: s++;
	inc	de
	jp	.l00104
.l00106:
;src/shcmd.c:127: }
	ret
;src/shcmd.c:130: void shc_pwd(void)
;	---------------------------------
; Function shc_pwd
; ---------------------------------
_shc_pwd::
;src/shcmd.c:132: uint8_t node = fs_get_cwd();
	call	_fs_get_cwd
	ld	c, a
	ld	b, c
;src/shcmd.c:133: if (node == 0) {
	ld	a, c
	or	a, a
	jp	NZ, .l00102
;src/shcmd.c:134: shc_puts("/ (root)");              /* "/" alone is easy to miss */
	ld	de, ___str_0
	call	_shc_puts
;src/shcmd.c:135: shc_putc('\n');
	ld	a, $0A
	jp	_shc_putc
;src/shcmd.c:136: return;
	jp	.l00103
.l00102:
;src/shcmd.c:138: fs_pwd_str(node);                      /* fills pwd_buf */
	ld	a, b
	call	_fs_pwd_str
;src/shcmd.c:139: shc_puts(pwd_buf);
	ld	de, _pwd_buf
	call	_shc_puts
;src/shcmd.c:140: shc_putc('\n');
	ld	a, $0A
	jp	_shc_putc
.l00103:
;src/shcmd.c:141: }
	ret
___str_0:
	DB "/ (root)"
	DB $00
;src/shcmd.c:144: void shc_echo_plain(void)
;	---------------------------------
; Function shc_echo_plain
; ---------------------------------
_shc_echo_plain::
;src/shcmd.c:147: for (i = 1; i < sh_argc; i++) {
	ld	c, $01
.l00105:
	ld	a, c
	ld	hl, _sh_argc
	sub	a, [hl]
	jp	NC, .l00103
;src/shcmd.c:148: if (i != 1)
	ld	a, c
	dec	a
	jp	NZ,.l00125
	jp	.l00102
.l00125:
;src/shcmd.c:149: shc_putc(' ');
	push	bc
	ld	a, $20
	call	_shc_putc
	pop	bc
.l00102:
;src/shcmd.c:150: shc_puts(sh_args[i]);
	ld	l, c
;	spillPairReg hl
;	spillPairReg hl
	ld	h, $00
;	spillPairReg hl
;	spillPairReg hl
	add	hl, hl
	ld	de, _sh_args
	add	hl, de
	ld	b, [hl]
	inc	hl
	ld	l, [hl]
;	spillPairReg hl
	push	bc
	ld	e, b
	ld	d, l
	call	_shc_puts
	pop	bc
;src/shcmd.c:147: for (i = 1; i < sh_argc; i++) {
	inc	c
	jp	.l00105
.l00103:
;src/shcmd.c:152: shc_putc('\n');
	ld	a, $0A
	jp	_shc_putc
.l00107:
;src/shcmd.c:153: }
	ret
	SECTION FRAGMENT "src/shcmd.c_CODE",ROMX
	SECTION FRAGMENT "_INITIALIZER",ROM0
	SECTION FRAGMENT "_CABS (ABS)",ROM0

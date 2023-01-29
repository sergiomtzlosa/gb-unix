/* shcmd.c — pwd/echo output for gbsh, compiled with SDCC (-msm83) and
 * linked into the ROM with rgblink.
 *
 * This is an independent, C-compiled implementation of the shell text
 * output path. It drives the screen buffer with exactly the same
 * semantics as src/text.asm (tile = charcode - $20, pending wrap at
 * column 20, scroll region scr_top..scr_bot, per-row dirty flags) so the
 * commands reported as rendering nothing on screen (pwd, echo) go through
 * fresh, separately compiled code rather than the assembly print
 * routines.
 *
 * Every WRAM access on the asm-owned screen state goes through the tiny
 * hand-written helpers in src/cwrite.asm: SDCC's RGBDS asm backend
 * miscompiles several direct array stores from C (drops the array base,
 * reuses stale registers), so the C code only computes addresses and
 * logic while the helpers perform the memory access.
 *
 * Freestanding rules: no runtime library is linked, so this module avoids
 * division/modulo and initialized globals (SDCC helpers like __divuint and
 * the crt0 data copy are absent).
 */

#include <stdint.h>

/* ---- WRAM owned by the RGBDS asm (underscore aliases exported there) ----- */

extern uint8_t screen_buf[];   /* 20x18 tile indices (charcode - $20) */
extern uint8_t dirty_rows[];   /* nonzero = row needs re-blit */
extern uint8_t cur_col;        /* cursor column (20 = pending wrap) */
extern uint8_t cur_row;        /* cursor row */
extern uint8_t scr_top;        /* scroll region top */
extern uint8_t scr_bot;        /* scroll region bottom (10 in the shell) */
extern char    pwd_buf[];      /* fs_pwd_str writes the cwd path here */
extern uint8_t sh_argc;        /* tokenized command argument count */
extern char   *sh_args[];      /* argument pointers (little-endian) */

/* ---- ROM routines (jp thunks / hand-written helpers, sdcccall(1)) -------- */

extern uint8_t fs_get_cwd(void);        /* a = current dir node (0 = root) */
extern void    fs_pwd_str(uint8_t node); /* writes path of node a to pwd_buf */
extern void    shc_store(uint16_t where, uint8_t val); /* *(uint8_t*)where=val */
extern uint8_t shc_load(uint16_t where); /* a = *(uint8_t*)where */

#define SCREEN_W 20

/* Scroll state lives in file-scope statics: SDCC's RGBDS asm backend
 * miscompiles stores of computed values to stack locals (it addresses the
 * slot with a stale register), while absolute-addressed globals compile
 * correctly. The shell is single-threaded so shared state is safe. */
static uint8_t  s_c;         /* loop cursor (candidate row) */
static uint8_t  s_i;         /* loop counter */
static uint8_t  s_r;         /* row index */
static uint16_t s_src;       /* source row offset */
static uint16_t s_dst;       /* destination row offset */
static uint16_t s_base;      /* bottom row offset */

/* off_row: WRAM offset of screen row r (r*20 via shifts, no runtime mul). */
static uint16_t off_row(uint8_t r)
{
    return ((uint16_t)r << 4) + ((uint16_t)r << 2);
}

/* shc_scroll: scroll region up one line (same as txt_scroll). */
static void shc_scroll(void)
{
    s_c = scr_top + 1;

    while (scr_bot >= s_c) {
        s_src = off_row(s_c);
        s_dst = s_src - SCREEN_W;
        for (s_i = 0; s_i < SCREEN_W; s_i++)
            shc_store((uint16_t)screen_buf + s_dst + s_i,
                      shc_load((uint16_t)screen_buf + s_src + s_i));
        s_c++;
    }
    s_base = off_row(scr_bot);
    for (s_i = 0; s_i < SCREEN_W; s_i++)
        shc_store((uint16_t)screen_buf + s_base + s_i, 0); /* tile 0 = space */
    for (s_r = scr_top; scr_bot >= s_r; s_r++)
        shc_store((uint16_t)dirty_rows + s_r, 1);
}

/* shc_newline: CR/LF; scrolls the region when passing scr_bot. */
static void shc_newline(void)
{
    cur_col = 0;
    if ((uint8_t)(cur_row + 1) > scr_bot) {
        shc_scroll();
        cur_row = scr_bot;
    } else {
        cur_row = cur_row + 1;
    }
}

/* shc_putc: print one character at the cursor (same rules as txt_putc). */
void shc_putc(char c_in)
{
    uint8_t ch = (uint8_t)c_in;
    uint8_t r;
    uint16_t off;

    if (ch == '\n') {
        shc_newline();
        return;
    }
    if (ch < 0x20u || ch >= 0x7Fu)
        ch = '.';                          /* control bytes render as '.' */
    if (cur_col >= SCREEN_W)
        shc_newline();                     /* resolve pending wrap */
    r = cur_row;
    off = off_row(r) + cur_col;
    shc_store((uint16_t)screen_buf + off, ch - 0x20u);
    shc_store((uint16_t)dirty_rows + r, 1);
    cur_col++;
}

/* shc_puts: print a NUL-terminated string. */
void shc_puts(const char *s)
{
    for (;;) {
        char c = *s;
        if (c == 0)
            return;
        shc_putc(c);
        s++;
    }
}

/* shc_pwd: print the current directory path. */
void shc_pwd(void)
{
    uint8_t node = fs_get_cwd();
    if (node == 0) {
        shc_puts("/ (root)");              /* "/" alone is easy to miss */
        shc_putc('\n');
        return;
    }
    fs_pwd_str(node);                      /* fills pwd_buf */
    shc_puts(pwd_buf);
    shc_putc('\n');
}

/* shc_echo_plain: print the echo arguments, space-joined, plus newline. */
void shc_echo_plain(void)
{
    uint8_t i;
    for (i = 1; i < sh_argc; i++) {
        if (i != 1)
            shc_putc(' ');
        shc_puts(sh_args[i]);
    }
    shc_putc('\n');
}

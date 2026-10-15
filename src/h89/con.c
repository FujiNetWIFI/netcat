/**
 * @brief   Raw H19 console - Heathkit H89
 * @author  Thomas Cherryhomes
 * @email   thom dot cherryhomes at gmail dot com
 * @license gpl v. 3, see LICENSE for details.
 *
 * The H19 is the terminal, so bytes go to it exactly as they come from the
 * host, and keys go to the host exactly as the H19 sends them. That means
 * going under the OS's console handling: HDOS's .SCOUT/.SCIN with the
 * console driver in raw character mode, or the CP/M BIOS's CONOUT/CONST/CONIN
 * straight from the jump table (the BDOS console calls expand tabs and catch
 * ^C, ^S and ^P).
 *
 * From fujinet-battleship's H89 port (add-h89, src/h89/console.c).
 */

#include <string.h>
#include "con.h"

#ifdef __HDOS__

// HDOS system calls: RST 38H, then the function byte. HDOS is 8080 code and
// leaves IX and IY alone.
void con_out(uint8_t c) __z88dk_fastcall __naked
{
#asm
    ld      a,l
    rst     38h
    defb    2           ; .SCOUT
    ret
#endasm
}

int con_in(void) __naked
{
#asm
    rst     38h
    defb    1           ; .SCIN - carry set when nothing is waiting
    ld      hl,-1
    ret     c
    ld      l,a
    ld      h,0
    ret
#endasm
}

// .CONSL: A = index of the console byte, B = the bits to set, C = the mask of
// bits to change
uint8_t h89ConslIndex, h89ConslBits, h89ConslMask;

static void consl(void) __naked
{
#asm
    ld      a,(_h89ConslBits)
    ld      b,a
    ld      a,(_h89ConslMask)
    ld      c,a
    ld      a,(_h89ConslIndex)
    rst     38h
    defb    6           ; .CONSL
    ret
#endasm
}

static void consl_set(uint8_t index, uint8_t bits, uint8_t mask)
{
    h89ConslIndex = index;
    h89ConslBits = bits;
    h89ConslMask = mask;
    consl();
}

// The five console cells (S.CSLMD..S.CONFL) live at 040.326A in HDOS 2.0's
// system values (HOSDEF: S.VAL at 040.277A)
#define S_CSLMD ((volatile uint8_t *)0x20D6)
#define I_CSLMD 0
#define I_CONTY 1
#define I_CUSOR 2
#define I_CONWI 3
#define I_CONFL 4

#define CSL_ECH 0x80 // suppress echo
#define CSL_RAW 0x04 // raw mode I/O (no CTL-C/S/O/P processing)
#define CSL_WRP 0x02 // wrap lines at width
#define CSL_CHR 0x01 // character mode
#define CTP_MLI 0x20 // map lower case to upper on input
#define CTP_MLO 0x10 // map lower case to upper on output
#define CTP_BKM 0x02 // map backspace to rubout on input
#define CO_FLG 0x01  // CTL-O (discard output) flag
#define CS_FLG 0x80  // CTL-S (hold output) flag

static uint8_t saved[5];

void con_init(void)
{
    memcpy(saved, (void *)S_CSLMD, sizeof(saved));

    // Raw character mode with no echo, so ^C, ^S, ^O and ^P go to the host;
    // no wrap and no width, because the H19 wraps for itself and HDOS would
    // count escape sequences as columns; and no case mapping either way.
    consl_set(I_CSLMD, CSL_ECH | CSL_RAW | CSL_CHR, CSL_ECH | CSL_RAW | CSL_WRP | CSL_CHR);
    consl_set(I_CONTY, 0, CTP_MLI | CTP_MLO | CTP_BKM);
    consl_set(I_CONWI, 255, 0xFF);
    consl_set(I_CONFL, 0, CO_FLG | CS_FLG);
}

void con_exit(void)
{
    consl_set(I_CSLMD, saved[I_CSLMD], 0xFF);
    consl_set(I_CONTY, saved[I_CONTY], 0xFF);
    consl_set(I_CONWI, saved[I_CONWI], 0xFF);
    consl_set(I_CUSOR, 0, 0xFF); // every exit path ends a line
}

#else /* CP/M */

// The BIOS jump table: (0001) points at its WBOOT entry, base+3. CONST is at
// +3 from there, CONIN +6, CONOUT +9. The BIOS may use any register, so IX
// and IY are kept for the C side.
void con_out(uint8_t c) __z88dk_fastcall __naked
{
#asm
    EXTERN  l_dcal
    push    ix
    push    iy
    ld      c,l
    ld      hl,(1)
    ld      de,9
    add     hl,de
    call    l_dcal      ; CONOUT
    pop     iy
    pop     ix
    ret
#endasm
}

int con_in(void) __naked
{
#asm
    EXTERN  l_dcal
    push    ix
    push    iy
    ld      hl,(1)
    ld      de,3
    add     hl,de
    call    l_dcal      ; CONST: A = FF when a character is waiting
    or      a
    ld      hl,-1
    jr      z,con_in_done
    ld      hl,(1)
    ld      de,6
    add     hl,de
    call    l_dcal      ; CONIN
    ld      l,a
    ld      h,0
con_in_done:
    pop     iy
    pop     ix
    ret
#endasm
}

void con_init(void)
{
}

void con_exit(void)
{
}

#endif /* __HDOS__ */

void con_puts(const char *s)
{
    while (*s)
        con_out(*s++);
}

void con_putu(uint16_t n)
{
    char d[6];
    uint8_t i = sizeof(d) - 1;

    d[i] = 0;
    do
    {
        d[--i] = '0' + n % 10;
        n /= 10;
    } while (n);
    con_puts(&d[i]);
}

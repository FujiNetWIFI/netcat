/**
 * @brief   Raw H19 console - Heathkit H89
 * @author  Thomas Cherryhomes
 * @email   thom dot cherryhomes at gmail dot com
 * @license gpl v. 3, see LICENSE for details.
 */

#ifndef CON_H
#define CON_H

#include <stdint.h>

#define CRLF "\015\012"

/** Put the OS console into raw mode (HDOS); call before any other con_ call */
void con_init(void);

/** Put the console back the way it was found */
void con_exit(void);

/** Send one byte to the H19, untouched */
void con_out(uint8_t c) __z88dk_fastcall;

/** The next key, or -1 if none is waiting */
int con_in(void);

void con_puts(const char *s);

void con_putu(uint16_t n);

#endif /* CON_H */

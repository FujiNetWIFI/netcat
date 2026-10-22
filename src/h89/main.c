/**
 * @brief   NetCat - a dumb terminal for the Heathkit H89
 * @author  Thomas Cherryhomes
 * @email   thom dot cherryhomes at gmail dot com
 * @license gpl v. 3, see LICENSE for details.
 * @verbose Main Program
 *
 * One program for CP/M (NC.COM) and HDOS (NC.ABS). The H19 is already a
 * terminal, so this is a pipe: bytes from the host go straight to it, keys go
 * straight to the host, and TELNET and SSH are told term=h19 so the far end
 * draws for it. Everything else (TCP, HTTP, ...) is more likely a text file
 * with bare LF line ends, so there a LF gets the CR the H19 needs in front of
 * it. f5 (ESC W) hangs up.
 */

#include <stdint.h>
#include <string.h>
#include <fujinet-network.h>
#include "con.h"

#define ESC 0x1B
#define CTRL_C 0x03
#define BS 0x08
#define DEL 0x7F

// f5 sends ESC W. The H19 sends the pair back to back at 9600 baud, so an
// ESC with nothing behind it after this many polls is the ESC key itself
// (each poll is a BIOS or HDOS call, roughly 0.1-0.25 ms).
#define KEY_HANGUP 'W'
#define ESC_POLLS 200

// How many unhappy STATUS polls in a row mean the connection has gone.
// Patient while dialling (OPEN returns before SSH has finished its
// handshake), brisk once up. A poll is happy when it says SUCCESS or has
// bytes waiting: a connection already closed can still have a screenful.
#define GRACE_POLLS 2000
#define DROP_POLLS 16

// Read for the screen in pieces this size. The console is 9600 baud, so
// this is half a second of output.
#define RX_CHUNK 512

#define TERM_PARAMS "?term=h19&cols=80&rows=24"

static char line[256];
static char spec[2 + sizeof(line) + sizeof(TERM_PARAMS)];
static uint8_t rxbuf[RX_CHUNK];

// Keys waiting to go to the host
static uint8_t txq[64];
static uint8_t txn;
static uint8_t hangup;

// Not a terminal session (TELNET/SSH): give a bare LF a CR
static uint8_t add_cr;

static const char banner[] =
    "NetCat for the Heathkit H89 - a FujiNet terminal" CRLF
    CRLF
    "Usage: NC <URL>    f5 hangs up." CRLF
    "The command line arrives in upper case; type a case-sensitive URL here." CRLF
    CRLF
    "Enter URL, e.g. N:TELNET://BBS.FOZZTEXX.COM/  (RETURN alone quits)" CRLF
    "URL> ";

/** The byte after an ESC, or -1 if none comes in time */
static int esc_follower(void)
{
    uint8_t i;
    int c;

    for (i = 0; i < ESC_POLLS; i++)
    {
        c = con_in();
        if (c >= 0)
            return c;
    }
    return -1;
}

/** Read a line into line[]; returns its length, 0 to quit */
static uint8_t read_line(void)
{
    uint8_t n = 0;
    int c;

    for (;;)
    {
        c = con_in();
        if (c < 0)
            continue;
        c &= 0x7F;

        if (c == '\r' || c == '\n')
            break;
        if (c == CTRL_C)
        {
            n = 0;
            break;
        }
        if (c == ESC)
        {
            // an arrow or function key: not part of a URL
            esc_follower();
            continue;
        }
        if (c == BS || c == DEL)
        {
            if (n)
            {
                n--;
                con_puts("\010 \010");
            }
            continue;
        }
        if (c >= ' ' && n < sizeof(line) - 1)
        {
            line[n++] = c;
            con_out(c);
        }
    }

    line[n] = 0;
    con_puts(CRLF);
    return n;
}

static char upper(char c)
{
    return (c >= 'a' && c <= 'z') ? c - 'a' + 'A' : c;
}

/** Does s begin with prefix (upper case), ignoring case? */
static uint8_t starts_with(const char *s, const char *prefix)
{
    while (*prefix)
        if (upper(*s++) != *prefix++)
            return 0;
    return 1;
}

/** N:, or N1: to N8: */
static uint8_t has_device(const char *s)
{
    if (upper(s[0]) != 'N')
        return 0;
    if (s[1] == ':')
        return 1;
    return s[1] >= '1' && s[1] <= '8' && s[2] == ':';
}

/**
 * The devicespec from what was typed: N: in front if it has no device, and
 * the H19's terminal type and size on TELNET and SSH URLs that carry no query
 * of their own (firmware 1.6.1 and later read them there).
 */
static void make_spec(const char *url)
{
    const char *u;

    while (*url == ' ')
        url++;

    spec[0] = 0;
    if (!has_device(url))
        strcpy(spec, "N:");
    strcat(spec, url);

    u = strchr(spec, ':') + 1;
    if (!starts_with(u, "TELNET://") && !starts_with(u, "SSH://"))
        add_cr = 1;
    else if (!strchr(spec, '?'))
        strcat(spec, TERM_PARAMS);
}

/** Queue one key for the host, f5 sets hangup instead; 0 if none taken */
static uint8_t take_key(void)
{
    int c, n;

    if (hangup || txn > sizeof(txq) - 2)
        return 0;

    c = con_in();
    if (c < 0)
        return 0;

    if (c == ESC)
    {
        n = esc_follower();
        if (n == KEY_HANGUP)
        {
            hangup = 1;
            return 0;
        }
        txq[txn++] = ESC;
        if (n >= 0)
            txq[txn++] = n;
        return 1;
    }
    txq[txn++] = c;
    return 1;
}

static void send_keys(void)
{
    while (take_key())
        ;

    if (txn)
    {
        network_write(spec, txq, txn);
        txn = 0;
    }
}

/** Show what the host sent; returns 0 when the connection has gone */
static uint8_t from_host(void)
{
    static uint16_t bad;
    static uint8_t up, last;
    uint16_t bw, i, n;
    uint8_t c, err;

    if (network_status(spec, &bw, &c, &err) != FN_ERR_OK)
        bw = err = 0;

    if (err == NETWORK_SUCCESS || bw)
    {
        up = 1;
        bad = 0;
    }
    else if (++bad > (up ? DROP_POLLS : GRACE_POLLS))
        return 0;

    if (bw)
    {
        n = bw > sizeof(rxbuf) ? sizeof(rxbuf) : bw;
        if (network_read(spec, rxbuf, n) > 0)
        {
            for (i = 0; i < n; i++)
            {
                c = rxbuf[i];
                if (add_cr && c == '\n' && last != '\r')
                    con_out('\r');
                con_out(c);
                last = c;
                // keys typed while a long screen draws go with the next send
                take_key();
            }
        }
    }
    return 1;
}

static void session(void)
{
    uint16_t bw;
    uint8_t c, err;

    con_puts("Connecting to ");
    con_puts(spec);
    con_puts("  (f5 hangs up)" CRLF);

    if (network_open(spec, OPEN_MODE_RW, OPEN_TRANS_NONE) != FN_ERR_OK)
    {
        con_puts("Could not connect");
        if (network_status(spec, &bw, &c, &err) == FN_ERR_OK && err > NETWORK_SUCCESS)
        {
            con_puts(": error ");
            con_putu(err);
        }
        con_puts("." CRLF);
        return;
    }

    for (;;)
    {
        send_keys();
        if (hangup)
        {
            network_close(spec);
            con_puts(CRLF "Hung up." CRLF);
            return;
        }
        if (!from_host())
        {
            network_close(spec);
            con_puts(CRLF "Disconnected." CRLF);
            return;
        }
    }
}

int main(int argc, char **argv)
{
    con_init();
    network_init();

    if (argc > 1)
        make_spec(argv[1]);
    else
    {
        con_puts(banner);
        if (!read_line())
        {
            con_exit();
            return 0;
        }
        make_spec(line);
    }

    session();

    con_exit();
    return 0;
}

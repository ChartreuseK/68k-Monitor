# 68k-Monitor
A simple ROM based monitor, for my home-brew 68000 computer

# Files
##### Monitor-Simple.x68
 * My original simple polling driven serial ROM monitor for my home-brew 68000 based computer.
 * Polls the 68681 DUART for each character received. 
 * Can easily be modified to work with other I/O devices.
##### Monitor.x68
 * Currently the same file as Monitor-Simple.x68
##### Monitor_narrowdisp.x68
 * The currently up-to-date version of my Monitor
 * Has proper interrupt and exception vector support
 * DUART attached to AUTOVECTOR1 interrupt, allowing interrupt driven I/O
 * Uses interrupts and a ring buffer for reading from the serial port
 * Has a 300Hz timer interrupt setup on the 68681 DUART to provide a system tick
 * 50Hz and 60Hz interrupt routines divided out of the 300Hz timer
 * YM2149F chip-tune interrupt driven playback routines. Using the MYM format from the OSDK (http://osdk.defence-force.org/index?page=documentation&subpage=ym2mym) since my computer only has 16K of RAM and the full YM format needs more to decompress. This routine 'works' but every frame (128 register dumps at 50Hz) it takes around a half second to decompress the next chunk which stalls playback. This needs to be optimized, or moved away from purely being part of the 50Hz interrupt.
 * Defines added for adjusting the display width of the memory dump routines to allow support for different terminal widths.
 * Currently optimized for a 32 character wide colour terminal, built with an ATMEGA328.
 * Added ANSI escape code colour to the messages.


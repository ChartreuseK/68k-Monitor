*-----------------------------------------------------------
* Title      : 68k Homebrew ROM Monitor
* Written by : Hayden Kroepfl (ChartreuseK)
* Date       : August 24th 2015
* Description: A simple ROM monitor for my homebrew 68k
*              breadboard computer.
*-----------------------------------------------------------
*
* To make this responsive to different terminal widths we need to change the number of bytes printed
* on a line from 16, which fits exactly on a 72 column screen, to an ammount based on a formula.
*  Sizes: 
*   Address:      "000000: " 8
*   Each Byte:    "00 "      3
*   Start ASCII:  "|"        1
*   Each ASCII:   "."        1
*   End ASCII:    "|"        1
*
*   Width = 8 + numBytes*(3 + 1) + 2
*   numBytes = (Width - 10)/4 = (Width - 10)>>2
*  Examples:
*    (80 - 10)/4 = 70/4 = 16 Bytes
*    (40 - 10)/4 = 30/4 =  7 Bytes
*    (32 - 10)/4 = 22/4 =  5 Bytes
* On small screens we should not show the start and end characters on the ASCII section
* 40 Characters wide or less
*    (40 - 8)/4  = 32/4 =  8 Bytes
*    (32 - 8)/4  = 24/4 =  6 Bytes


* 000000-03FFFF ROM  (138 output 0)
* 040000-043FFF RAM  (138 output 1)
* 044000-07FFFF RAM mirrors (138 output 1)
* 080000-0BFFFF      (138 output 2)
* 0C0000-0FFFFF      (138 output 3)
* 100000-13FFFF      (138 output 4)
* 140000-17FFFF      (138 output 5)
* 180000-180003 YM2149 ((138 output 6)
* 180004-1BFFFF      (138 output 6)
* 1C0000-1C000F DUART (138 output 7)
* 1C0010-1FFFFF DUART mirrors (138 output 7)


**********************************
* Defines
*
RAM_START           equ     $40000
RAM_END             equ     $44000
MAX_LINE_LENGTH     equ     80
SERIAL_RING_LENGTH  equ     40

TERM_WIDTH          equ     32
TERM_HEIGHT         equ     24

DUMP_BYTES_LINE     equ     6           * 8 For 72 width+
DUMP_BYTES_QUICK    equ     16          * Still a handy width even if it wraps on small screens
DUMP_BYTES_PAGE     equ     138         * 256 For 72 width+
 
**********************************
* Colours
COLOR_BLACK    equ 0
COLOR_DGREY    equ 8
COLOR_DRED     equ 1
COLOR_RED      equ 9
COLOR_DGREEN   equ 2
COLOR_GREEN    equ 10
COLOR_DYELLOW  equ 3
COLOR_ORANGE   equ 3
COLOR_YELLOW   equ 11
COLOR_DBLUE    equ 4
COLOR_BLUE     equ 12
COLOR_DMAGENTA equ 5
COLOR_PURPLE   equ 5
COLOR_MAGENTA  equ 13
COLOR_DCYAN    equ 6
COLOR_CYAN     equ 14
COLOR_LGREY    equ 7
COLOR_WHITE    equ 15


COLOR_BANNER  equ COLOR_GREEN
COLOR_HELP    equ COLOR_BLUE
COLOR_PROMPT  equ COLOR_MAGENTA
COLOR_INPUT   equ COLOR_WHITE
COLOR_DEFAULT equ COLOR_WHITE
COLOR_ADDR    equ COLOR_MAGENTA
COLOR_BYTES   equ COLOR_CYAN
COLOR_ASCII   equ COLOR_WHITE
COLOR_ERROR   equ COLOR_DRED
 
 
*********************************
* 68681 Duart Register Addresses
*
DUART equ $1C0000       * Base Addr of DUART
MRA   equ DUART+0       * Mode Register A           (R/W)
SRA   equ DUART+2       * Status Register A         (r)
CSRA  equ DUART+2       * Clock Select Register A   (w)
CRA   equ DUART+4       * Commands Register A       (w)
RBA   equ DUART+6       * Receiver Buffer A         (r)
TBA   equ DUART+6       * Transmitter Buffer A      (w)
ACR   equ DUART+8       * Aux. Control Register     (R/W)
ISR   equ DUART+10      * Interrupt Status Register (R)
IMR   equ DUART+10      * Interrupt Mask Register   (W)
CUR   equ DUART+12      * Counter MSB               (R)
CTUR  equ DUART+12      * Counter/Timer Upper Reg   (W)
CLR   equ DUART+14      * Counter LSB               (R)
CTLR  equ DUART+14      * Counter/Timer Lower Reg   (W)
MRB   equ DUART+16      * Mode Register B           (R/W)
SRB   equ DUART+18      * Status Register B         (R)
CSRB  equ DUART+18      * Clock Select Register B   (W)
CRB   equ DUART+20      * Commands Register B       (W)
RBB   equ DUART+22      * Reciever Buffer B         (R)
TBB   equ DUART+22      * Transmitter Buffer B      (W)
IVR   equ DUART+24      * Interrupt Vector Register (R/W)
IPUL  equ DUART+26      * Unlatched Input Port values (R)
OPCR  equ DUART+26      * Output Port Configuration Register (W)
STRT_CNTR equ DUART+28  * Start-Counter Command (R)
OPR_SET   equ DUART+28  * Output Port Bit Set Command (W)
STOP_CNTR equ DUART+30  * Stop-Counter Command (R) / Clear timer interrupt
OPR_CLR   equ DUART+28  * Output Port Bit Clear Command (W)

**********************************
* ASCII Control Characters
*
BEL   equ $07
BKSP  equ $08       * CTRL-H
TAB   equ $09
LF    equ $0A
CR    equ $0D
ESC   equ $1B

CTRLC	EQU	$03     
CTRLX	EQU	$18     * Line Clear


**********************************
* Variables
*
varCurAddr     equ   RAM_END-4                       * Last address accessed
varLineBuf     equ   varCurAddr-MAX_LINE_LENGTH-4    * Line buffer
varSerialRing  equ   varLineBuf-SERIAL_RING_LENGTH
varSRingStart  equ   varSerialRing-1
varSRingEnd    equ   varSRingStart-1
varSysCntr5    equ   varSRingEnd-1                   * System Timer 50hz divider/counter 0-4
varSysCntr6    equ   varSysCntr5-1                   * System Timer 60hz divider/counter 0-5 (Could probably pack these two into one byte)
* Make sure the above is aligned to a multiple of 4, as the next two MUST be on a word boundary (Maybe move these to the first declarations)
varHndlr50hz   equ   varSysCntr6-4                   * Pointer to 50hz handler
varHndlr60hz   equ   varHndlr50hz-4                  * Pointer to 60hz handler
varHndlrSIGINT equ   varHndlr60hz-4                  * Pointer to CTRLC / SIGINT handler (Not yet implemented)

varMYMIndex    equ   varHndlrSIGINT-4                     * Index into the file/memory
varMYMEndPos   equ   varMYMIndex-4                   * End Position, when Index=This we're done
varMYMFramePos equ   varMYMEndPos-1                  * Current column into frame (0-127)
varMYMCurByte  equ   varMYMFramePos-1                * Current byte value being examined in data
varMYMBitPos   equ   varMYMCurByte-1                 * Current bit in the above byte being examined
varMYMFillBuf  equ   varMYMBitPos-1                  * Semaphore to fill buffer
varMYMCurRegs  equ   varMYMFillBuf-16                * Previous value for the registers
varMYMBuf      equ   varMYMCurRegs-2048              * 2k buffer for decompressed mym data 
varLast        equ   varMYMBuf


**********************************
* Supervisor Stack Begins after system variables
STACK_START         equ    varLast                   * Make sure stack is aligned to word boundary



**** PROGRAM STARTS HERE ****
    
    ORG     $0000
    
**** FIRST 8 bytes loaded after reset/Execption Vector Table ****
    DC.l    STACK_START  * 0 - Supervisor stack pointer
    DC.l    START        *     Initial PC    
    DC.l    RESETVECT    * 2 - Bus Error
    DC.l    RESETVECT    * 3 - Address Error
    DC.l    RESETVECT    * 4 - ILLEGAL Instruction
    DC.l    RESETVECT    * 5 - Divide by Zero
    DC.l    RESETVECT    * 6 - CHK
    DC.l    UNHANDLED    * 7 - TRAPV
    DC.l    UNHANDLED    * 8 - Privilage Violation
    DC.l    UNHANDLED    * 9 - Trace
    DC.l    UNHANDLED    * 10- Line 1010/Unused
    DC.l    UNHANDLED    * 11- Line 1111/Unused
    DC.l    UNHANDLED    * 12- Unused
    DC.l    UNHANDLED    * 13- Unused
    DC.l    UNHANDLED    * 14- Unused
    DC.l    UNHANDLED    * 15- Unused
    DC.l    UNHANDLED    * 16- Uninitialized Interrupt Vector
    DC.l    UNHANDLED    * 17- Unused
    DC.l    UNHANDLED    * 18- Unused
    DC.l    UNHANDLED    * 19- Unused
    DC.l    UNHANDLED    * 20- Unused
    DC.l    UNHANDLED    * 21- Unused
    DC.l    UNHANDLED    * 22- Unused
    DC.l    UNHANDLED    * 23- Unused
    DC.l    UNHANDLED    * 24- Spurious Interrupt
    DC.l    AUTOVECT1    * 25- Autovector 1
    DC.l    UNHANDLED    * 26- Autovector 2
    DC.l    UNHANDLED    * 27- Autovector 3
    DC.l    UNHANDLED    * 28- Autovector 4
    DC.l    UNHANDLED    * 29- Autovector 5
    DC.l    UNHANDLED    * 30- Autovector 6
    DC.l    UNHANDLED    * 31- Autovector 7
    DC.l    UNHANDLED    * 32- TRAP #0
    DC.l    UNHANDLED    * 33- TRAP #1
    DC.l    UNHANDLED    * 34- TRAP #2
    DC.l    UNHANDLED    * 35- TRAP #3
    DC.l    UNHANDLED    * 36- TRAP #4
    DC.l    UNHANDLED    * 37- TRAP #5
    DC.l    UNHANDLED    * 38- TRAP #6
    DC.l    UNHANDLED    * 39- TRAP #7
    DC.l    UNHANDLED    * 40- TRAP #8
    DC.l    UNHANDLED    * 41- TRAP #9
    DC.l    UNHANDLED    * 42- TRAP #10
    DC.l    UNHANDLED    * 43- TRAP #11
    DC.l    UNHANDLED    * 44- TRAP #12
    DC.l    UNHANDLED    * 45- TRAP #13
    DC.l    UNHANDLED    * 46- TRAP #14
    DC.l    UNHANDLED    * 47- TRAP #15
    * 48-63 Unassigned
    * 64-255 User, 



   

    
    
********************************************
* Cold start entry point
*
START:
    lea     STACK_START, SP     * Set our stack pointer to be sure
    jsr     initDuart           * Setup the serial port
    jsr     clearScreen         * Clear the terminal
    
********************************************
* Simple Ram Readback Test
*    
ramCheck:
    lea     msgRamCheck, A0
    bsr.w   printString
    lea     RAM_START, A2
 .loop:
    move.b  #$AA, (A2)   * First test with 10101010
    cmp.b   #$AA, (A2)
    bne.s   .fail
    move.b  #$55, (A2)   * Then with 01010101
    cmp.b   #$55, (A2)
    bne.s   .fail
    move.b  #$00, (A2)   * And finally clear the memory
    cmp.b   #$00, (A2)+  * And move to the next byte
    bne.s   .fail 
    cmp.l   #RAM_END, A2  
    blt.s   .loop        * While we're still below the end of ram to check
    bra.s   .succ
 .fail:                  * One of the bytes of RAM failed to readback test
    lea     msgRamFail, A0
    bsr.w   printString
    move.l  A2, D0
    bsr.w   printHexLong * Print out the address that failed
    bsr.w   printNewline
 .haltloop:              * Sit forever in the halt loop
    bra.s   .haltloop
 .succ:                  * All bytes passed the readback test
    lea     msgRamPass, A0
    bsr.w   printString


    lea     varSRingStart, a0   * Ring buffer ends   
    move.b  #0, (a0)
    lea     varSRingEnd,   a0
    move.b  #0, (a0)
    * Enable Interrupts
    move.w #$2000, SR       * Supervisor mode, no trace, interrupt mask 000


**************************************************
* Warm Restart entry point
*
monitorStart:
    move.l  #COLOR_BANNER, d0          * Dark Green
    bsr.w   setColor

    lea     msgBanner, A0   * Show our banner
    bsr.w   printString
    
    move.l  #COLOR_HELP, d0         * Bright Blue
    bsr.w   setColor
    lea     msgHelp,   A0   * And the command help message
    bsr.w   printString

monitorLine:                * Our main monitor loop
    move.l  #COLOR_PROMPT, d0         * Bright Magenta
    bsr.w   setColor
    lea     msgPrompt, a0   * Prompt
    bsr.w   printString     
    
    move.l  #COLOR_INPUT, d0
    bsr.w   setColor
    
    bsr.w   readLine        * Read in the line
    bsr.w   lineToUpper     * Convert to upper-case for ease of parsing
    
    move.l  #COLOR_DEFAULT, d0         * Bright White
    bsr.w   setColor
    bsr.w   parseLine       * Then parse and respond to the line
    
    bra.s   monitorLine
    


***************************************
* Converts input line to uppercase
lineToUpper:
    lea     varLineBuf, a0   * Get the start of the line buffer
 .loop:
    move.b  (a0), d0         * Read in a character
    cmp.b   #'a', d0         
    blt.s   .next            * Is it less than lower-case 'a', then move on
    cmp.b   #'z', d0
    bgt.s   .next            * Is it greater than lower-case 'z', then move on
    sub.b   #$20, d0         * Then convert a to A, b to B, etc.
 .next:
    move.b  d0, (a0)+        * Store the character back into a0, and move to the next
    bne.s   .loop            * Keep going till we hit a null terminator
    rts

***************************************
* Parse Line
parseLine:
    movem.l a2-a3, -(SP)        * Save registers
    lea     varLineBuf, a0
 .findCommand:
    move.b  (a0)+, d0
    cmp.b   #' ', d0            * Ignore spaces
    beq.w   .findCommand    
    cmp.b   #'E', d0            * Examine command
    beq.w   .examine
    cmp.b   #'D', d0            * Deposit command
    beq.w   .deposit
    cmp.b   #'R', d0            * Run command
    beq.w   .run
    cmp.b   #'H', d0            * Help command
    beq.w   .help
    cmp.b   #0, d0              * Ignore blank lines
    beq.s   .exit               
 .invalid:   
    move.l  #COLOR_ERROR, d0    
    bsr.w   setColor
    
    lea     msgInvalidCommand, a0
    bsr.w   printString
 .exit:
    movem.l (SP)+, a2-a3        * Restore registers
    rts

**********************
* Examines memory addresses
* Valid modes:
*   e ADDR                  Displays a single byte
*   e ADDR-ADDR             Dispalys all bytes between the two addresses
*   e ADDR+LEN              Dispays LEN bytes after ADDR
*   e ADDR;                 Interactive mode, space shows a page, enter shows quick amount.
*   e ADDR.                 Quick line, displays one line 
 .examine:
    bsr.w   parseNumber         * Read in the start address
    tst.b   d1                  * Make sure it's valid (parseNumber returns non-zero in d1 for failure)
    bne.w   .invalidAddr        
    move.l  d0, a3              * Save the start address
 .exloop:
    move.b  (a0)+, d0
    cmp.b   #' ', d0            * Ignore spaces
    beq.s   .exloop
    cmp.b   #'-', d0            * Check if it's a range specifier
    beq.s   .exrange
    cmp.b   #'+', d0            * Check if it's a length specifier
    beq.s   .exlength
    cmp.b   #';', d0            * Check if we're going interactive
    beq.s   .exinter
    cmp.b   #'.', d0            * Check if quick 16 
    beq.s   .exquick
    move.l  #1, d0              * Otherwise read in a single byte
    bra.s   .exend              
 .exrange:
    bsr.w   parseNumber         * Find the end address
    tst.b   d1                  * Check if we found a valid address
    bne.w   .invalidAddr
    sub.l   a3, d0              * Get the length
    bra.s   .exend
 .exquick:                      * Quick mode means show quick amount bytes
    move.l  #DUMP_BYTES_QUICK, d0
    bra.s   .exend
 .exlength:                     * Length mode means a length is specified
    bsr.w   parseNumber         * Find the length
    tst.b   d1
    bne.w   .invalidAddr
 .exend:                        * We're done parsing, give the parameters to dumpRAM and exit
    move.l  a3, a0
    bsr.w   dumpRAM
    bra.s   .exit
 .exinter:                      * Interactive mode, Space dumps a page worth of lines, enter shows quick amount
    move.l  a3, a0              * Current Address
    move.l  #DUMP_BYTES_QUICK, d0 * Quick amount
    bsr.w   dumpRAM             * Dump this line
    add.l   #DUMP_BYTES_QUICK, a3 * Move up the current address by Quick amount bytes
 .exinterend:
    bsr.w   inChar
    cmp.b   #CR, d0             * Display another line
    beq.s   .exinter
    cmp.b   #' ', d0            * Display a page 
    beq.s   .exinterpage
    bra.s   .exit               * Otherwise exit
 .exinterpage:
    move.l  a3, a0

    move.l  #DUMP_BYTES_PAGE, d0  * 138 bytes can fit in the 32x24 screen, 256 is 16 lines on 80x25
    bsr.w   dumpRAM               * Dump 
    add.l   #DUMP_BYTES_PAGE, a3  * Move up the current address by 256
    bra.s   .exinterend

****************************************
* Deposit values into RAM
* d ADDR VAL VAL            Deposit value(s) into RAM
* d ADDR VAL VAL;           Deposit values, continue with values on next line
*  VAL VAL VAL;              - Continuing with further continue
* d: VAL VAL                Continue depositing values after the last address written to
 .deposit:
    move.b  (a0), d0
    cmp.b   #':', d0            * Check if we want to continue from last
    beq.s   .depCont
    
    bsr.w   parseNumber         * Otherwise read the address
    tst.b   d1
    bne.s   .invalidAddr
    move.l  d0, a3              * Save the start address
 .depLoop:
    move.b  (a0), d0            
    cmp.b   #';', d0            * Check for continue
    beq.s   .depMultiline
    tst     d0                  * Check for the end of line
    beq     .depEnd
    
    bsr.w   parseNumber         * Otherwise read a value
    tst.b   d1
    bne.s   .invalidVal
    cmp.w   #255, d0            * Make sure it's a byte
    bgt.s   .invalidVal
    
    move.b  d0, (a3)+           * Store the value into memory
    bra.s   .depLoop
    
 .depCont:
    move.l  varCurAddr, a3      * Read in the last address 
    addq.l  #1, a0              * Skip over the ':'
    bra.s   .depLoop
    
 .depMultiline:
    move.l  #COLOR_PROMPT, d0   
    bsr.w   setColor
    lea     msgDepositPrompt, a0
    bsr.w   printString
    
    move.l  #COLOR_INPUT, d0   
    bsr.w   setColor
    bsr.w   readLine            * Read in the next line to be parsed
    
    bsr.w   lineToUpper         * Convert to uppercase
    lea     varLineBuf, a0      * Reset our buffer pointer
    bra.s   .depLoop            * And jump back to decoding
 .depEnd:
    move.l  a3, varCurAddr
    bra.w   .exit
****************************************
* 
 .run:
    bsr.w   parseNumber         * Otherwise read the address
    tst.b   d1
    bne.s   .invalidAddr
    move.l  d0, a0
    jsr     (a0)                * Jump to the code! 
                                * Go as subroutine to allow code to return to us
    jmp     monitorStart        * Warm start after returning so everything is in
                                * a known state.
    
 .help:
    lea     msgHelp, a0
    bsr.w   printString
    bra.w   .exit
 .invalidAddr:
    lea     msgInvalidAddress, a0
    bsr.w   printString
    bra.w   .exit
 .invalidVal:
    lea     msgInvalidValue, a0
    bsr.w   printString
    bra.w   .exit
    
    
**************************************
* Find and parse a hex number
*  Starting address in A0
*  Number returned in D0
*  Status in D1   (0 success, 1 fail)
*  TODO: Try and merge first digit code with remaining digit code
parseNumber:
    eor.l   d0, d0           * Zero out d0
    move.b  (a0)+, d0
    cmp.b   #' ', d0         * Ignore all leading spaces
    beq.s   parseNumber
    cmp.b   #'0', d0         * Look for hex digits 0-9
    blt.s   .invalid
    cmp.b   #'9', d0
    ble.s   .firstdigit1

    cmp.b   #'A', d0         * Look for hex digits A-F
    blt.s   .invalid    
    cmp.b   #'F', d0
    ble.s   .firstdigit2
 .invalid:
    move.l  #1, d1          * Invalid character, mark failure and return
    rts
 .firstdigit2:
    sub.b   #'7', d0        * Turn 'A' to 10
    bra.s   .loop
 .firstdigit1:
    sub.b   #'0', d0        * Turn '0' to 0
 .loop:
    move.b  (a0)+, d1       * Read in a digit
    cmp.b   #'0', d1        * Look for hex digits 0-9
    blt.s   .end            * Any other characters mean we're done reading
    cmp.b   #'9', d1
    ble.s   .digit1
    cmp.b   #'A', d1        * Look for hex digits A-F
    blt.s   .end
    cmp.b   #'F', d1
    ble.s   .digit2

.end:                       * We hit a non-hex digit character, we're done parsing
    subq.l  #1, a0          * Move the pointer back before the end character we read
    move.l  #0, d1
    rts
 .digit2:
    sub.b   #'7', d1        * Turn 'A' to 10
    bra.s   .digit3
 .digit1:
    sub.b   #'0', d1        * Turn '0' to 0
 .digit3:
    lsl.l   #4, d0          * Shift over to the next nybble
    add.b   d1, d0          * Place in our current nybble (could be or.b instead)
    bra.s   .loop
    
    
****************************************
* Dumps a section of RAM to the screen
* Displays both hex values and ASCII characters
* d0 - Number of bytes to dump
* a0 - Start Address
dumpRAM:
    movem.l d2-d4/a2, -(SP)  * Save registers
    move.l  a0, a2           * Save the start address
    move.l  d0, d2           * And the number of bytes
 .line:
    move.l  #COLOR_ADDR, d0   
    bsr.w   setColor 
    move.l  a2, d0          
    bsr.w   printHexAddr     * Starting address of this line
    move.l  #COLOR_BYTES, d0   
    bsr.w   setColor
    
    move.b  #' ', d0
    bsr.w   outChar          * Space out bytes
*    lea     msgColonSpace, a0
*    bsr.w   printString
    move.l  #DUMP_BYTES_LINE, d3 * Bytes that can be printed on a line
    move.l  d3, d4           * Save number of bytes on this line
 .hexbyte:
    tst.l   d2               * Check if we're out of bytes
    beq.s   .endbytesShort
    tst.b   d3               * Check if we're done this line
    beq.s   .endbytes    
    move.b  (a2)+, d0        * Read a byte in from RAM
    bsr.w   printHexByte     * Display it
    move.b  #' ', d0
    bsr.w   outChar          * Space out bytes
    subq.l  #1, d3    
    subq.l  #1, d2        
    bra.s   .hexbyte
 .endbytesShort:
    sub.b   d3, d4           * Make d4 the actual number of bytes on this line
    move.b  #' ', d0
 .endbytesShortLoop:
    tst.b   d3               * Check if we ended the line
    beq.s   .endbytes
    move.b  #' ', d0
    bsr.w   outChar          * Three spaces to pad out
    move.b  #' ', d0
    bsr.w   outChar
    move.b  #' ', d0
    bsr.w   outChar
    
    subq.b  #1, d3
    bra.s   .endbytesShortLoop
 .endbytes:
    suba.l  d4, a2           * Return to the start address of this line
    move.l  #COLOR_ASCII, d0   
    bsr.w   setColor
 .endbytesLoop:
    tst.b   d4               * Check if we're done printing ascii
    beq     .endline    
    subq.b  #1, d4
    move.b  (a2)+, d0        * Read the byte again
    cmp.b   #' ', d0         * Lowest printable character
    blt.s   .unprintable
    cmp.b   #'~', d0         * Highest printable character
    bgt.s   .unprintable
    bsr.w   outChar
    bra.s   .endbytesLoop
 .unprintable:
    move.b  #'.', d0
    bsr.w   outChar
    bra.s   .endbytesLoop
 .endline:
    lea     msgNewline, a0
    bsr.w   printString
    tst.l   d2
    ble.s   .end
    bra.w   .line
 .end:
    movem.l (SP)+, d2-d4/a2  * Restore registers
    rts
    
    
        
    
******
* Read in a line into the line buffer
readLine:
    movem.l d2/a2, -(SP)     * Save changed registers
    lea     varLineBuf, a2   * Start of the lineBuffer
    eor.w   d2, d2           * Clear the character counter
 .loop:
    bsr.w   inChar           * Read a character from the serial port
    cmp.b   #BKSP, d0        * Is it a backspace?
    beq.s   .backspace
    cmp.b   #CTRLX, d0       * Is it Ctrl-H (Line Clear)?
    beq.s   .lineclear
    cmp.b   #CR, d0          * Is it a carriage return?
    beq.s   .endline
    cmp.b   #LF, d0          * Is it anything else but a LF?
    beq.s   .loop            * Ignore LFs and get the next character
 .char:                      * Normal character to be inserted into the buffer
    cmp.w   #MAX_LINE_LENGTH, d2
    bge.s   .loop            * If the buffer is full ignore the character
    move.b  d0, (a2)+        * Otherwise store the character
    addq.w  #1, d2           * Increment character count
    bsr.w   outChar          * Echo the character
    bra.s   .loop            * And get the next one
 .backspace:
    tst.w   d2               * Are we at the beginning of the line?
    beq.s   .loop            * Then ignore it
    bsr.w   outChar          * Backspace
    move.b  #' ', d0
    bsr.w   outChar          * Space
    move.b  #BKSP, d0
    bsr.w   outChar          * Backspace
    subq.l  #1, a2           * Move back in the buffer
    subq.l  #1, d2           * And current character count
    bra.s   .loop            * And goto the next character
 .lineclear:
    tst     d2               * Anything to clear?
    beq.s   .loop            * If not, fetch the next character
    suba.l  d2, a2           * Return to the start of the buffer
 .lineclearloop:
    move.b  #BKSP, d0
    bsr.w   outChar          * Backspace
    move.b  #' ', d0
    bsr.w   outChar          * Space
    move.b  #BKSP, d0
    bsr.w   outChar          * Backspace
    subq.w  #1, d2          
    bne.s   .lineclearloop   * Go till the start of the line
    bra.s   .loop   
 .endline:
    bsr.w   outChar          * Echo the CR
   * move.b  #LF, d0
   * bsr.w   outChar          * Line feed to be safe
    move.b  #0, (a2)         * Terminate the line (Buffer is longer than max to allow this at full length)
    movea.l a2, a0           * Ready the pointer to return (if needed)
    movem.l (SP)+, d2/a2     * Restore registers
    rts                      * And return



******
* Set Color
* 
setColor:
    movem.l d2, -(SP)
    move.l  d0, d2          * Save our color argument
    bsr.s   printCSI         * Escape code start
    cmp.l   #15, d2         * Only colours 0-15 supported
    bgt.s   .ignore
    
    move.b  #'0', d0
    cmp.l   #8, d2
    blt.s   .normal
    sub.l   #8, d2          * If color >= 8 then it should be bolded
    move.b  #'1', d0
 .normal:
    bsr.w   outChar
    move.b  #';', d0
    bsr.w   outChar
    move.b  #'3', d0        * Foreground text is 30-37
    bsr.w   outChar
    add.l   #'0', d2        * Adjust our color 
    move.b  d2, d0
    bsr.w   outChar
 .ignore:
    move.b  #'m', d0        * End of escape sequence, graphical changes
    bsr.w   outChar
    
    movem.l (SP)+, d2
    rts
    
******
* Clear screen
clearScreen:
   bsr.s    printCSI    * Clear the entire screen
   move.b   #'2', d0
   bsr.w    outChar
   move.b   #'J', d0
   bsr.w    outChar
   
   bsr.s    printCSI    * Home the cursor
   move.b   #'H', d0
   bsr.w    outChar
   rts
   
******
* Prints the CSI (Control Sequence Indicatior) ESC[ to signal escape sequence
printCSI:
    move.b #27, d0
    bsr.s  outChar
    move.b #'[', d0
    bsr.s  outChar
    rts
******
* Prints a newline (CR, LF)
printNewline:
    lea     msgNewline, a0
******
* Print a null terminated string
*
printString:
 .loop:
    move.b  (a0)+, d0    * Read in character
    beq.s   .end         * Check for the null
    
    bsr.s   outChar      * Otherwise write the character
    bra.s   .loop        * And continue
 .end:
    rts

** KEEP All printHex functions together **
******
* Print a hex word
printHexWord:
    move.l  d2, -(SP)    * Save D2
    move.l  d0, d2       * Save the address in d2
    
    rol.l   #8, d2       * 4321 -> 3214
    rol.l   #8, d2       * 3214 -> 2143 
    bra.s   printHex_wordentry  * Print out the last 16 bits
*****
* Print a hex 24-bit address
printHexAddr:
    move.l d2, -(SP)     * Save D2
    move.l d0, d2          * Save the address in d2
    
    rol.l   #8, d2       * 4321 -> 3214
    bra.s   printHex_addrentry  * Print out the last 24 bits
******
* Print a hex long
printHexLong:
    move.l  d2, -(SP)     * Save D2
    move.l  d0, d2        * Save the address in d2
    
    rol.l   #8, d2        * 4321 -> 3214 high byte in low
    move.l  d2, d0
    bsr.s   printHexByte  * Print the high byte (24-31)
printHex_addrentry:     
    rol.l   #8, d2        * 3214 -> 2143 middle-high byte in low
    move.l  d2, d0              
    bsr.s   printHexByte  * Print the high-middle byte (16-23)
printHex_wordentry:    
    rol.l   #8, d2        * 2143 -> 1432 Middle byte in low
    move.l  d2, d0
    bsr.s   printHexByte  * Print the middle byte (8-15)
    rol.l   #8, d2
    move.l  d2, d0
    bsr.s   printHexByte  * Print the low byte (0-7)
    
    move.l (SP)+, d2      * Restore D2
    RTS
    
******
* Print a hex byte
*  - Takes byte in D0
printHexByte:
    move.l  D2, -(SP)
    move.b  D0, D2
    lsr.b   #$4, D0
    add.b   #'0', D0
    cmp.b   #'9', D0     * Check if the hex number was from 0-9
    ble.s   .second
    add.b   #7, D0       * Shift 0xA-0xF from ':' to 'A'
.second:
    bsr.s   outChar      * Print the digit
    andi.b  #$0F, D2     * Now we want the lower digit Mask only the lower digit
    add.b   #'0', D2
    cmp.b   #'9', D2     * Same as before    
    ble.s   .end
    add.b   #7, D2
.end:
    move.b  D2, D0
    bsr.s   outChar      * Print the lower digit
    move.l  (SP)+, D2
    rts
    
    
    
    
    
*****
* Writes a character to Port A, blocking if not ready (Full buffer)
*  - Takes a character in D0
outChar:
    btst    #2, SRA      * Check if transmitter ready bit is set
    beq     outChar     
    move.b  d0, TBA      * Transmit Character
    rts

*****
* Reads in a character from Port A, blocking if none available
*  - Returns character in D0
*
inChar:
    lea     varSRingStart, a0
    lea     varSRingEnd,   a1
 .nodata:
    eor.l   d0, d0
    move.b  (a1), d1
    move.b  (a0), d0
    cmp.b   d0, d1     * Check if the ring buffer has data in it
    beq.s   .nodata
    
    * POSSIBLE RACE CONDITION - if ring buffer is full when we read this byte
    *  the buffer may be double incremented (start and end) and lose bytes, I think?
    add.b   #1, (a0)     * Increment the start of the buffer
    cmp.b   #SERIAL_RING_LENGTH, (a0)
    blt.s   .nowrap      * Check if we hit the end and need to wrap
    sub.b   #SERIAL_RING_LENGTH, (a0)
 .nowrap:
    lea     varSerialRing, a1
    add.b   #1, d0
    add.l   d0, a1       * Address the ring buffer start
    move.b (a1), d0      * We got this byte

    rts
    
*****
* Reads in a character from Port A, blocking if none available
*  - Returns character in D0
*    
inCharPoll:
    btst    #0,  SRA     * Check if receiver ready bit is set
    beq     inChar
    move.b  RBA, d0      * Read Character into D0
    rts
    
*****
* Initializes the 68681 DUART port A as 9600 8N1 
initDuart:
    move.b  #$30, CRA       * Reset Transmitter
    move.b  #$20, CRA       * Reset Reciever
    move.b  #$10, CRA       * Reset Mode Register Pointer
    
    move.b  #$F0, ACR       * Baud Rate Set #2, Timer (Crystal/16)
    move.b  #$BB, CSRA      * Set Tx and Rx rates to 9600
    move.b  #$93, MRA       * 8-bit, No Parity ($93 for 8-bit, $92 for 7-bit), RxRDY irq type
    move.b  #$07, MRA       * Normal Mode, Not CTS/RTS, 1 stop bit
    
    * Set up the timer for 300Hz
    * Crystal 3.6864MHz / 16 prescaler = 230400. 230400 / 300 = 768 ($300) (384? $180)
    move.b  #$01, CTUR          * Set Timer range value
    move.b  #$80, CTLR          * 
    move.b  #0, varSysCntr5     * Ready the timer divider variables
    move.b  #0, varSysCntr6     * 
    move.l  #0, varHndlr50hz    * No 50hz handler for now
    move.l  #0, varHndlr60hz    * No 60hz handler for now
    
    move.b  #$04, OPCR          * Place counter/timer output on OP3
    
    move.b  #$0a, IMR           * Enable Interrupts: RxRDYA interrupt (bit 1), Timer interrupt (bit 3)
    move.b  #$05, CRA           * Enable Transmit/Recieve
    rts    





********** Interrupts and Exception Handlers ************





********************************************
* Unhandled vector
UNHANDLED:
    rte
 
********************************************
* RESETVECT
RESETVECT:
    reset
    rte
********************************************
* AUTOVECT1 - Currently 68681 DUART, only interrupting device
AUTOVECT1:
    movem.l d0-d1/a0-a1, -(SP)        * Save registers touched by handler
    
    * Check which interrupt the DUART is asserting
    btst.b   #1, ISR            * RxRDYA
    beq.s   .test2              * If no data is waiting
    
    bsr.s   serialReadIntCharacter
 .test2:
    btst.b   #3, ISR            * Counter/Timer Ready
    beq.s   .done               * If the timer hasn't fired yet
    
    bsr.s   timerInt    
    
 .done:
    movem.l (SP)+, d0-d1/a0-a1     * Restore registers
    rte                         * Return from exception
    
********************************************
* Read the character from the DUART (assume it's there from interrupt)
serialReadIntCharacter:
    * We've got data available
    lea     varSRingStart, a0   * Ring buffer ends   
    lea     varSRingEnd,   a1
    
    eor.l   d0, d0              * Clear the full d0 register
    add.b   #1, (a1)            * Increment the end of the buffer
    cmp.b   #SERIAL_RING_LENGTH, (a1)
    blt.s   .noendwrap          * Check if we hit the end and need to wrap
    sub.b   #SERIAL_RING_LENGTH, (a1)
 .noendwrap:
    move.b  (a1), d0
    move.b  (a0), d1
    cmp.b   d0, d1            * Check if the ring buffer is full
    bne.s   .notfull            
    * When buffer is full we'll overwrite the oldest data
    add.b   #1, (a0)            * Make room by removing the oldest element
    cmp.b   #SERIAL_RING_LENGTH, (a0)
    blt.s   .notfull
    sub.b   #SERIAL_RING_LENGTH, (a0)
 .notfull:
    lea     varSerialRing, a0   * Ring buffer
    add.l   d0, a0              * Offset of the last byte in ring buffer
                                * d0 still contains the end offset
    * Read one byte from the DUART into the ring buffer
    move.b  RBA, d0             * Read Character into D0
    move.b  d0, (a0)
    rts
    
********************************************
* Timer fired by DUART, for our purposes 300Hz System timer (divides nicely to 50hz (ym2149 timer) 60hz (vsync)
* If system clock is 4MHz, a 300Hz interrupt gives us ~13,333 cycles between calls so don't take too long here or in timer300hz
timerInt:  
    move.b STOP_CNTR, d0        * Read from STOP_CNTR port to clear interrupt flag
 .test50:
    add.b  #1, varSysCntr5      * Increment the 50hz timer register
    cmp.b  #6, varSysCntr5
    blt.s  .test60
    move.b #0, varSysCntr5  
    
    move.l varHndlr50hz, a0     * Indirectly run our 50hz handler
    cmp.l  #0, a0               * Check if there's a handler specified
    beq.s  .test60              * If not skip
    jsr    (a0)                 * 50hz handler
 .test60:
    add.b  #1, varSysCntr6      * Increment the 60hz timer register
    cmp.b  #5, varSysCntr6  
    blt.s  .standard
    move.b #0, varSysCntr6
    
    move.l varHndlr60hz, a0     * Indirectly run our 60hz handler
    cmp.l  #0, a0               * Check if there's a handler specified
    beq.s  .standard            * If not skip 
    jsr    (a0)                 * 60hz handler
 .standard:
    * Things to do at 300hz here
    
    rts











************************* ROM ROUTINES ********************************

*****************************
* Tests the ym2149 and 50hz interrupt
ym2149:
    move.b #$00, $180000    * Select reg 0 chan a fine
    move.b #$00, $180002    * 
    move.b #$01, $180000    * chan a rough
    move.b #$01, $180002
    
    move.b #$07, $180000    * Mixer reg
    move.b #$FE, $180002
    
    move.b #$08, $180000    * Level chan a reg
    move.b #$0F, $180002
    
    move.b #$0d, $180000    * Envelope shape
    move.b #$00, $180002    * None
    
    move.l #ym2149_50hz, varHndlr50hz
    
    rts
    
ym2149_50hz:
    move.b #$00, $180000
    move.b $180000, d0      * Read current value
    sub.b  #10, d0
    move.b d0, $180002      * Write back decremented value
    rts
    
ym2149_stop:    
    move.b #$07, $180000    * Mixer reg
    move.b #$FF, $180002
    
    move.b #$08, $180000    * Level chan a reg
    move.b #$00, $180002
    
    move.b #$0d, $180000    * Envelope shape
    move.b #$00, $180002    * None

    move.l #0, (varHndlr50hz)
    rts
    
*******************************************
* MYM Playback Routines

  
*varMYMBuf      equ   varHndlrSIGINT-2048             * 2k buffer for decompressed mym data
*varMYMIndex    equ   varMYMBuf-4                     * Index into the file/memory
*varMYMEndPos   equ   varMYMIndex-4                   * End Position, when Index=This we're done
*varMYMFramePos equ   varMYMEndPos-1                  * Current column into frame (0-127)
*varMYMCurByte  equ   varMYMFramePos-1                * Current byte value being examined in data
*varMYMBitPos   equ   varMYMCurByte-1                 * Current bit in the above byte being examined
*varMYMSpare    equ   varMYMBitPos-1                  * Unused (alignment)
*varMYMCurRegs  equ   varMYMSpare-16                  * Previous value for the registers

* Sizes of the various registers in bits
MYMRegSizes:
    dc.b    8, 4, 8, 4, 8, 4, 5, 8, 5, 5, 5, 8, 8, 8
 
PlayWarhawk:
    move.l  #$2000, a0
    bsr.w   MYMInit
    rts
 
PlayThrust:
    move.l  #$8000, a0
    bsr.w   MYMInit
    rts
    
    * The code below dumps the current address into the song
    * then the current position in the frame, while the song is running
MYMDebug:
    move.l  varMYMIndex, d0
    bsr.w   printHexLong
    move.b  #' ', d0
    bsr.w   outChar
    move.b  varMYMFramePos, d0
    bsr.w   printHexByte
    move.b  #' ', d0
    bsr.w   outChar

    bsr.w   printNewline
    
    bra.s  MYMDebug
    rts

*******************************************
* Initializes an MYM Playback
*   'File' address in a0
MYMInit:
    eor.l   d0, d0
    eor.w   d1, d1
    move.b  (a0)+, d0                   * Read in the number of rows
    move.b  (a0)+, d1                   * 16-bit little-endian (Why the hell is this little endian >_<)
    lsl.w   #8, d1
    or.w    d1, d0                  
    
    move.l  a0, varMYMIndex             * Our starting index
    move.l  a0, varMYMEndPos        
    add.l   d0, varMYMEndPos            * Our actual End position
    move.b  #0, varMYMFramePos          * Current frame of fragment
    move.b  #0, varMYMCurByte
    move.b  #7, varMYMBitPos            * Set to 7 so that the first time it's called it will read a new byte
    
    bsr.w  MYMFragment2

    move.l #MYMFrame, varHndlr50hz      * Set our handler to run at 50Hz
    rts
    
*******************************************
* Plays an MYM Frame
MYMFrame:
    cmp.b  #128, varMYMFramePos
    blo.s  .playframe
    move.b #0, varMYMFramePos
    
*    move.l #0, varHndlr50hz
    bsr.s  MYMFragment2
    
*    bra.s .playframe
*    move.l #MYMFrame, varHndlr50hz 
    move.l varMYMEndPos, d1
    sub.l  varMYMIndex, d1
    bhi.s  .playframe                   * If we haven't hit the end yet
 .endSong:
    * End of song
    * Play the last frame loaded
    bsr.s .playframe
    
    move.l #0, varHndlr50Hz             * Remove us from the interrupt handler
    * Silence the YM2149
    move.b #$07, $180000                * Mixer Settings                
    move.b $180000, d0              
    or.b   #$3F, d0                     * Disable all channels
    move.b d0, $180002                  
    move.b #$0D, $180000                * Envelope register
    move.b #$00, $180002                * No envelope
    
    rts
 .playframe:
 
    lea    varMYMBuf, a0                * Fragment buffer
    eor.l  d1, d1
    move.b varMYMFramePos, d1           * Read which frame we're on
    lsl.w  #4, d1                       * There's 16 bytes/registers per frame (Really only 14, but I'm being lazy)
    eor.b  d0, d0
    
    * Now dump the registers
 .dumploop:
    move.b d0, $180000                  * Write the register address to the addr port (Note: reading from this address reads the value of the register)
    move.b (a0, d1), $180002            * Write value to YM register (TODO: Stop code from overwriting high 2 bits of register 7 (port direction control))
    add.w  #1, d1
    add.b  #1, d0
    cmp.b  #14, d0
    blt.s  .dumploop
    
    add.b #1, varMYMFramePos
 .done:
    rts

*******************************************
* Decompress next Fragment into buffer
* Attempt #2, trying to closer match the C code    
MYMFragment2:
    movem.l d2-d5/a2-a4, -(SP)
    
    eor.l  d2, d2                       * Register index
    lea    varMYMCurRegs, a4            * current[]
    lea    MYMRegSizes,  a3             * regbits[]
    
    * for(i=0; i<14(REGS); i++)
    bra.s .regloop_body
 .regloop_head:  
    add.b  #1, d2
    cmp.b  #14, d2                      * For(i=0; i<14; i++)
    bge.w  .done
 .regloop_body:
    lea    varMYMBuf, a2                * data
    add.l  d2, a2                       * "data[i]"
    eor.l  d3, d3                       * index - frame index into fragment (*16)
    move.b #1, d0
    bsr.w  MYMgetBits
    tst.b  d0                           * Check if the fragment unchanged bit is set
    beq.w  .unchg_frag                 
    
    * while(index<128*16) -- Packed fragment
 .fragmentloop_head:
    cmp.w  #2048, d3
    bge.s  .regloop_head
 .fragmentloop_body:
    * if(!readbits(1,f)) -- Unchanged register
    move.b #1, d0
    bsr.w  MYMgetBits
    tst.b  d0                           * Check if the register unchanged bit is set
    beq.w  .unchg_reg                 

    move.b #1, d0
    bsr.w  MYMgetBits
    tst.b  d0                           * Check if the rawdata bit is set    
    bne.w  .raw_reg
    
    * Previous data reference
 .prev_data:
    move.b #7, d0
    bsr.w  MYMgetBits
    eor.l  d4, d4                       * compoff
    move.b d0, d4
    lsl.w  #4, d4
    add.w  d3, d4                       * compoff=readbits(7) + index
    sub.l  #2048, d4                    * compoff-FRAG*16 (precompute to make things easier
    
    move.b #7, d0
    bsr.s  MYMgetBits
    
    eor.l  d5, d5
    move.b d0, d5                       * compnum=readbits(7) + 1
    add.b  #1, d5
    lsl.w  #4, d5                       * *16    
    
    eor.l  d1, d1                       * row=0
    bra.s  .prev_dataloop_body
 .prev_dataloop_head:
    add.w  #16, d1
    cmp.w  d1, d5
    ble.w  .fragmentloop_head           * for(row=0; row<compnum*16; row+= 16)
 .prev_dataloop_body:
    * Compute the offset compoff+row-FRAG
    move.w d4, d0
    add.w  d1, d0
    bge.s  .prev_datanowrap
    add.w  #2048, d0                    * We need to allow wrapping back to data from the previous fragment
 .prev_datanowrap:
    move.b (a2, d0), d0                 * data[i][compoff-FRAG+row]
    move.b d0, (a4, d2)                 * Save into current[i]
    move.b d0, (a2, d3)                 * data[i][index] = current[i] = data[i][compoff-FRAG+row]
    add.w  #16, d3                      * index++ (*16)
    
    bra.s  .prev_dataloop_head
 
 
 .raw_reg:
    move.b (a3, d2), d0                 * regbits[i]
    bsr.s  MYMgetBits
    move.b d0, (a4, d2)                 * Save data into current[i]
    move.b d0, (a2, d3)                 * data[i][index] = current[i] = c
    add.w  #16, d3                      * index++ (*16)
    bra.w  .fragmentloop_head
 

 .unchg_reg:
    move.b (a4, d2), d0                 * current[i]
    move.b d0, (a2, d3)                 * data[i][index] = current[i]
    add.w  #16, d3                      * index++  (*16)
    bra.w  .fragmentloop_head
    
    
 .unchg_frag:
    eor.l  d1, d1                       * row = 0
    bra.s .unchg_frag_body
 .unchg_frag_head:
    add.w  #16, d1
    cmp.w  #2048, d1                    * for(row=0;row<128*16;row+=16)
    bge.w  .regloop_head                * continue for regloop;
 .unchg_frag_body:
    move.b (a4, d2), d0                 * current[i]
    move.b d0, (a2, d1)                 * data[i][row] = current[i]

    bra.s  .unchg_frag_head

    
 .done:
    movem.l (SP)+, d2-d5/a2-a4
    rts
    
*******************************************
* Reads next d0 bits, (This really needs optimization)
MYMgetBits:
    move.l d2, -(SP)
    
    eor.l  d1, d1                       * Data to be returned
    bra.s  .loophead
 .loop:
    add.b  #1, varMYMBitPos             * Move to the next bit position
    cmp.b  #8, varMYMBitPos             * If we're done we read in the next byte
    bne.s  .noread
    move.b #0, varMYMBitPos
    
    
    move.l  varMYMIndex, a0
    move.b (a0), varMYMCurByte          * Read in the next byte
    add.l  #1, varMYMIndex              * Go to the next byte, don't worry about EOF here
 .noread:
    lsl.b  #1, d1                       * Make space for this new bit
    btst.b #7, varMYMCurByte            * Check the highbit
    beq.s  .zero
    or.b   #1, d1                       * Put the bit in
 .zero:
    move.b varMYMCurByte, d2
    rol.b  #1, d2                       * Rotate to the next bit to read    
    move.b d2, varMYMCurByte
    sub.b  #1, d0                       * Done reading one bit
 .loophead:
    tst.b  d0                           
    bne.s  .loop                        * Keep reading
    
    move.l d1, d0                       * Return our bits
    
    move.l (SP)+, d2
    rts    
    
    
    
*******************************************
* Decompress next Fragment into buffer, currently broken use MYMFragment2
MYMLoadFragment:
    movem.l d2-d4/a2-a6, -(SP)

    eor.l   d2, d2                      * Fragment index 
    eor.l   d3, d3                      * Register Index
    lea     varMYMBuf, a2             * Current Pos in buffer
    lea     MYMRegSizes, a3             * Quick index table for register sizes
    lea     varMYMCurRegs, a4           * Previous values for registers
    movea.l a2, a6
 .regloop:
    move.l  #1, d0                      
    bsr.w   MYMgetBits                  * Read in the fragment unchanged bit
    tst.b   d0                          * Check what the bit was
    bne.s   .fragloop                   *
    * Nothing changed in this register since last the entire fragment, copy it in
    move.l  #128, d0                    * Fill all 128 frames with this reg value
    move.b  (a4, d3), d1                * Read the last register value
 .dupfrag_loop:
    move.b  d1, (a2)
    add.l   #16, a2
    sub.b   #1, d0
    bne.s   .dupfrag_loop
    bra.w   .regloop_head
    
 .fragloop:
    move.l  #1, d0                      
    bsr.w   MYMgetBits                  * Read in the frame unchanged bit    
    tst.b   d0
    beq.s   .duplast                    * Frame is the same as the previous frame
    
    move.l  #1, d0                      
    bsr.w   MYMgetBits                  * Read in the repeat segment bit
    tst.b   d0
    beq.s   .repseg
    * Otherwise this is raw data for the register
    eor.l   d0, d0 * TEST: to be safe?
    move.b  (a3, d3), d0                * Read in how many bits this register is
    bsr.w   MYMgetBits
    move.b  d0, (a2)                    * Store the register in our buffer
    move.b  d0, (a4, d3)                * Save the value for the register
    add.l   #16, a2                     * Move to the next frame
    add.w   #1, d2                      * Next frame
    bra.s   .fragloop_head
    
    * Repeat a sequence from earlier in the fragment
    * problem is likely here
 .repseg:
    move.l  #7, d0
    bsr.w   MYMgetBits                  * Read in offset 
    
    * a2 - (128-offset)*16
    
    move.l  #128, d4
    sub.b   d0, d4
    lsl.l   #4, d4
    neg.l   d4
    
    move.l  #7, d0
    bsr.w   MYMgetBits                  * Read in the count
    add.b   #1, d0                      * Off by one
    move.l  d0, d1
    
 .repseg_loop:
    movea.l a2, a5
    add.l   d4, a5
    cmp.l   #varMYMBuf, a5
    bge.s   .repseg_nowrap
    add.l   #4096, a5
 .repseg_nowrap:
    move.b  (a5), d0                    * Read the offseted byte
    move.b  d0, (a2)                    * Store it at the current
    move.b  d0, (a4, d3)                * Save the last/current value for the register
    add.l   #16, a2
    
    add.w   #1, d2                      * Next frame
    sub.b   #1, d1                      * Next count
    bne.s   .repseg_loop
    
    bra.s   .fragloop_head
    
    * Duplicate the last frame
 .duplast:
    move.b  (a4, d3), d0                * Restore the value for the register
    move.b  d0, (a2)
    add.l   #16, a2                     * Move to the next spot in the buffer (Probably can do this with addressing modes and the fragment index,
                                        *  like [a2 + 16*d2 - 16] instead of this increment here
    add.w   #1, d2                      * Next frame
 .fragloop_head:
    cmp.w   #128, d2                    * There's 128 frames in a fragment
    
    blo.w   .fragloop
    
    
 .regloop_head:
    add.b   #1, d3
    lea     varMYMBuf, a2               * Move back to the start
    add.l   d3, a2                      * First byte for this register
    eor.l   d2, d2                      * Reset Fragment index

    cmp.b   #14, d3                     * Go through for each of the 14 registers
    
    blt.w   .regloop



    movem.l (SP)+, d2-d4/a2-a6
    rts

    
    


**********************************
* Strings
*
msgBanner:
    dc.b CR,'Chartreuse''s 68000 ROM Monitor',CR
    dc.b    '===============================',CR,0
msgHelp:
    dc.b 'Available Commands: ',CR
    dc.b ' (E)xamine    (D)eposit',CR
    dc.b ' (R)un        (H)elp',CR,0
msgDepositPrompt:
    dc.b ': ',0
msgPrompt:
    dc.b '> ',0
msgInvalidCommand:
    dc.b 'Invalid Command',CR,0
msgInvalidAddress:
    dc.b 'Invalid Address',CR,0
msgInvalidValue:
    dc.b 'Invalid Value',CR,0
msgRamCheck:
    dc.b 'Checking RAM...',CR,0
msgRamFail:
    dc.b 'Failed at: ',0
msgRamPass:
    dc.b 'Passed.',CR,0
msgNewline:
    dc.b CR,0
msgColonSpace:
    dc.b ': ',0





****** Our mym songs stored in ROM*****
    ORG    $2000
    INCBIN "Warhawk.mym"

    ORG    $8000
    INCBIN "Thrust.mym"


    END    START            * last line of source

*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~

*-----------------------------------------------------------
* Title      : 68k Homebrew ROM Monitor
* Written by : Hayden Kroepfl (ChartreuseK)
* Date       : August 24th 2015
* Description: A simple ROM monitor for my homebrew 68k
*              breadboard computer.
*-----------------------------------------------------------

**********************************
* Defines
*
RAM_START           equ     $40000
RAM_END             equ     $44000
MAX_LINE_LENGTH     equ     80

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
MRB   equ DUART+16      * Mode Register B           (R/W)
SRB   equ DUART+18      * Status Register B         (R)
CSRB  equ DUART+18      * Clock Select Register B   (W)
CRB   equ DUART+20      * Commands Register B       (W)
RBB   equ DUART+22      * Reciever Buffer B         (R)
TBB   equ DUART+22      * Transmitter Buffer B      (W)
IVR   equ DUART+24      * Interrupt Vector Register (R/W)

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
varCurAddr  equ     RAM_END-4                        * Last address accessed
varLineBuf  equ     varCurAddr-MAX_LINE_LENGTH-2     * Line buffer

varLast     equ     varLineBuf


**********************************
* Defines 2 
*
STACK_START         equ     varLast



**** PROGRAM STARTS HERE ****
    
    ORG     $0000
    
**** FIRST 8 bytes loaded after reset ****
    DC.l    STACK_START  * Supervisor stack pointer
    DC.l    START        * Initial PC    
    
    
********************************************
* Cold start entry point
*
START:
    lea     STACK_START, SP     * Set our stack pointer to be sure
    jsr     initDuart           * Setup the serial port
 
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

**************************************************
* Warm Restart entry point
*
monitorStart:
    lea     msgBanner, A0   * Show our banner
    bsr.w   printString
    lea     msgHelp,   A0   * And the command help message
    bsr.w   printString

monitorLine:                * Our main monitor loop
    lea     msgPrompt, a0   * Prompt
    bsr.w   printString     
    bsr.w   readLine        * Read in the line
    bsr.w   lineToUpper     * Convert to upper-case for ease of parsing
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
*   e ADDR;                 Interactive mode, space shows 16 lines, enter shows 1.
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
 .exquick:                      * Quick mode means show one line of 16 bytes
    move.l  #$10, d0
    bra.s   .exend
 .exlength:                     * Length mode means a length is specified
    bsr.w   parseNumber         * Find the length
    tst.b   d1
    bne.w   .invalidAddr
 .exend:                        * We're done parsing, give the parameters to dumpRAM and exit
    move.l  a3, a0
    bsr.w   dumpRAM
    bra.s   .exit
 .exinter:                      * Interactive mode, Space shows 16 lines, enter shows 1.
    move.l  a3, a0              * Current Address
    move.l  #$10, d0            * 16 bytes
    bsr.w   dumpRAM             * Dump this line
    add.l   #$10, a3            * Move up the current address 16 bytes
 .exinterend:
    bsr.w   inChar
    cmp.b   #CR, d0             * Display another line
    beq.s   .exinter
    cmp.b   #' ', d0            * Display a page (256 bytes at a time)
    beq.s   .exinterpage
    bra.s   .exit               * Otherwise exit
 .exinterpage:
    move.l  a3, a0
    move.l  #$100, d0           * 256 bytes
    bsr.w   dumpRAM             * Dump 16 lines of RAM
    add.l   #$100, a3           * Move up the current address by 256
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
    
    bsr.s   parseNumber         * Otherwise read a value
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
    lea     msgDepositPrompt, a0
    bsr.w   printString
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
    jsr     monitorStart        * Warm start after returning so everything is in
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
    move.l  a2, d0          
    bsr.w   printHexAddr     * Starting address of this line
    lea     msgColonSpace, a0
    bsr.w   printString
    move.l  #16, d3          * 16 Bytes can be printed on a line
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
    move.b  #LF, d0
    bsr.w   outChar          * Line feed to be safe
    move.b  #0, (a2)         * Terminate the line (Buffer is longer than max to allow this at full length)
    movea.l a2, a0           * Ready the pointer to return (if needed)
    movem.l (SP)+, d2/a2     * Restore registers
    rts                      * And return




    
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
    btst    #0,  SRA     * Check if receiver ready bit is set
    beq     inChar
    move.b  RBA, d0      * Read Character into D0
    rts
    
*****
* Initializes the 68681 DUART port A as 9600 7N1 
initDuart:
    move.b  #$30, CRA       * Reset Transmitter
    move.b  #$20, CRA       * Reset Reciever
    move.b  #$10, CRA       * Reset Mode Register Pointer
    
    move.b  #$80, ACR       * Baud Rate Set #2
    move.b  #$BB, CSRA      * Set Tx and Rx rates to 9600
    move.b  #$92, MRA       * 7-bit, No Parity ($93 for 8-bit)
    move.b  #$07, MRA       * Normal Mode, Not CTS/RTS, 1 stop bit
    
    move.b  #$05, CRA       * Enable Transmit/Recieve
    rts    






**********************************
* Strings
*
msgBanner:
    dc.b CR,LF,'Chartreuse''s 68000 ROM Monitor',CR,LF
    dc.b       '==============================',CR,LF,0
msgHelp:
    dc.b 'Available Commands: ',CR,LF
    dc.b ' (E)xamine    (D)eposit    (R)un     (H)elp',CR,LF,0
msgDepositPrompt:
    dc.b ': ',0
msgPrompt:
    dc.b '> ',0
msgInvalidCommand:
    dc.b 'Invalid Command',CR,LF,0
msgInvalidAddress:
    dc.b 'Invalid Address',CR,LF,0
msgInvalidValue:
    dc.b 'Invalid Value',CR,LF,0
msgRamCheck:
    dc.b 'Checking RAM...',CR,LF,0
msgRamFail:
    dc.b 'Failed at: ',0
msgRamPass:
    dc.b 'Passed.',CR,LF,0
msgNewline:
    dc.b CR,LF,0
msgColonSpace:
    dc.b ': ',0







    END    START            * last line of source

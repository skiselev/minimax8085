;
; MON85: A software debugger for the 8080/8085 processor
;
; Copyright 1979-2007 Dave Dunfield
; All rights reserved.
;
; Version 1.2 - 2012 Roman Borik
;
; New in version 1.2
; - Support for undocumented 8085 instructions.
;   DSUB B, ARHL, RDEL, LDHI d8, LDSI d8, LHLX D, SHLX D, JNK a16, JK a16, RSTV
; - Command R displays all flags of F register (SZKA3PVC). If flag is not set
;   dash '-' is displayed.
; - Added restart vector RST 8 (0040h) for possibility to handle RSTV call.
; - Changed TRACE mode. After entering TRACE mode, instruction on actual PC and
;   content of registers (if it is switched on) are displayed.
;   Entering a space ' ' executes this instruction, and returns to the 'T>'
;   prompt with the next instruction.
; - Instructions LXI, DAD, INX, DCX displays argument 'SP' rather than 'S'.
; - Commands that requires 1 byte parameter raises error if entered value
;   not fit to 1 byte.
; - Command 'C' checks overlap of source and destination block and for copying
;   uses appropriate direction.
; - Command 'F' checks <start> and <end> parameters and raises error,
;   if <end> is lower than <start>.
; - Added command 'H' to send out memory content in Intel HEX format.
; - Sending of LF and CR characters were reversed and are sent in the usual
;   order - CR first and followed by LF.


ROM	EQU	0000h		; Debugger goes here
DRAM	EQU	0FFA0h		; Debugger RAM (96 bytes required)

;
; Debugger data area (in RAM)
;
	ORG	DRAM		; Monitor data goes here
;
UBASE:	DS	2		; Base address of user program
HL:	DS	2		; Saved HL register pair
DE:	DS	2		; Saved DE register pair
BC:	DS	2		; Saved BC register pair
PSW:	DS	2		; Saved PSW (A + CC)
SP:	DS	2		; Saved Stack Pointer
PC:	DS	2		; Saved Program Counter
OFLAG:	DS	1		; Output suspended flag
TFLAG:	DS	1		; Flag to enable TRACING
SFLAG:	DS	1		; Flag to enable SUBROUTINE tracing
AFLAG:	DS	1		; Flag to enable AUTO REGISTER DISPLAY
BRKTAB:	DS	24		; Breakpoint table
INST:	DS	6		; Save area for "faking" instructions
BUFFER:	DS	48		; Input/temp buffer & stack
DSTACK	EQU	$&0FFFFh	; Debugger stack
;
; Startup code... Kick off the monitor
;
	ORG	ROM		; Debugger code goes here
;
	LXI	SP,DSTACK	; Set up initial stack pointer
	JMP	TEST		; Execute main program
	DS	2		; Filler bytes to first int
;
; Interrupt handlers for RESTART interrupts
;
; Although they RST 1.5, 2.5 and 3.5 vectors are not used by the
; 8085 hardware,  they are included since the space must contain
; SOMETHING,  and who knows,  perhaps someone uses them for jump
; table addresses etc...
;
; Restart 1 is the entry point for breakpoints
RST1:	JMP	ENTRY		; Execute handler
	DS	1		; Filler to next int
RST15:	CALL	RSTINT		; Invoke interrupt
	DB	12		; Offset to handler
RST2:	CALL	RSTINT		; Invoke interrupt
	DB	16		; Offset to handler
RST25:	CALL	RSTINT		; Invoke interrupt
	DB	20		; Offset to handler
RST3:	CALL	RSTINT		; Invoke interrupt
	DB	24		; Offset to handler
RST35:	CALL	RSTINT		; Invoke interrupt
	DB	28		; Offset to handler
RST4:	CALL	RSTINT		; Invoke interrupt
	DB	32		; Offset to handler
TRAP:	CALL	RSTINT		; Invoke interrupt
	DB	36		; Offset to handler
RST5:	CALL	RSTINT		; Invoke interrupt
	DB	40		; Offset to handler
RST55:	CALL	RSTINT		; Invoke interrupt
	DB	44		; Offset to handler
RST6:	CALL	RSTINT		; Invoke interrupt
	DB	48		; Offset to handler
RST65:	CALL	RSTINT		; Invoke interrupt
	DB	52		; Offset to handler
RST7:	CALL	RSTINT		; Invoke interrupt
	DB	56		; Offset to handler
RST75:	CALL	RSTINT		; Invoke interrupt
	DB	60		; Offset to handler
RST8:	CALL	RSTINT		; Invoke interrupt
	DB	64		; Offset to handler
;
; Process a RESTART interrupt, get offset & vector to code
; To speed processing, it is assumed that the user program
; base address begins on a 256 byte page boundary.
;
RSTINT:	XTHL			; Save HL, Get PTR to offset
	PUSH	PSW		; Save A and CC
	MOV	A,M		; Get offset
	LHLD	UBASE		; Get high of user program
	MOV	L,A		; Set low address
	POP	PSW		; Restore A & CC
	XTHL			; Restore HL, set 
	RET			; Vector to interrupt
;
; Register -> text translation tables used by the disassembler. These tables
; go here (near beginning) so that we can be sure the high address will not
; cross a page boundary allowing us to index by modifying low address only.
;
RTAB:	DB	"BCDEHLMA"	; Table of register names
RPTAB:	DB	"BDHS"		; Table of register pairs
;
; Entry point for breakpoints & program tracing
;
; Save the user program registers
ENTRY:	SHLD	HL		; Save HL
	XCHG			; Get DE
	SHLD	DE		; Save DE
	POP	H		; Get RET addrss
	SHLD	PC		; Save PC
	PUSH	B		; Copy BC
	POP	H		; And get it
	SHLD	BC		; Save PC
	PUSH	PSW		; Copy PSW
	POP	H		; And get it
	SHLD	PSW		; Save PSW
	LXI	H,0		; Start with zero
	DAD	SP		; Get SP
	SHLD	SP		; Save SP
	LXI	SP,DSTACK	; Move to our stack
	LHLD	PC		; Get RET addrss
	DCX	H		; Backup to actual instruction
	SHLD	PC		; Save PC
	LXI	D,BRKTAB	; Point to breakpoint table
	MVI	B,'0'		; Assume breakpoint #0
; Search breakpoint table & see if this is a breakpoint
TRYBRK:	LDAX	D		; Get HIGH byte from table
	INX	D		; Advance
	CMP	H		; Does it match?
	LDAX	D		; Get LOW byte from table
	INX	D		; Advance
	JNZ	NOTBRK		; No, try next
	CMP	L		; Does it match?
	JZ	FOUND		; Yes, we have an entry
NOTBRK:	INX	D		; Skip saved code byte
	INR	B		; Advance breakpoint number
	MOV	A,B		; Get breakpoint number
	CPI	'0'+8		; Table exausted
	JC	TRYBRK		; No, keep looking
; This interrupt is NOT a breakpoint
	JMP	NOBK		; Enter with no breakpoint
; This interrupt is a breakpoint, display the message
FOUND:	CALL	PRTMSG		; Output message
	DB	"** Breakpoint ",0
	MOV	A,B		; Get breakpoint number
	CALL	OUT		; Output it
	CALL	CRLF		; New line
; Reenter monitor, first, restore all breakpoint opcodes
NOBK:	LXI	H,BRKTAB	; Point to breakpoint table
	MVI	B,8		; 8 breakpoints
FIXL:	MOV	D,M		; Get HIGH address
	INX	H		; Advance
	MOV	E,M		; Get LOW address
	INX	H		; Advance
	MOV	A,D		; Get high
	ORA	E		; Test for ZERO
	JZ	NOFIX		; Breakpoint is not set
	MOV	A,M		; Get opcode
	STAX	D		; And patch user code
NOFIX:	INX	H		; Skip opcode
	DCR	B		; Reduce count
	JNZ	FIXL		; Not finished, keep going
	LDA	TFLAG		; Get trace mode flag
	ANA	A		; Is it enabled?
	JNZ	TRTB		; Yes, enter trace mode
	LDA	AFLAG		; Get auto register display flag
	ANA	A		; Is it enabled?
	CNZ	REGDIS		; Yes, display the registers
	JMP	REST		; Enter monitor
; Prompt for and handle trace mode commands
TRTB:	CALL	PRTMSG		; Output message
	DB	"T> ",0		; Trace mode prompt
	LHLD	PC		; Get PC
	XCHG			; Move to DE
	CALL	DINST		; Disassemble the instruction
	CALL	CRLF		; New line
	LDA	AFLAG		; Get auto register display flag
	ANA	A		; Is it enabled?
	CNZ	REGDIS		; Yes, display the registers
TRL:	CALL	INCHR		; Get a command character
	CPI	' '		; Execute command?
	JZ	NOADR		; Yes, handle it
	CPI	1Bh		; ESCAPE?
	JZ	RECR		; Yes, abort
	CPI	'?'		; Register display?
	JNZ	TRL		; No, ignore it
	CALL	REGDIS		; Display the registers
	JMP	TRTB		; And go again
;
; Main entry point for the 8080 debugger
;
TEST:	CALL	INIT		; Set up hardware
	CALL	PRTMSG		; Output herald message
	DB	0Dh,0Ah
	DB	"MON85 Version 1.2"
	DB	0Dh,0Ah,0Ah
	DB	"Copyright 1979-2007 Dave Dunfield"
	DB	0Dh,0Ah
	DB	"2012 Roman Borik"
	DB	0Dh,0Ah
	DB	"All rights reserved."
	DB	0Ah,0
	LXI	H,UBASE		; Point to start of reserved RAM
	MVI	C,(DSTACK-UBASE)&0FFh ; Number of bytes to zero
INIL1:	MVI	M,0		; Clear a byte
	INX	H		; Advance
	DCR	C		; Reduce count
	JNZ	INIL1		; Clear em all
	LXI	H,0FFFFh	; Set flags
	SHLD	SFLAG		; Turn on SUBTRACE & AUTOREG
	LXI	H,UBASE		; Default user stack (below monitor RAM)
	SHLD	SP		; Set user SP
; Newline and prompt for command
RECR:	CALL	CRLF		; Output a newline
; Prompt for an input command
REST:	LXI	SP,DSTACK	; Reset stack pointer
	CALL	PRTMSG		; Output message
	DB	"C> ",0		; Command prompt
	CALL	INPT		; Get command character
; Look up command in table
	MOV	B,A		; Save for later
	LXI	H,CTABLE	; Point to command table
REST1:	MOV	A,M		; Get char
	INX	H		; Advance
	CMP	B		; Do it match?
	JZ	REST2		; Yes, go for it
	INX	H		; Skip HIGH address
	INX	H		; Skip LOW address
	ANA	A		; end of table?
	JNZ	REST1		; Its OK
; Error has occured, issue message & return for command
ERROR:	MVI	A,'?'		; Error indicator
	CALL	OUT		; Display
	JMP	RECR		; And wait for command
; We have command, execute it
REST2:	INX	D		; Skip command character
	MOV	A,M		; Get low address
	INX	H		; Skip to next
	MOV	H,M		; Get HIGH address
	MOV	L,A		; Set LOW
	CALL	SKIP		; Set 'Z' of no operands
	PCHL			; And execute
; Table of commands to execute
CTABLE:	DB	'A'		; Set AUTOREG flag
	DW	AUTO
	DB	'B'		; Set/Display breakpoint
	DW	SETBRK
	DB	'C'		; Copy memory
	DW	COPY
	DB	'D'		; Disassemble
	DW	GODIS
	DB	'E'		; Edit memory
	DW	EDIT
	DB	'F'		; Fill memory
	DW	FILL
	DB	'G'		; Go (begin execution)
	DW	GO
	DB	'H'		; Send out memory as Intel HEX
	DW	SNDHEX
	DB	'I'		; Input from port
	DW	INPUT
	DB	'L'		; Load from serial port
	DW	LOAD
	DB	'M'		; Memory display
	DW	MEMRY
	DB	'O'		; Output to port
	DW	OUTPUT
	DB	'R'		; Set/Display Registers
	DW	REGIST
	DB	'S'		; Set SUBTRACE flag
	DW	SUBON
	DB	'T'		; Set TRACE mode
	DW	TRACE
	DB	'U'		; Set/Display user base
	DW	USRBASE
	DB	'?'		; Help command
	DW	HELP
	DB	0		; End of table
	DW	REST		; Handle NULL command
;
; Help command
;
HELP:	LXI	H,HTEXT		; Point to help text
	SUB	A		; Get a zero
	STA	OFLAG		; Clear the output flag
; Output each line
HELP1:	MVI	C,25		; Column counter
HELP2:	MOV	A,M		; Get character
	INX	H		; Advance to next
	ANA	A		; End of line?
	JZ	HELP4		; Yes, terminate
	CPI	'!'		; Separator?
	JZ	HELP3		; Yes, output
	CALL	OUT		; Write character
	DCR	C		; Reduce count
	JMP	HELP2		; Keep going
; Fill with spaces to discription column
HELP3:	CALL	SPACE		; Output a space
	DCR	C		; Reduce count
	JNZ	HELP3		; Do them all
	MVI	A,'-'		; Spperator
	CALL	OUT		; Display
	CALL	SPACE		; And space over
	JMP	HELP2		; Output rest of line
; End of line encountered...
HELP4:	CALL	CHKSUS		; New line
	MOV	A,M		; Get next byte
	ANA	A		; End of text?
	JNZ	HELP1		; Do them all
	JMP	RECR		; And go home
;
; Input from port
;
INPUT:	CALL	CALC8		; Get port number
	MVI	A,0DBh		; 'IN' instruction
	MVI	H,0C9h		; 'RET' instruction
	STA	INST		; Set RAM instruction
	SHLD	INST+1		; Set RAM instruction
	CALL	PRTMSG		; Output message
	DB	"DATA=",0
	CALL	INST		; Perform the read
	CALL	HPR		; Output it
	JMP	RECR		; Newline & EXIT
;
; Output to port
;
OUTPUT:	CALL	CALC8		; Get port number
	MVI	A,0D3h		; 'OUT' instruction
	MVI	H,0C9h		; 'RET' instruction
	STA	INST		; Set RAM instruction
	SHLD	INST+1		; Set RAM instruction
	CALL	CALC8		; Get data byte
	CALL	INST		; Output the data
	JMP	REST		; Back to command prompt
;
; Set breakpoint command
;
SETBRK:	JZ	DISBRK		; No operands, display breakpoints
; Set a breakpoint
	CALL	CALC8		; Get hex operand
	CPI	8		; In range?
	JNC	ERROR		; No, invalud
	LXI	H,BRKTAB-3	; Point to breakpoint table
	LXI	B,3		; Offset for a breakpoint
SBRLP:	DAD	B		; Advance to next breakpoint
	DCR	A		; Reduce count
	JP	SBRLP		; Go until we are there
	PUSH	H		; Save table address
	CALL	CALC		; Get address
	POP	D		; Restore address
	XCHG			; D=brkpt address, H=table address
	MOV	M,D		; Set HIGH address in table
	INX	H		; Advance
	MOV	M,E		; Set LOW address in table
	INX	H		; Advance
	LDAX	D		; Get opcode from memory
	MOV	M,A		; Save in table
	JMP	REST		; And get next command
; Display breakpoints
DISBRK:	LXI	D,BRKTAB	; Point to breakpoint table
	MVI	B,'0'		; Begin with breakpoint zero
DISLP:	MVI	A,'B'		; Lead in character
	CALL	OUT		; Output
	MOV	A,B		; Get breakpoint number
	CALL	OUT		; Output
	MVI	A,'='		; Seperator character
	CALL	OUT		; Output
	LDAX	D		; Get HIGH address
	MOV	H,A		; Copy
	INX	D		; Advance
	LDAX	D		; Get LOW address
	MOV	L,A		; Copy
	ORA	H		; Is breakpoint set?
	JZ	NOTSET		; No, don't display
	CALL	HLOUT		; Output in hex
	JMP	GIVLF		; And proceed
; Breakpoint is not set
NOTSET:	CALL	PRTMSG		; Output message
	DB	"****",0	; Indicate not set
GIVLF:	MVI	A,' '		; Get a space
	CALL	OUT		; Output
	CALL	OUT		; Output
	MOV	A,B		; Get breakpoint address
	CPI	'0'+3		; Halfway through?
	CZ	CRLF		; Yes, new line
	INX	D		; Skip low byte
	INX	D		; Skip opcode
	INR	B		; Advance breakpoint number
	MOV	A,B		; Get number again
	CPI	'0'+8		; All done?
	JC	DISLP		; No, keep going
	CALL	CRLF		; New line
	LXI	H,AUTMSG	; Message for AFLAG
	LDA	AFLAG		; Get flag state
	CALL	DISON		; Display ON/OFF indication
	LXI	H,SUBMSG	; Message for SFLAG
	LDA	SFLAG		; Get flag state
	CALL	DISON		; Display ON/OFF indication
	LXI	H,TRCMSG	; Message for TFLAG
	LDA	TFLAG		; Get flag state
	CALL	DISON		; Display ON/OFF indication
	CALL	CRLF		; New line
	JMP	REST		; Back for another command
; Display ON/OFF flag state
DISON:	PUSH	PSW		; Save A
	CALL	PRTSTR		; Output message
	POP	PSW		; Restore A
	LXI	H,OFF		; Assume OFF
	ANA	A		; Test A
	JZ	PRTSTR		; Yes, display OFF
	LXI	H,ON		; Convert to ON
	JMP	PRTSTR		; And display ON
;
; GO command, Begin program execution
;
GO:	JZ	NOHEX		; Address not given, assume default
	CALL	CALC		; Get argument
	SHLD	PC		; Save new PC value
NOHEX:	LDA	TFLAG		; Get trace flag
	ANA	A		; Enabled?
	JNZ	TRTB		; Yes, wait for prompt
; Single-step one instruction...
; Used for first instruction even when NOT tracing, so
; that we can insert breakpoints
NOADR:	SUB	A		; Get NOP
	MOV	H,A		; Set high
	MOV	L,A		; Set LOW
	STA	INST		; Set first byte
	SHLD	INST+1		; Set second & third
	LHLD	PC		; Get PC
	XCHG			; Set DE to PC
	CALL	LOOK		; Lookup instruction
	MOV	B,A		; Save the TYPE/LENGTH byte
	ANI	03h		; Mask TYPE, save LENGTH
	MOV	C,A		; Save for count
; Copy instruction into "faking" area
	LXI	H,INST		; Point to saved instruction
GOSET:	LDAX	D		; Get byte from code
	MOV	M,A		; Save in instruction
	INX	H		; Advance output
	INX	D		; Advance input
	DCR	C		; Reduce count
	JNZ	GOSET		; Copy it all
	XCHG			; HL = addrss to execute
	MVI	A,0C3h		; Get a JMP instruction
	STA	INST+3		; Set up a JUMP instruction
	SHLD	INST+4		; Set target address
	LDA	TFLAG		; Get trace flag
	ANA	A		; Are we tracing?
	JZ	NOTRC		; No, we are not
	PUSH	B		; Save TYPE/LENGTH
	LHLD	INST+4		; Get termination address
	INX	H		; Skip this one
	SHLD	BUFFER		; Save for "fake" handling
	LXI	H,FAKE		; Point to FAKE routine
	SHLD	INST+4		; Save new addres
	POP	B		; Restore TYPE/LENGTH
; Simulate any control transfer instruction
	LDA	INST		; Get instruction
	CPI	0E9h		; Is it PCHL?
	JNZ	NOPCHL		; No, skip
	LHLD	HL		; Get user HL value
	JMP	HLJMP		; And simulate a jump
NOPCHL:	CPI	0CBh		; Is it RSTV?
	JNZ	NORSTV		; No, skip
	LDA	PSW		; Get status flags
	ANI	2		; Check V flag
	JNZ	NOTRC		; Is set, execute instruction
	STA	INST		; Change to NOP
	JMP	NOTRC		; Not set, execute NOP
NORSTV:	CPI	0DDh		; Is it JNK?
	JZ	JNKJK		; Yes, go
	CPI	0FDh		; Is it JK?
	JNZ	NOJNK		; No, skip
JNKJK:	ANI	20h		; Save K flag from instruction code
	MOV	C,A
	LDA	PSW		; Get status flags
	ANI	20h		; Save only K flag
	XRA	C		; Compare them
	JZ	NOPSH		; If they are equal, make jump
	JMP	NOTRC		; No jump 
NOJNK:	MOV	A,B		; Get TYPE back
	CPI	0Bh		; Is it a 'JUMP'
	JZ	GOJMP		; Yes, handle it
	CPI	05h		; Is it a 'RETURN'
	JZ	CALRET		; Yes, handle it
	ANI	0F8h		; Save only conditional bits
	JZ	NOTRC		; Not conditional, always execute instruction
	ANI	08h		; Does this test require COMPLEMENTED flags
	LDA	PSW		; Get status flags
	JZ	NOCOM		; No need to complement
	CMA			; Invert for NOT tests
NOCOM:	MOV	C,A		; Save PSW bits
	MOV	A,B		; Get conditon back
	RAL			; Is it SIGN flag?
	JC	SIGN		; Yes, handle it
	RAL			; Is it ZERO flag?
	JC	ZERO		; Yes, handle it
	RAL			; Is it PARITY flag?
	JC	PARITY		; Yes, handle it
; This instruction is conditional on the CARRY flag
CARRY:	MOV	A,C		; Get flag bits
	ANI	01h		; Test CARRY flag
	JMP	ENFLG		; And proceed
; This instruction is conditional on the SIGN flag
SIGN:	MOV	A,C		; Get flag bits
	ANI	80h		; Test SIGN flag
	JMP	ENFLG		; And proceed
; This instruction is conditional on the ZERO flag
ZERO:	MOV	A,C		; Get flag bits
	ANI	40h		; Test ZERO flag
	JMP	ENFLG		; And proceed
; This instruction is conditional on the PARITY flag
PARITY:	MOV	A,C		; Get flag bits
	ANI	04h		; Test PARITY flag
; Execute conditional instruction
ENFLG:	JZ	NOTRC		; Not executed
	MOV	A,B		; Get type back
	ANI	04h		; Is it JUMP
	JNZ	CALRET		; No, try next
; Simulate a JUMP instruction
GOJMP:	LDA	INST		; Get instruction
	CPI	0CDh		; Is it a CALL
	JZ	PADR		; Yes
	ANI	0C7h		; Mask conditional
	CPI	0C4h		; Conditional call?
	JNZ	NOPSH		; No, its a jump
; Simulate a subroutine trace
PADR:	LDA	SFLAG		; Get subroutine tracing flag
	ANA	A		; Is it set?
	JZ	NOTRC		; No, simulate as one instruction
	LHLD	BUFFER		; Get termination address
	DCX	H		; Backup
	XCHG			; D = address
	LHLD	SP		; Get user SP
	DCX	H		; Backup
	MOV	M,D		; Set HIGH return address
	DCX	H		; Backup
	MOV	M,E		; Set LOW return address
	SHLD	SP		; Resave user SP
; Continue simulation of a JUMP type instruction
NOPSH:	LHLD	INST+1		; Get target address
	JMP	HLJMP		; And proceed
; Handle simulation of RETURN instruction
CALRET:	LHLD	SP		; Get sser SP
	MOV	E,M		; Get LOW return address
	INX	H		; Advance
	MOV	D,M		; Get HIGH return address
	INX	H		; Advance
	SHLD	SP		; Resave user SP
	XCHG			; Set HL = address
; Simulate a jump to the address in HL
HLJMP:	INX	H		; Advance
	SHLD	BUFFER		; Save new target address
	SUB	A		; Get NOP
	MOV	H,A		; Set HIGH
	MOV	L,A		; Set LOW
	STA	INST		; NOP first byte
	SHLD	INST+1		; NOP second byte
; Dispatch the user program
; First, insert any breakpoints into the object code
NOTRC:	LXI	D,BRKTAB	; Point to breakpoint table
	MVI	C,8		; Size of table (in entries)
RESBP:	LDAX	D		; Get a HIGH address
	MOV	H,A		; Save for later
	INX	D		; Advance
	LDAX	D		; Get low address
	MOV	L,A		; Save for later
	INX	D		; Advance
	ORA	H		; Is breakpoint enabled?
	JZ	NORES		; No, its not
	MVI	M,0CFh		; Set up a RST 1 breakpoint
NORES:	INX	D		; Skip opcode
	DCR	C		; Reduce count
	JNZ	RESBP		; Do them all
; Restore the user applications registers
	LHLD	SP		; Get stack pointer
	SPHL			; Set stack pointer
	LHLD	BC		; Get BC
	PUSH	H		; Save
	POP	B		; And set
	LHLD	PSW		; Get PSW
	PUSH	H		; Save
	POP	PSW		; And set
	LHLD	DE		; Get DE
	XCHG			; Set DE
	LHLD	HL		; Get HL
	JMP	INST		; Execute "faked" instruction
; Trace routine: simulate a breakpoint interrupt
FAKE:	PUSH	H		; Save HL on stack
	LHLD	BUFFER		; Get address to execute
	XTHL			; Restore HL, [SP] = address
	JMP	ENTRY		; Display the registers
;
; Display/Change registers
;
REGIST:	JNZ	CHG1		; Register name to change is given
; Display registers
	CALL	REGDIS		; Display registers
	JMP	REST		; And exit
; Set register value
CHG1:	MOV	B,A		; Save first register name char
	CALL	GETCHI		; Get char (in upper case)
	MOV	C,A		; Save for later
	JZ	OKCH		; End of string
; Drop extra characters incase 'PSW'
CHG2:	CALL	GETCHR		; Get next
	JNZ	CHG2		; Clean them out
; Get new value for register
OKCH:	CALL	CALC		; Get new value
	MOV	A,B		; Get first char
	CPI	'H'		; Is it HL pair
	JNZ	CDE		; No, try next
	SHLD	HL		; Set HL value
	JMP	REST		; And proceed
CDE:	CPI	'D'		; Is it DE pair?
	JNZ	CBC		; No, try next
	SHLD	DE		; Set DE value
	JMP	REST		; And proceed
CBC:	CPI	'B'		; Is it BC pair?
	JNZ	CSP		; No, try next
	SHLD	BC		; Set BC value
	JMP	REST		; And proceed
CSP:	CPI	'S'		; Is it SP?
	JNZ	CP		; No, try next
	SHLD	SP		; Set SP value
	JMP	REST		; And proceed
CP:	CPI	'P'		; Is it PS or PC
	JNZ	ERROR		; No, error
	MOV	A,C		; Get low character
	CPI	'S'		; Is it PSW?
	JNZ	CPC		; No, try next
	SHLD	PSW		; Set new PSW
	JMP	REST		; And proceed
CPC:	CPI	'C'		; Is it PC?
	JNZ	ERROR		; No, error
	SHLD	PC		; Set new PC
	JMP	REST		; And proceed
; Process an ON/OFF operand
ONOFF:	CALL	SKIP		; Get next char
	CPI	'O'		; Must begin with ON
	JNZ	ERROR		; Invalid
	CALL	GETCHI		; Get next char
	MVI	B,0		; Assume OFF
	CPI	'F'		; OFF?
	JZ	RETON		; Yes, set it
	CPI	'N'		; ON?
	JNZ	ERROR		; No, error
	DCR	B		; Convert to FF
RETON:	MOV	A,B		; Save new value
	RET
;
; Turn automatic register display ON or OFF
;
AUTO:	CALL	ONOFF		; Get ON/OFF value
	STA	AFLAG		; Set AUTOREG flag
	JMP	REST		; And proceed
;
; Turn SUBROUTINE tracing ON or OFF
;
SUBON:	CALL	ONOFF		; Get ON/OFF value
	STA	SFLAG		; Set SUBTRACE flag
	JMP	REST		; And proceed
;
; Set TRACE mode ON or OFF
;
TRACE:	CALL	ONOFF		; Get ON/OFF value
	STA	TFLAG		; Set TRACE flag
	JMP	REST		; And proceed
;
; Edit memory contents
;
EDIT:	CALL	CALC		; Get address
EDIT1:	CALL	HLOUT		; Display address
	CALL	SPACE		; Separator
	MOV	A,M		; Get contents
	CALL	HPR		; Output
	MVI	A,'='		; Prompt
	CALL	OUT		; Output
	PUSH	H		; Save address
	CALL	INPT		; Get a value
	POP	H		; Restore address
	INX	H		; Assume advance
	JZ	EDIT1		; Null, advance
	DCX	H		; Fix mistake
	DCX	H		; Assume backup
	CPI	'-'		; Backup?
	JZ	EDIT1		; Yes, backup a byte
	INX	H		; Fix mistake
	CPI	27h		; Single quote?
	JNZ	EDIT3		; No, try hex value
; Handle quoted ASCII text
	INX	D		; Skip the quote
EDIT2:	LDAX	D		; Get char
	INX	D		; Advance input
	ANA	A		; End of loop?
	JZ	EDIT1		; Yes, exit
	MOV	M,A		; Save it
	INX	H		; Advance output
	JMP	EDIT2		; And proceed
; Handle HEXIDECIMAL values
EDIT3:	PUSH	H		; Save address
	CALL	CALC8		; Get HEX value
	POP	H		; HL = address
	MOV	M,A		; Set value
	INX	H		; Advance to next
	CALL	SKIP		; More operands?
	JNZ	EDIT3		; Get then all
	JMP	EDIT1		; And continue
;
; FIll memory with a value
;
FILL:	CALL	CALC		; Get starting address
	PUSH	H		; Save for later
	CALL	CALC		; Get ending address
	PUSH	H		; Save for later
	CALL	CALC8		; Get value
	MOV	C,A		; C = value
	POP	D
	INX	D		; DE = End address+1
	POP	H		; HL = Starting address
	CALL	COMP16		; Is Start<End ?
	JNC	ERROR		; Yes, bad entry
FILL1:	MOV	M,C		; Save one byte
	INX	H		; Advance
	CALL	COMP16		; Test for match
	JC	FILL1		; And proceed
	JMP	REST		; Back for next
;
; 16 bit compare of HL to DE
;
COMP16:	MOV	A,H		; Get HIGH
	CMP	D		; Match?
	RNZ			; No, we are done
	MOV	A,L		; Get LOW
	CMP	E		; Match?
	RET
;
; Copy a block of memory
;
COPY:	CALL	CALC		; Get SOURCE address
	PUSH	H		; Save for later
	CALL	CALC		; Get DEST Address
	PUSH	H		; Save for later
	CALL	CALC		; Get size
	MOV	B,H		; BC = Size
	MOV	C,L
	POP	D		; DE = Dest address
	POP	H		; HL = Source
	MOV	A,B		; Size is zero?
	ORA	C
	JZ	REST		; Yes, exit
	CALL	COMP16		; Compare source and destination address
	JC	COPY2		; Dest > Source, jump
	; Source > Dest
COPY1:	MOV	A,M		; Get byte from source
	STAX	D		; Write to dest
	INX	H		; Advance source
	INX	D		; Advance dest
	DCX	B		; Reduce count
	MOV	A,C		; Count is zero ?
	ORA	B
	JNZ	COPY1		; No, continue
	JMP	REST
	; Dest > Source
COPY2:	DAD	B		; Move source and destination address to end
	DCX	H		; of block
	XCHG
	DAD	B
	DCX	H
COPY3:	LDAX	D		; Get byte from source
	MOV	M,A		; Write to dest
	DCX	D		; Decrement source address
	DCX	H		; Decrement destination address
	DCX	B		; Reduce count
	MOV	A,C		; Count is zero ?
	ORA	B
	JNZ	COPY3		; No, continue
	JMP	REST
;
; Display a block of memory
;
MEMRY:	CALL	CALC		; Get operand
	SUB	A		; Get a ZERO
	STA	OFLAG		; Clear output flag
ALOOP:	CALL	HLOUT2		; Display address (in hex) with 2 spaces
	MVI	D,16		; 16 bytes/line
	PUSH	H		; Save address
ALP1:	MOV	A,M		; Get byte
	CALL	HPR		; Output in hex
	CALL	SPACE		; Space over
	MOV	A,D		; Get count
	CPI	9		; At boundary?
	CZ	SPACE		; Yes, extra space
	MOV	A,D		; Get count
	ANI	7		; Mask for low bits
	CPI	5		; At boundary?
	CZ	SPACE		; Extra space
	INX	H		; Advance address
	DCR	D		; Reduce count
	JNZ	ALP1		; Do them all
	MVI	D,4		; # separating spaces
AL2:	CALL	SPACE		; Output a space
	DCR	D		; Reduce count
	JNZ	AL2		; And proceed
	POP	H
	MVI	D,16		; 16 chars/display
AL3:	MOV	A,M		; Get data byte
	CALL	OUTP		; Display (if printable)
	INX	H		; Advance to next
	DCR	D		; Reduce count
	JNZ	AL3		; Do them all
	CALL	CHKSUS		; Handle output suspension
	JMP	ALOOP		; And continue
;
; Perform disassembly to console
;
GODIS:	CALL	CALC		; Get starting address
	PUSH	H		; Save address
	POP	D		; Copy to D
	SUB	A		; Get a zero
	STA	OFLAG		; Clear output flag
VLOOP:	CALL	DINST		; Display one instruction
	CALL	CHKSUS		; Handle output
	JMP	VLOOP		; And proceed
;
; Set/display user base address
;
USRBASE: JNZ	USRB1		; Address is given, set it
	CALL	PRTMSG		; Output message
	DB	"BASE=",0
	LHLD	UBASE		; Get address
	CALL	HLOUT		; Output
	JMP	RECR		; New line & exit
USRB1:	CALL	CALC		; Get operand
	SHLD	UBASE		; Set the address
	JMP	REST		; and return
;
; Send out as Intel HEX
;
SNDHEX:	CALL	CALC		; Get start address
	PUSH	H		; Save for later
	CALL	CALC		; Get end address
	INX	H		; HL = end+1
	POP	D		; DE = start
	CALL	COMP16		; Check for Start > End
	JC	ERROR		; Bad entry
	MOV	A,L		; Compute length
	SUB	E
	MOV	L,A
	MOV	A,H
	SBB	D
	MOV	H,A
	XCHG			; HL = start, DE = length
SNDHX1:	MOV	A,D		; Finish ?
	ORA	E
	JZ	SNDHX3		; Yes, jump
	MVI	B,16		; 16 bytes per record
	MOV	A,D		; Is rest > 16 ?
	ORA	A
	JNZ	SNDHX2		; No, jump
	MOV	A,E
	CMP	B
	JNC	SNDHX2		; No, jump
	MOV	B,E		; Yes, B=rest
SNDHX2:	CALL	SHXRC		; Send out one record
	JMP	SNDHX1		; continue
;
SNDHX3:	CALL	PRTMSG
	DB	":00000001FF",0Dh,0Ah,0
	JMP	REST
;
SHXRC:	MVI	A,':'		; Start record
	CALL	OUT
	MOV	A,B		; Length
	MOV	C,A		; Init checksum
	CALL	HPR		; Output in hex
	MOV	A,H		; High byte of address 
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
	MOV	A,H
	CALL	HPR		; Output in hex
	MOV	A,L		; Low byte of address 
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
	MOV	A,L
	CALL	HPR		; Output in hex
	XRA	A		; Record type
	CALL	HPR
SHXRC1:	MOV	A,M		; One byte
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
	MOV	A,M
	INX	H
	CALL	HPR		; Output in hex
	DCX	D		; Decrement main counter
	DCR	B		; Decrement bytes per record counter
	JNZ	SHXRC1
	MOV	A,C		; Negate checksum
	CMA
	INR	A
	CALL	HPR		; Output in hex
	JMP	CRLF
;
; Download command
;
LOAD:	MVI	A,0Fh		; Get default initial state
	JZ	LOAD1		; Address not given...
	CALL	CALC		; Get operand value
	SHLD	BUFFER+3	; Save for later calulation
	MVI	A,0FFh		; Set new initial state
; Setup the offset calculator
LOAD1:	LXI	H,0		; Assume no offset
	STA	BUFFER		; Set mode flag
	SHLD	BUFFER+1	; Assume offset is ZERO
; Download the records
LOAD2:	CALL	DLREC		; Get a record
	JNZ	DLBAD		; Report error
	JNC	LOAD2		; Get them all
	JMP	DLWAIT		; And back to monitor
; Error in receiving download record
DLBAD:	CALL	PRTMSG		; Output message
	DB	"?Load error"
	DB	0Dh,0Ah,0
; Wait till incoming data stream stops
DLWAIT:	MVI	C,0		; Initial count
DLWAIT1: CALL	IN		; Test for input
	ANA	A		; Any data
	JNZ	DLWAIT		; Reset count
	DCR	C		; Reduce counter
	JNZ	DLWAIT1		; Keep looking
	JMP	REST		; Back to monitor
;
; Download a record from the serial port
;
DLREC:	CALL	INCHR		; Read a character
	CPI	':'		; Start of record?
	JZ	DLINT		; Download INTEL format
	CPI	'S'		; Is it MOTOROLA?
	JNZ	DLREC		; No, keep looking
; Download a MOTOROLA HEX format record
DLMOT:	CALL	INCHR		; Get next character
	CPI	'0'		; Header record?
	JZ	DLREC		; Yes, skip it
	CPI	'9'		; End of file?
	JZ	DLEOF		; Yes, report EOF
	CPI	'1'		; Type 1 (code) record
	JNZ	DLERR		; Report error
	CALL	GETBYT		; Get length
	MOV	C,A		; Start checksum
	SUI	3		; Convert for overhead
	MOV	B,A		; Save data length
	CALL	GETBYT		; Get first byte of address
	MOV	H,A		; Set HIGH address
	ADD	C		; Include in checksum
	MOV	C,A		; And re-save
	CALL	GETBYT		; Get next byte of address
	MOV	L,A		; Set LOW address
	ADD	C		; Include in checksum
	MOV	C,A		; And re-save
	CALL	SETOFF		; Handle record offsets
DMOT1:	CALL	GETBYT		; Get a byte of data
	MOV	M,A		; Save in memory
	INX	H		; Advance
	ADD	C		; Include in checksum
	MOV	C,A		; And re-save
	DCR	B		; Reduce length
	JNZ	DMOT1		; Keep going
	CALL	GETBYT		; Get record checksum
	ADD	C		; Include calculated checksum
	INR	A		; Adjust for test
	ANA	A		; Clear carry set Z
	RET
; Download a record in INTEL hex format
DLINT:	CALL	GETBYT		; Get length
	ANA	A		; End of file?
	JZ	DLEOF		; Yes, handle it
	MOV	C,A		; Begin Checksum
	MOV	B,A		; Record length
	CALL	GETBYT		; Get HIGH address
	MOV	H,A		; Set HIGH address
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
	CALL	GETBYT		; Get LOW address
	MOV	L,A		; Set LOW address
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
	CALL	SETOFF		; Handle record offsets
	CALL	GETBYT		; Get type byte
	ADD	C		; Include in checksum
	MOV	C,A		; Re-save
DLINT1:	CALL	GETBYT		; Get data byte
	MOV	M,A		; Save in memory
	INX	H		; Advance to next
	ADD	C		; Include in checksum
	MOV	C,A		; Resave checksum
	DCR	B		; Reduce count
	JNZ	DLINT1		; Do entire record
	CALL	GETBYT		; Get record checksum
	ADD	C		; Add to computed checksum
	ANA	A		; Clear carry, set Z
	RET
; End of file on download
DLEOF:	STC			; Set carry, EOF
	RET
;
; Process record offsets for download records
;
SETOFF:	LDA	BUFFER		; Get flag
	ANA	A		; Test flag
	JNZ	SETOF1		; Special case
; Not first record, adjust for offset & proceed
	XCHG			; DE = address
	LHLD	BUFFER+1	; Get offset
	DAD	D		; HL = address + offset
	RET
; First record, set USER BASE & calculate offset (if any)
SETOF1:	MVI	A,0		; Get zero (NO CC)
	STA	BUFFER		; Clear flag
	SHLD	UBASE		; Set user program base
	RP			; No more action
; Calculate record offset to RAM area
	XCHG			; DE = address
	LHLD	BUFFER+3	; Get operand
	MOV	A,L		; Subtract
	SUB	E		; Record
	MOV	L,A		; From
	MOV	A,H		; Operand
	SBB	D		; To get
	MOV	H,A		; Offset
	SHLD	BUFFER+1	; Set new offset
	DAD	D		; Get address
	RET
;
; Gets a byte of HEX data from serial port.
;
GETBYT:	CALL	GETNIB		; Get first nibble
	RLC			; Shift into
	RLC			; Upper nibble
	RLC			; Of result
	RLC			; To make room for lower
	MOV	E,A		; Keep high digit
	CALL	GETNIB		; Get second digit
	ORA	E		; Insert high digit
	RET
; GETS A NIBBLE FROM THE TERMINAL (IN ASCII HEX)
GETNIB:	CALL	INCHR		; Get a character
	SUI	'0'		; Is it < '0'?
	JC	GETN1		; Yes, invalid
	CPI	10		; 0-9?
	RC			; Yes, its OK
	SUI	7		; Convert
	CPI	10		; 9-A?
	JC	GETN1		; Yes, invalid
	CPI	16		; A-F?
	RC			; Yes, its OK
GETN1:	POP	D		; Remove GETNIB RET addr
	POP	D		; Remove GETBYT RET addr
; Error during download record
DLERR:	ORI	0FFh		; Error indicator
	RET
;
; Read an input line from the console
;
INPT:	LXI	H,BUFFER	; Point to input buffer
INPT1:	CALL	INCHR		; Get a char
	CPI	1Bh		; ESCAPE?
	JZ	RECR		; Back for command
	CPI	0Dh		; Carriage return?
	JZ	INPT4		; Yes, exit
	MOV	D,A		; Save for later
; Test for DELETE function
	CPI	7Fh		; Is it delete?
	JZ	INPT3		; Yes, it is
	CPI	08h		; Backspace?
	JZ	INPT3		; Yes, it is
; Insert character in buffer
	MOV	A,L		; Get low address
	CPI	(BUFFER&255)+30	; Beyond end?
	MVI	A,7		; Assume error
	JZ	INPT2		; Yes, report error
	MOV	A,D		; Get char back
	MOV	M,A		; Save in memory
	INX	H		; Advance
INPT2:	CALL	OUT		; Echo it
	JMP	INPT1		; And proceed
; Delete last character from buffer
INPT3:	MOV	A,L		; Get char
	CPI	BUFFER&255	; At begining
	MVI	A,7		; Assume error
	JZ	INPT2		; Report error
	PUSH	H		; Save H
	CALL	PRTMSG		; Output message
	DB	8,' ',8,0	; Wipe away character
	POP	H		; Restore H
	DCX	H		; Backup
	JMP	INPT1		; And proceed
; Terminate the command
INPT4:	MVI	M,0		; Zero terminate
	CALL	CRLF		; New line
	LXI	D,BUFFER	; Point to input buffer
; Advance to next non-blank in buffer
SKIP:	LDAX	D		; Get char from buffer
	INX	D		; Advance
	CPI	' '		; Space?
	JZ	SKIP		; Yes, keep looking
	DCX	D		; Backup to it
	JMP	TOCAP		; And convert to upper
;
; Read next character from command & convert to upper case
;
GETCHI:	INX	D		; Skip next character
GETCHR:	LDAX	D		; Get char from command line
	ANA	A		; End of line?
	RZ			; Yes, return with it
	INX	D		; Advance command pointer
;
; Convert character in A to uppercase, set Z if SPACE or EOL
;
TOCAP:	CPI	61h		; Lower case?
	JC	TOCAP1		; Yes, its ok
	ANI	5Fh		; Convert to UPPER
TOCAP1:	CPI	' '		; Space
	RZ			; Yes, indicate
	ANA	A		; Set 'Z' if EOL
	RET
;
; Get 8 bit HEX operands to command
;
CALC8:	CALL	CALC		; Get operand
	MOV	A,H		; High byte must be zero
	ORA	A
	JNZ	ERROR		; Bad value
	MOV	A,L		; Value also to A
	RET
;
; Get 16 bit HEX operands to command
;
CALC:	PUSH	B		; Save B-C
	CALL	SKIP		; Find start of operand
	LXI	H,0		; Begin with zero value
	MOV	C,H		; Clear flag
CALC1:	CALL	GETCHR		; Get next char
	JZ	CALC3		; End of number
	CALL	VALHEX		; Is it valid hex?
	JC	ERROR		; No, report error
	DAD	H		; HL = HL*2
	DAD	H		; HL = HL*4
	DAD	H		; HL = HL*8
	DAD	H		; HL = HL*16 (Shift over 4 bits)
	SUI	'0'		; Convert to ASCII
	CPI	10		; Decimal number?
	JC	CALC2		; Yes, its ok
	SUI	7		; Convert to HEX
CALC2:	ORA	L		; Include in final value
	MOV	L,A		; Resave low bute
	MVI	C,0FFh		; Set flag & indicate we have char
	JMP	CALC1		; And continue
; End of input string was found
CALC3:	MOV	A,C		; Get flag
	POP	B		; Restore B-C
	ANA	A		; Was there any digits?
	JZ	ERROR		; No, invalid
	RET
; Test for character in A as valid hex
VALHEX:	CPI	'0'		; < '0'
	RC			; Too low
	CPI	'G'		; >'F'
	CMC			; Set C state
	RC			; Too high
	CPI	3Ah		; <='9'
	CMC			; Set C state
	RNC			; Yes, its OK
	CPI	'A'		; Set C if < 'A'
	RET
;
; Display the user process registers
;
REGDIS:	LHLD	BC		; Get saved BC pair
	LXI	B,'BC'		; And register names
	CALL	OUTPT		; Output
	LHLD	DE		; Get saved DE pair
	LXI	B,'DE'		; And register names
	CALL	OUTPT		; Output
	LHLD	HL		; Get saved HL pair
	LXI	B,'HL'		; And register names
	CALL	OUTPT		; Output
	LHLD	SP		; Get saved SP
	LXI	B,'SP'		; And register name
	CALL	OUTPT		; Output
	LHLD	PC		; Get saved PC
	LXI	B,'PC'		; And regsiter name
	CALL	OUTPT		; Output
	CALL	PRTMSG		; Output message
	DB	" PSW=",0
	LHLD	PSW		; Get saved PSW
	CALL	HLOUT2		; Output value (with two spaces)
	CALL	PRTMSG		; Output
	DB	" FLAGS=",0
	LHLD	PSW-1		; Get Flags to H
	MVI	B,'S'		; 'S' flag
	CALL	OUTB		; Display
	MVI	B,'Z'		; 'Z' flag
	CALL	OUTB		; Display
	MVI	B,'K'		; 'K' flag
	CALL	OUTB		; Display
	MVI	B,'A'		; 'A' flag
	CALL	OUTB		; Display
	MVI	B,'3'		; 3. bit flag
	CALL	OUTB		; Display
	MVI	B,'P'		; 'P' flag
	CALL	OUTB		; Display
	MVI	B,'V'		; 'V' flag
	CALL	OUTB		; Display
	MVI	B,'C'		; 'C' flag
	CALL	OUTB		; Display
	JMP	CRLF		; New line & exit
; Display contents of a register pair
OUTPT:	MOV	A,B		; Get first char of name
	CALL	OUT		; Output
	MOV	A,C		; Get second char of name
	CALL	OUT		; Output
	MVI	A,'='		; Get separator
	CALL	OUT		; Output
HLOUT2:	CALL	HLOUT		; Output value
	CALL	SPACE		; Output a space
; Display a space on the console
SPACE:	MVI	A,' '		; Get a spave
	JMP	OUT		; Display it
; Display an individual flag bit B=title, H[7]=bit
OUTB:	DAD	H		; Shift H[7] into carry
	MVI	A,'-'		; Dash for not set flag
	JNC	OUT		; Display dash
	MOV	A,B		; Get character
	JMP	OUT		; And display
;
; Display an instruction in disassembly format
;
DINST:	PUSH	D		; Save address
	MOV	A,D		; Get high value
	CALL	HPR		; Output
	MOV	A,E		; Get low address
	CALL	HPR		; Output
	CALL	SPACE		; Output a space
	CALL	LOOK		; Lookup instruction
	ANI	03h		; Save length
	PUSH	PSW		; Save length
	PUSH	H		; Save table address
	MVI	B,4		; 4 spaces total
	MOV	C,A		; Save count
	DCX	D		; Backup address
; Display the opcode bytes in HEX
VLP1:	INX	D		; Advance
	LDAX	D		; Get opcode
	CALL	HPR		; Output in HEX
	CALL	SPACE		; Separator
	DCR	B		; Reduce count
	DCR	C		; Reduce count of opcodes
	JNZ	VLP1		; Do them all
; Fill in to boundary
VLP2:	CALL	SPACE		; Space over
	CALL	SPACE		; Space over
	CALL	SPACE		; Spave over
	DCR	B		; Reduce count
	JNZ	VLP2		; Do them all
; DISPLAY ASCII equivalent of opcodes
	POP	B		; Restore table address
	POP	PSW		; Restore type/length
	POP	D		; Restore instruction address
	PUSH	D		; Resave
	PUSH	PSW		; Resave
	MVI	H,8		; 8 spaces/field
	ANI	0Fh		; Save only length
	MOV	L,A		; Save for later
PCHR:	LDAX	D		; Get byte from opcode
	INX	D		; Advance
	CALL	OUTP		; Display (if printable)
	DCR	H		; Reduce field count
	DCR	L		; Reduce opcode count
	JNZ	PCHR		; Do them all
; Space over to instruction address
SPLP:	CALL	SPACE		; Output a space
	DCR	H		; Reduce count
	JNZ	SPLP		; Do them all
	MVI	D,6		; Field width
VLP3:	LDAX	B		; Get char from table
	ANA	A		; End of string?
	JZ	VOUT1		; Yes, exit
	CALL	OUT		; Output it
	INX	B		; Advance to next
	DCR	D		; reduce count
	CPI	' '		; end of name?
	JNZ	VLP3		; no, keep going
; Fill in name field with spaces
VOUT:	DCR	D		; reduce count
	JZ	VLP3		; Keep going
	CALL	SPACE		; Output a space
	JMP	VOUT		; And proceed
; Output operands for the instruction
VOUT1:	POP	PSW		; Restore type
	POP	D		; Restore instruction address
	DCR	A		; Is it type1?
	JZ	T1		; Yes, handle it
; Type 2 -  One byte immediate date
T2:	PUSH	PSW		; Save type
	MVI	A,'$'		; Get HEX indicator
	CALL	OUT		; Output
	POP	PSW		; Restore type
	DCR	A		; Type 2?
	JNZ	T3		; No, try next
	INX	D		; Advance to data
	LDAX	D		; Get data
	CALL	HPR		; Output in HEX
; Type 1 - No operand
T1:	INX	D
	RET
; Type 3 - Two bytes immediate data
T3:	INX	D		; Skip to low	
	INX	D		; Skip to high
	LDAX	D		; Get HIGH
	CALL	HPR		; Output
	DCX	D		; Backup to low
	LDAX	D		; Get LOW
	CALL	HPR		; Output
	INX	D		; Advance to high
	INX	D
	RET
;
; Look up instruction in table & return TYPE/LENGTH[A], and string[HL]
;
LOOK:	PUSH	D		; Save DE
	LDAX	D		; Get opcode
	MOV	B,A		; Save for later
	LXI	H,ITABLE	; Point to table
LOOK1:	MOV	A,B		; Get Opcode
	ANA	M		; Mask
	INX	H		; Skip mask
	CMP	M		; Does it match
	INX	H		; Skip opcode
	JZ	LOOK3		; Yes, we found it
; This wasn't it, advance to the next
LOOK2:	MOV	A,M		; Get byte
	INX	H		; Advance to next
	ANA	A		; End of string?
	JNZ	LOOK2		; No, keep looking
	JMP	LOOK1		; And continue
; We found the instruction, copy over the text description
LOOK3:	MOV	C,M		; Save type
	INX	H		; Skip type
	LXI	D,BUFFER	; Point to text buffer
LOOK4:	MOV	A,M		; Get char from source
	INX	H		; Advance to next
; Insert a RESTART vector number
	CPI	'v'		; Restart vector
	JNZ	LOOK5		; No, its OK
	MOV	A,B		; Get opcode
	RRC			; Shift it
	RRC			; Over
	RRC			; To low digit
	ANI	07h		; Remove trash
	ADI	'0'		; Convert to digit
	JMP	LOOK10		; And set the character
; Insert a register pair name
LOOK5:	CPI	'p'		; Register PAIR?
	JNZ	LOOK6		; No, try next
	MOV	A,B		; Get opcode
	RRC			; Shift
	RRC			; Over into
	RRC			; Low digit
	RRC			; For lookup
	ANI	03h		; Save only RP
	PUSH	H		; Save HL
	LXI	H,RPTAB		; Point to pair table
	JMP	LOOK9		; And proceed
; Insert destination register name
LOOK6:	CPI	'd'		; Set destination?
	JNZ	LOOK7		; No, try next
	MOV	A,B		; Get opcode
	RRC			; Shift
	RRC			; Into low
	RRC			; digit
	JMP	LOOK8		; And proceed
; Insert source register name
LOOK7:	CPI	's'		; Source register?
	JNZ	LOOK10		; No, its OK
	MOV	A,B		; Get opcode
; Lookup a general processor register
LOOK8:	ANI	07h		; Save only source
	PUSH	H		; Save HL
	LXI	H,RTAB		; Point to table
; Lookup register in table
LOOK9:	ADD	L		; Offset to value
	MOV	L,A		; Resave address
	MOV	A,M		; Get character
	CPI	'S'		; 'SP' register ?
	JNZ	LOOK9A		; No, skip
	STAX	D		; Save 'S'
	INX	D		; Advance to next
	MVI	A,'P'		; Character 'P'
LOOK9A:	POP	H		; Restore HL
; Save character in destination string
LOOK10:	STAX	D		; Save value
	INX	D		; Advance to next
	ANA	A		; End of list?
	JNZ	LOOK4		; No, keep copying
; End of LIST
	LXI	H,BUFFER	; Point to description
	MOV	A,C		; Get length
	POP	D		; Restore DE
	RET
;
; Opcode disassembly table: MASK, OPCODE, TYPE/LENGTH, STRINGZ
;
ITABLE:	DB	0FFh,0FEh,02h
	DB	"CPI ",0
	DB	0FFh,3Ah,03h
	DB	"LDA ",0
	DB	0FFh,32h,03h
	DB	"STA ",0
	DB	0FFh,2Ah,03h
	DB	"LHLD ",0
	DB	0FFh,22h,03h
	DB	"SHLD ",0
	DB	0FFh,0F5h,01h
	DB	"PUSH PSW",0
	DB	0FFh,0F1h,01h
	DB	"POP PSW",0
	DB	0FFh,27h,01h
	DB	"DAA",0
	DB	0FFh,76h,01h
	DB	"HLT",0
	DB	0FFh,0FBh,01h
	DB	"EI",0
	DB	0FFh,0F3h,01h
	DB	"DI",0
	DB	0FFh,37h,01h
	DB	"STC",0
	DB	0FFh,3Fh,01h
	DB	"CMC",0
	DB	0FFh,2Fh,01h
	DB	"CMA",0
	DB	0FFh,0EBh,01h
	DB	"XCHG",0
	DB	0FFh,0E3h,01h
	DB	"XTHL",0
	DB	0FFh,0F9h,01h
	DB	"SPHL",0
	DB	0FFh,0E9h,01h
	DB	"PCHL",0
	DB	0FFh,0DBh,02h
	DB	"IN ",0
	DB	0FFh,0D3h,02h
	DB	"OUT ",0
	DB	0FFh,07h,01h
	DB	"RLC",0
	DB	0FFh,0Fh,01h
	DB	"RRC",0
	DB	0FFh,17h,01h
	DB	"RAL",0
	DB	0FFh,1Fh,01h
	DB	"RAR",0
	DB	0FFh,0C6h,02h
	DB	"ADI ",0
	DB	0FFh,0CEh,02h
	DB	"ACI ",0
	DB	0FFh,0D6h,02h
	DB	"SUI ",0
	DB	0FFh,0DEh,02h
	DB	"SBI ",0
	DB	0FFh,0E6h,02h
	DB	"ANI ",0
	DB	0FFh,0F6h,02h
	DB	"ORI ",0
	DB	0FFh,0EEh,02h
	DB	"XRI ",0
	DB	0FFh,00h,01h
	DB	"NOP",0
; 8085 specific instructions
	DB	0FFh,20h,01h
	DB	"RIM",0
	DB	0FFh,30h,01h
	DB	"SIM",0
; 8085 undocumented instructions
	DB	0FFh,08h,01h
	DB	"DSUB B",0
	DB	0FFh,10h,01h
	DB	"ARHL",0
	DB	0FFh,18h,01h
	DB	"RDEL",0
	DB	0FFh,28h,02h
	DB	"LDHI ",0
	DB	0FFh,38h,02h
	DB	"LDSI ",0
	DB	0FFh,0CBh,01h
	DB	"RSTV",0
	DB	0FFh,0D9h,01h
	DB	"SHLX D",0
	DB	0FFh,0DDh,03h
	DB	"JNK ",0
	DB	0FFh,0EDh,01h
	DB	"LHLX D",0
	DB	0FFh,0FDh,03h
	DB	"JK ",0
; Jumps, Calls & Returns
	DB	0FFh,0C3h,0Bh
	DB	"JMP ",0
	DB	0FFh,0CAh,43h
	DB	"JZ ",0
	DB	0FFh,0C2h,4Bh
	DB	"JNZ ",0
	DB	0FFh,0DAh,13h
	DB	"JC ",0
	DB	0FFh,0D2h,1Bh
	DB	"JNC ",0
	DB	0FFh,0EAh,23h
	DB	"JPE ",0
	DB	0FFh,0E2h,2Bh
	DB	"JPO ",0
	DB	0FFh,0FAh,83h
	DB	"JM ",0
	DB	0FFh,0F2h,8Bh
	DB	"JP ",0
	DB	0FFh,0CDh,0Bh
	DB	"CALL ",0
	DB	0FFh,0CCh,43h
	DB	"CZ ",0
	DB	0FFh,0C4h,4Bh
	DB	"CNZ ",0
	DB	0FFh,0DCh,13h
	DB	"CC ",0
	DB	0FFh,0D4h,1Bh
	DB	"CNC ",0
	DB	0FFh,0ECh,23h
	DB	"CPE ",0
	DB	0FFh,0E4h,2Bh
	DB	"CPO ",0
	DB	0FFh,0FCh,83h
	DB	"CM ",0
	DB	0FFh,0F4h,8Bh
	DB	"CP ",0
	DB	0FFh,0C9h,05h
	DB	"RET",0
	DB	0FFh,0C8h,45h
	DB	"RZ",0
	DB	0FFh,0C0h,4Dh
	DB	"RNZ",0
	DB	0FFh,0D8h,15h
	DB	"RC",0
	DB	0FFh,0D0h,1Dh
	DB	"RNC",0
	DB	0FFh,0E8h,25h
	DB	"RPE",0
	DB	0FFh,0E0h,2Dh
	DB	"RPO",0
	DB	0FFh,0F8h,85h
	DB	"RM",0
	DB	0FFh,0F0h,8Dh
	DB	"RP",0
; Register based instructions
	DB	0C0h,40h,01h
	DB	"MOV d,s",0
	DB	0C7h,06h,02h
	DB	"MVI d,",0
	DB	0F8h,90h,01h
	DB	"SUB s",0
	DB	0F8h,98h,01h
	DB	"SBB s",0
	DB	0F8h,80h,01h
	DB	"ADD s",0
	DB	0F8h,88h,01h
	DB	"ADC s",0
	DB	0F8h,0A0h,01h
	DB	"ANA s",0
	DB	0F8h,0B0h,01h
	DB	"ORA s",0
	DB	0F8h,0A8h,01h
	DB	"XRA s",0
	DB	0F8h,0B8h,01h
	DB	"CMP s",0
	DB	0C7h,04h,01h
	DB	"INR d",0
	DB	0C7h,05h,01h
	DB	"DCR d",0
; Register pair instructions
	DB	0CFh,01h,03h
	DB	"LXI p,",0
	DB	0EFh,0Ah,01h
	DB	"LDAX p",0
	DB	0EFh,02h,01h
	DB	"STAX p",0
	DB	0CFh,03h,01h
	DB	"INX p",0
	DB	0CFh,0Bh,01h
	DB	"DCX p",0
	DB	0CFh,09h,01h
	DB	"DAD p",0
	DB	0CFh,0C5h,01h
	DB	"PUSH p",0
	DB	0CFh,0C1h,01h
	DB	"POP p",0
; Restart instruction
	DB	0C7h,0C7h,01h
	DB	"RST v",0
; This entry always matches invalid opcodes
	DB	00h,00h,01h
	DB	"DB ",0
; Misc Strings and messages
ON:	DB	"ON ",0
OFF:	DB	"OFF",0
AUTMSG:	DB	"AUTOREG=",0
SUBMSG:	DB	" SUBTRACE=",0
TRCMSG:	DB	" TRACE=",0
HTEXT:	DB	"MON85 Commands:"
	DB	0Dh,0Ah,0
	DB	"A ON|OFF!Enable/Disable Automatic register display",0
	DB	"B [bp address]!Set/Display breakpoints",0
	DB	"C <src> <dest> <size>!Copy memory",0
	DB	"D <address>!Display memory in assembly format",0
	DB	"E <address>!Edit memory",0
	DB	"F <start> <end> <value>!Fill memory",0
	DB	"G [address]!Begin/Resume execution",0
	DB	"H <start> <end>!Send out memory in Intel HEX format",0
	DB	"I <port>!Input from port",0
	DB	"L [address]!Load image into memory",0
	DB	"M <address>!Display memory in hex dump format",0
	DB	"O <port> <data>!Output to port",0
	DB	"R [rp value]!Set/Display program registers",0
	DB	"S ON|OFF!Enable/Disable Subroutine trace",0
	DB	"T ON|OFF!Enable/Disable Trace mode",0
	DB	"U [address]!Set/Display program base address",0
	DB	0
;
; Read a character, and wait for it
;
INCHR:	CALL	IN		; Check for a character
	ANA	A		; Is there any data?
	JZ	INCHR		; Wait for it
	RET
;
; Display HL in hexidecimal
;
HLOUT:	MOV	A,H		; Get HIGH byte
	CALL	HPR		; Output
	MOV	A,L		; Get LOW byte
;
; Display A in hexidecimal
;
HPR:	PUSH	PSW		; Save low digit
	RRC			; Shift
	RRC			; high
	RRC			; digit
	RRC			; into low
	CALL	HOUT		; Display a single digit
	POP	PSW		; Restore low digit
HOUT:	ANI	0Fh		; Remove high digit
	CPI	10		; Convert to ASCII
	SBI	2Fh
	DAA
	JMP	OUT		; And output it
;
; Display message [PC]
;
PRTMSG:	POP	H		; Get address
	CALL	PRTSTR		; Output message
	PCHL			; And return
;
; Display message [HL]
;
PRTSTR:	MOV	A,M		; Get byte from message
	INX	H		; Advance to next
	ANA	A		; End of message?
	RZ			; Yes, exit
	CALL	OUT		; Output the character
	JMP	PRTSTR		; And proceed
;
; Handle output suspension
;
CHKSUS:	CALL	CRLF		; New line
	LDA	OFLAG		; Is output suspended?
	ANA	A		; Test flag
	JNZ	CHKS1		; Yes it is
	CALL	IN		; Test for CONTROL-C interrupt
	CPI	1Bh		; ESCAPE?
	JZ	REST		; Abort
	CPI	' '		; SPACE - Suspend command
	RNZ
	STA	OFLAG		; Set the flag
; Output is suspended, wait for command
CHKS1:	CALL	INCHR		; Get char
	CPI	' '		; One line?
	RZ			; Allow it
	CPI	1Bh		; ESCAPE?
	JZ	REST		; Abort
	CPI	0Dh		; Resume?
	JNZ	CHKS1		; Keep going
	SUB	A		; Reset flag
	STA	OFLAG		; Write it
	RET
; Display a character if its printable
OUTP:	CPI	' '		; < ' '
	JC	OUTP1		; Invalid, exchange it
	CPI	7Fh		; Printable?
	JC	OUT		; Ok to display
OUTP1:	MVI	A,'.'		; Set to DOT to indicate invalid
	JMP	OUT		; And display
;
; Write a Line-Feed and Carriage-Return to console
;
CRLF:	MVI	A,0Dh		; Carriage return
	CALL	OUT		; Output
	MVI	A,0Ah		; Line-feed
;
; User supplied I/O routines.
;-----------------------------------------------------------
; NOTE: "OUT" must appear first because "CRLF" falls into it.
;
; Write character in A to console (8251 uart)
OUT:	PUSH	PSW		; Save char
OUT1:	IN	9		; Get 8251 status
	RRC			; Test TX bit
	JNC	OUT1		; Not ready
	POP	PSW		; Restore char
	OUT	8		; Write 8251 data
	RET
; Check for a character from the console (8251 uart)
IN:	IN	9		; Get 8251 status
	ANI	00000010b	; Test for ready
	RZ			; No char
	IN	8		; Get 8251 data
	RET
;
; Initialize the timer & uart
;
; 8251A initialisation, according to datasheet (3x 00h + RESET 040h)  
INIT:	XRA	A		; Insure not setup mode
	OUT	9		; Write once
	OUT	9		; Write again (now in operate mode)
	OUT	9		; Write again (now in operate mode)
	MVI	A,01000000b	; Reset
	OUT	9		; write it
	MVI	A,01001110b	; 8 data, 1 stop, x16
	OUT	9		; Write it
	MVI	A,00010101b	; RTS,DTR,Enable RX,TX
	OUT	9		; Write it
; starts timer in 8155 RIOT chip
; timer count rate 307200Hz, with divider 15360(3C00H)
; is the resulting interrupt rate exactly 20Hz
I8155:	XRA	A		; counter low 8 bits
	OUT	04h
	MVI	A,7Ch		; counter high 6 bits + mode cont.square -> 0 1
	OUT	05h
	MVI	A,0C0h		; 8155 mode, start timer,
	OUT	00h		; disable port C interrupts, all ports input
	RET

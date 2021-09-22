; USART registers
USART_DATA:	EQU	00h
USART_CMD:	EQU	01h

START:		LXI	H,0C000h
		SPHL
		CALL	USART_INIT

; write a banner
		MVI	A,38h	; '8'
		MOV	C,A
		CALL	USART_OUT
		MVI	A,30h	; '0'
		MOV	C,A
		CALL	USART_OUT
		MVI	A,38h	; '8'
		MOV	C,A
		CALL	USART_OUT
		MVI	A,35h	; '5'
		MOV	C,A
		CALL	USART_OUT
		MVI	A,0Dh	; CR
		MOV	C,A
		CALL	USART_OUT
		MVI	A,0Ah	; LF
		MOV	C,A
		CALL USART_OUT

LOOP:		CALL USART_IN
		MOV C,A
		CALL USART_OUT
		JMP LOOP

USART_INIT: 	MVI A,00h
; Set USART to command mode - configure sync operation, write two dummy sync characters
		OUT USART_CMD
		OUT USART_CMD
		OUT USART_CMD
; Issue reset command
		MVI A,40h
		OUT USART_CMD
; Write mode instruction - 1 stop bit, no parity, 8 bits, divide clock by 16
		MVI A,4Eh
		OUT USART_CMD
; Write command instruction - activate RTS, reset error flags, enable RX, activate DTR, enable TX
		MVI A,37h
		OUT USART_CMD
; Clear the data register
		IN USART_DATA
		RET

; Read character from USART
USART_IN:	IN	USART_CMD	; Read USART status
		ANI	02h		; Test RxRdy bit
		JZ	USART_IN	; Wait for the data
		IN	USART_DATA	; Read character
		RET

; Write character to USART
USART_OUT:	IN	USART_CMD
		ANI	01h		; Test TxRdy
		JZ	USART_OUT	; Wait until USART is ready to transmit
		MOV	A,C
		OUT	USART_DATA	; Write character
		RET

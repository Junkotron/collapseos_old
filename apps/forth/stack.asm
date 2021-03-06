; The Parameter stack (PS) is maintained by SP and the Return stack (RS) is
; maintained by IX. This allows us to generally use push and pop freely because
; PS is the most frequently used. However, this causes a problem with routine
; calls: because in Forth, the stack isn't balanced within each call, our return
; offset, when placed by a CALL, messes everything up. This is one of the
; reasons why we need stack management routines below. IX always points to RS'
; Top Of Stack (TOS)
;
; This return stack contain "Interpreter pointers", that is a pointer to the
; address of a word, as seen in a compiled list of words.

; Push value HL to RS
pushRS:
	inc	ix
	inc	ix
	ld	(ix), l
	ld	(ix+1), h
	ret

; Pop RS' TOS to HL
popRS:
	ld	l, (ix)
	ld	h, (ix+1)
	dec ix
	dec ix
	ret

; Verifies that SP is within bounds. If it's not, call ABORT
chkPS:
	ld	hl, (INITIAL_SP)
	; We have the return address for this very call on the stack. Let's
	; compensate
	dec	hl \ dec hl
	or	a		; clear carry
	sbc	hl, sp
	ret	nc		; (INITIAL_SP) >= SP? good
	; underflow
	ld	hl, .msg
	call	printstr
	jp	abort
.msg:
	.db "stack underflow", 0

; Return address of scratchpad in HL
pad:
	ld	hl, (HERE)
	ld	a, PADDING
	jp	addHL

; Read word from (INPUTPOS) and return, in HL, a null-terminated word.
; Advance (INPUTPOS) to the character following the whitespace ending the
; word.
; Z set of word was read, unset if end of line.
readword:
	ld	hl, (INPUTPOS)
	; skip leading whitespace
	dec	hl	; offset leading "inc hl"
.loop1:
	inc	hl
	ld	a, (hl)
	or	a
	jr	z, .empty
	cp	' '+1
	jr	c, .loop1
	push	hl		; --> lvl 1. that's our result
.loop2:
	inc	hl
	ld	a, (hl)
	; special case: is A null? If yes, we will *not* inc A so that we don't
	; go over the bounds of our input string.
	or	a
	jr	z, .noinc
	cp	' '+1
	jr	nc, .loop2
	; we've just read a whitespace, HL is pointing to it. Let's transform
	; it into a null-termination, inc HL, then set (INPUTPOS).
	xor	a
	ld	(hl), a
	inc	hl
.noinc:
	ld	(INPUTPOS), hl
	pop	hl		; <-- lvl 1. our result
	ret	; Z set from XOR A
.empty:
	ld	(hl), a
	inc	a	; unset Z
	ret

; Sets Z if (HL) == E and (HL+1) == D
HLPointsDE:
	ld	a, (hl)
	cp	e
	ret	nz		; no
	inc	hl
	ld	a, (hl)
	dec	hl
	cp	d		; Z has our answer
	ret


HLPointsNUMBER:
	push	de
	ld	de, NUMBER
	call	HLPointsDE
	pop	de
	ret

HLPointsLIT:
	push	de
	ld	de, LIT
	call	HLPointsDE
	pop	de
	ret

HLPointsEXITQUIT:
	push	de
	ld	de, EXIT
	call	HLPointsDE
	jr	z, .end
	ld	de, QUIT
	call	HLPointsDE
.end:
	pop	de
	ret

; Skip the compword where HL is currently pointing. If it's a regular word,
; it's easy: we inc by 2. If it's a NUMBER, we inc by 4. If it's a LIT, we skip
; to after null-termination.
compSkip:
	call	HLPointsNUMBER
	jr	z, .isNum
	call	HLPointsLIT
	jr	nz, .isWord
	; We have a literal
	inc	hl \ inc hl
	call	strskip
	inc	hl		; byte after word termination
	ret
.isNum:
	; skip by 4
	inc	hl \ inc hl
	; continue to isWord
.isWord:
	; skip by 2
	inc	hl \ inc hl
	ret

; ***readLIT***
; The goal of this routine is to read a string literal following the currently
; executed words. For example, CREATE and DEFINE need this. Things are a little
; twisted, so bear with me while I explain how it works.
;
; When we call this routine, everything has been compiled. We're on an atom and
; we're executing it. Now, we're looking for a string literal or a word-with-a
; name that follows our readLIT caller. We could think that this word is
; right there on RS' TOS, but not always! You have to account for words wrapping
; the caller. For example, "VARIABLE" calls "CREATE". If you call
; "VARIABLE foo", if CREATE looks at what follows in RS' TOS, it will only find
; the "2" in "CREATE 2 ALLOT".
;
; In this case, we actually need to check in RS' *bottom of stack* for our
; answer. If that atom is a LIT, we're good. We make HL point to it and advance
; IP to byte following null-termination.
;
; If it isn't, things get interesting: If it's a word reference, then it's
; not an invalid literal. For example, one could want to redefine an existing
; word. So in that case, we'll copy the word's name on the pad (it might not be
; null-terminated) and set HL to point to it.
; How do we know that our reference is a word reference (it could be, for
; example, a NUMBER reference)? We check that its address is more than QUIT, the
; second word in our dict. We don't accept EXIT because it's the termination
; word. Yeah, it means that ";" can't be overridden...
; If name can't be read, we abort
;
; BOS vs TOS: What we cover so far is the "CREATE" and friends cases, where we
; want to read BOS. There are, however, cases where we want to read TOS, that is
; that we want to read the LIT right next to our atom. Example: "(". When
; processing comments, we are at compile time and want to read words from BOS,
; yes), however, in "("'s definition, there's "LIT@ )", which means "fetch LIT
; next to me and push this to stack". This LIT we want to fetch is *not* from
; BOS, it's from TOS.
;
; This is why we have readLITBOS and readLITTOS. readLIT uses HL and DE and is
; not used directly.

; Given a RS stack pointer HL, read LIT next to it (or abort) and set HL to
; point to its associated string. Set DE to there the RS stack pointer should
; point next.
readLIT:
	call	HLPointsLIT
	jr	nz, .notLIT
	; RS BOS is a LIT, make HL point to string, then skip this RS compword.
	inc	hl \ inc hl	; HL now points to string itself
	; HL has our its final value
	ld	d, h
	ld	e, l
	call	strskip
	inc	hl		; byte after word termination
	ex	de, hl
	ret
.notLIT:
	; Alright, not a literal, but is it a word? If it's not a number, then
	; it's a word.
	call	HLPointsNUMBER
	jr	z, .notWord
	call	HLPointsEXITQUIT
	jr	z, .notWord
	; Not a number, then it's a word. Copy word to pad and point to it.
	push	hl		; --> lvl 1. we need it to set DE later
	call	intoHL
	or	a		; clear carry
	ld	de, CODELINK_OFFSET
	sbc	hl, de
	; That's our return value
	push	hl		; --> lvl 2
	; HL now points to word offset, let'd copy it to pad
	ex	de, hl
	call	pad
	ex	de, hl
	ld	bc, NAMELEN
	ldir
	; null-terminate
	xor	a
	ld	(de), a
	pop	hl		; <-- lvl 2
	pop	de		; <-- lvl 1
	; Advance IP by 2
	inc	de \ inc de
	ret
.notWord:
	ld	hl, .msg
	call	printstr
	jp	abort
.msg:
	.db "word expected", 0

readLITBOS:
	push	de
	ld	hl, (RS_ADDR)
	call	readLIT
	ld	(RS_ADDR), de
	pop	de
	ret

readLITTOS:
	push	de
	ld	l, (ix)
	ld	h, (ix+1)
	call	readLIT
	ld	(ix), e
	ld	(ix+1), d
	pop	de
	ret

; For DE being a wordref, move DE to the previous wordref.
; Z is set if DE point to 0 (no entry). NZ if not.
prev:
	dec	de \ dec de	; prev field
	call	intoDE
	; DE points to prev. Is it zero?
	xor	a
	or	d
	or	e
	; Z will be set if DE is zero
	ret

; Find the entry corresponding to word where (HL) points to and sets DE to
; point to that entry.
; Z if found, NZ if not.
find:
	push	hl
	push	bc
	ld	de, (CURRENT)
	ld	bc, CODELINK_OFFSET
.inner:
	; DE is a wordref, let's go to beginning of struct
	push	de		; --> lvl 1
	or	a		; clear carry
	ex	de, hl
	sbc	hl, bc
	ex	de, hl		; We're good, DE points to word name
	ld	a, NAMELEN
	call	strncmp
	pop	de		; <-- lvl 1, return to wordref
	jr	z, .end		; found
	call	prev
	jr	nz, .inner
	; Z set? end of dict unset Z
	inc	a
.end:
	pop	bc
	pop	hl
	ret

; Write compiled data from HL into IY, advancing IY at the same time.
wrCompHL:
	ld	(iy), l
	inc	iy
	ld	(iy), h
	inc	iy
	ret

; Compile word string at (HL) and write down its compiled version in IY,
; advancing IY to the byte next to the last written byte.
compile:
	call	find
	jr	nz, .maybeNum
	ex	de, hl
	jr	wrCompHL
.maybeNum:
	push	hl		; --> lvl 1. save string addr
	call	parseLiteral
	jr	nz, .undef
	pop	hl		; <-- lvl 1
	; a valid number!
	ld	hl, NUMBER
	call	wrCompHL
	ex	de, hl		; number in HL
	jr	wrCompHL
.undef:
	; When encountering an undefined word during compilation, we spit a
	; reference to litWord, followed by the null-terminated word.
	; This way, if a preceding word expect a string literal, it will read it
	; by calling readLIT, and if it doesn't, the routine will be
	; called, triggering an abort.
	ld	hl, LIT
	call	wrCompHL
	pop	hl		; <-- lvl 1. recall string addr
.writeLit:
	ld	a, (hl)
	ld	(iy), a
	inc	hl
	inc	iy
	or	a
	jr	nz, .writeLit
	ret


; Spit name + prev in (HERE) and adjust (HERE) and (CURRENT)
; HL points to new (HERE)
entryhead:
	call	readLITBOS
	ld	de, (HERE)
	call	strcpy
	ex	de, hl		; (HERE) now in HL
	ld	de, (CURRENT)
	ld	a, NAMELEN
	call	addHL
	xor	a		; IMMED
	ld	(hl), a
	inc	hl
	ld	(hl), e
	inc	hl
	ld	(hl), d
	inc	hl
	ld	(CURRENT), hl
	ld	(HERE), hl
	xor	a		; set Z
	ret

; Sets Z if wordref at (HL) is of the IMMEDIATE type
HLPointsIMMED:
	push	hl
	call	intoHL
	dec	hl
	dec	hl
	dec	hl
	; We need an invert flag. We want to Z to be set when flag is non-zero.
	ld	a, 1
	and	(hl)
	dec	a	; if A was 1, Z is set. Otherwise, Z is unset
	inc	hl
	inc	hl
	inc	hl
	pop	hl
	ret

; Checks flags Z and C and sets BC to 0 if Z, 1 if C and -1 otherwise
flagsToBC:
	ld	bc, 0
	ret	z	; equal
	inc	bc
	ret	c	; >
	; <
	dec	bc
	dec	bc
	ret


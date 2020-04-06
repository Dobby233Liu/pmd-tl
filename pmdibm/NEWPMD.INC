
	;
	;@‚o‚l‚c—pƒCƒ“ƒNƒ‹ƒhƒtƒ@ƒCƒ‹
	;

;
;	’è”
;
vrtcvector	equ	0ah
pmdvector	equ	60h
_p		equ	2
_m		equ	3
_d		equ	4
_tonadr		equ	5
_vrtcofs	equ	9
_vrtcseg	equ	11
_mstart		equ	13
_mstop		equ	16
_fout		equ	19
_effgo		equ	22
_effoff		equ	25f
_getss		equ	28
_getfv		equ	31

mstart		equ	0
mstop		equ	1
fout		equ	2
efcon		equ	3
efcoff		equ	4
getss		equ	5
get_music_adr	equ	6
get_tone_adr	equ	7
getfv		equ	8
board_check	equ	9
get_status	equ	10
get_efc_adr	equ	11
fm_efcon	equ	12
fm_efcoff	equ	13
get_pcm_adr	equ	14
pcm_efcon	equ	15
get_workadr	equ	16
get_fmefc_num	equ	17
get_pcmefc_num	equ	18
set_fm_int	equ	19
set_efc_int	equ	20
get_effon	equ	21
get_joystick	equ	22
get_pcmdrv_flag	equ	23
set_pcmdrv_flag	equ	24
set_fout_vol	equ	25
pause_on	equ	26
pause_off	equ	27
ff_music	equ	28
get_memo	equ	29

msdos_exit	macro
	mov	ax,4c00h
	int	21h
	endm

error_exit	macro	qq
	mov	ax,4c00h+qq
	int	21h
	endm

print_mes	macro	qq
	mov	dx,offset qq
	mov	ah,09h
	int	21h
	endm

print_chr	macro
	mov	ah,02
	int	21h
	endm

pmd	macro	qq
	mov	ah,qq
	int	pmdvector
	endm

;==============================================================================
;	‚o‚l‚c‚Ìí’“‚µ‚Ä‚¢‚éƒZƒOƒƒ“ƒg‚ğ“¾‚é
;==============================================================================
check_pmd:
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]
;==============================================================================
;	‚o‚l‚c‚ªí’“‚µ‚Ä‚¢‚é‚©‚ğŠÏ‚é
;==============================================================================
	cmp	byte ptr es:_p[bx],"P"
	jnz	notpmd
	cmp	byte ptr es:_m[bx],"M"
	jnz	notpmd
	cmp	byte ptr es:_d[bx],"D"
	jnz	notpmd
	ret
notpmd:	stc
	ret


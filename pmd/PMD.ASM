;==============================================================================
;	Professional Music Driver [P.M.D.] version 4.8sen
;					FOR PC98 (+ Speak Board)
;			By M.Kajihara
;==============================================================================

ver		equ	"4.8sen"
vers		equ	48H
verc		equ	"s"
date		equ	"3/11/2020"

mdata_def	equ	16
voice_def	equ	8
effect_def	equ	4
key_def		equ	1

ifndef	_myname
_myname		equ	"PMD     COM"
endif

ifndef	va
va		=	0	;１の時ＶＡMSDOS用
endif
ifndef	board2
board2		=	0	;１の時ボード２/音美ちゃん有り
endif
ifndef	adpcm
adpcm		=	0	;１の時ADPCM使用
endif
ifndef	ademu
ademu		=	0	;１の時ADPCM Emulate
endif
ifndef	pcm
pcm		=	0	;１の時PCM使用
endif
ifndef	ppz
ppz		=	0	;１の時PPZ8使用
endif
ifndef	sync
sync		=	0	;１の時MIDISYNC使用
endif
ifndef	vsync
vsync		=	0	;１の時VSyncを止める
endif
ifndef	resmes
resmes	equ	"PMD ver.",ver
endif

if	va+board2
fmvd_init	=	0
else
fmvd_init	=	16	;９８は８８よりもＦＭ音源を小さく
endif

;==============================================================================
;	INT 60H 仕様
;==============================================================================
;			input		output		remarks.
;	MUSIC_START	AH=00H		AH=255で処理中	演奏の開始
;	MUSIC_STOP	AH=01H		AH=255で処理中	演奏の停止
;	FADEIN/OUT	AH=02H/AL=speed			speed=1で最低速
;							speed=-でfadein
;	EFFECT_ON	AH=03H/AL=efcnum		効果音の発音
;	EFFECT_OFF	AH=04H				効果音の消音
;	GET_SYOUSETU	AH=05H		AX=syousetu	演奏開始して何小節目か
;	GET_MUSDAT_ADR	AH=06H		DS:DX=MDAT_ADR	曲データを読み込む場所
;	GET_TONDAT_ADR	AH=07H		DS:DX=TDAT_ADR	音色データの場所
;	GET_FOUT_VOL	AH=08H		AL=FOUT_VOL	255でFADEOUT終了
;	BOARD_CHECK	AH=09H		AL=BOARD_CHK	0=PMD/1=B2/2=86/-1=なし
;					AH=Vernum	PMD Version
;					DX=Vernum/chr	PMD Version
;	GET_STATUS	AH=0AH		AH=ST1/AL=ST2	STATUSの取り込み
;	GET_EFCDAT_ADR	AH=0BH		DS:DX=EDAT_ADR	FM効果音データの場所
;	FM_EFFECT_ON	AH=0CH/AL=efcnum		FM効果音発音
;	FM_EFFECT_OFF	AH=0DH				FM効果音消音
;	GET_PCM_ADR	AH=0EH		DS:DX=PCM_TABLE	PCMテーブルの位置
;	PCM_EFFECT_ON	AH=0FH/AL=efcnum		PCM効果音発音
;			DX=DeltaN
;			CH=Pan/CL=Volume
;	GET_WORKADR	AH=10H		DS:DX=WORK	WORKの位置
;	GET_FMEFC_NUM	AH=11H		AL=FMEFC_NUM	FM効果音番号(none=255)
;	GET_PCMEFC_NUM	AH=12H		AL=PCMEFC_NUM	PCM効果音番号(none=255)
;	SET_FM_INT	AH=13H				FM音源割り込み時に飛ぶ
;			DS:DX=ADDRESS(0=cut)		割り込み先を設定
;	SET_EFC_INT	AH=14H				効果音割り込み時に飛ぶ
;			DS:DX=ADDRESS(0=cut)		割り込み先を設定
;	GET_PSGEFCNUM	AH=15H		AH=PSGEFCNUM	SSG効果音番号(none=0)
;					AL=EFFON	同 優先順位
;	GET_JOYSTICK	AH=16H		AL=JOYSTICK1	ジョイスティック読込み
;					AH=JOYSTICK2	bit = xxBARLDU
;	GET_ppsdrv_FLAG	AH=17H		AL=ppsdrv_FLAG	ppsdrv対応フラグREAD
;	SET_ppsdrv_FLAG	AH=18H				ppsdrv対応フラグWRITE
;			AL=ppsdrv_FLAG
;	SET_FOUT_VOL	AH=19H				全体音量設定(0～255)
;			AL=FOUT_VOL
;	PAUSE on	AH=1AH				ポーズ
;	PAUSE off	AH=1BH				ポーズ解除
;	FF_MUSIC	AH=1CH		AL=0/正常	ALの小節番号まで早送り
;			DX=小節番号	1=既に過ぎてる/2=曲停止中
;	GET_MEMO	AH=1DH		DS:DX=MEMOadr	曲中のメモのaddressの
;			AL=MEMO番号	00:00は無し	取り出し
;	PART_MASK	AH=1EH				パートのマスク/解除
;			AL=PART番号(+80H)		+80Hでマスク解除
;	GET_FM_INT	AH=1FH		DS:DX		FM音源割り込み時に飛ぶ
;					(ADDRESS)	割り込み先を取得
;	GET_EFC_INT	AH=20H		DS:DX		効果音割り込み時に飛ぶ
;					(ADDRESS)	割り込み先を取得
;	GET_FILE_ADR	AH=21H		DS:DX(ADDRESS)	演奏中曲File名位置取得
;	GET_SIZE	AH=22H		AL=MUSDATA	常駐サイズ確認
;					AH=VOICEDATA	(ＫＢ単位)
;					DL=EFFECDATA
;==============================================================================

pmdvector	=	60h		;PMD用の割り込みベクトル
ppsdrv		=	64h		;ppsdrvの割り込みベクトル
ppz_vec		=	7fh		;ppz8の割り込みベクトル

@code	segment	para	public	'@code'
	assume	cs:@code,ds:@code,es:@code,ss:@code

	org	100h

pmd	proc	near

	jmp	comstart

;==============================================================================
;	ＭＳ－ＤＯＳコールのマクロ
;==============================================================================

resident_exit	macro
		mov	ax,3100h
		int	21h
		endm

resident_cut	macro
		mov	ah,49h
		int	21h
		endm

get_psp 	macro
		mov	ah,51h
		int	21h
		endm

msdos_exit	macro
		mov	ax,4c00h
		int	21h
		endm

error_exit	macro	qq
		mov	ax,4c00h+qq
		int	21h
		endm

print_mes	macro	qq
		if	va
			push	si
			lea	si,qq
			mov	dh,80h
			mov	ah,02h
			int	83h
			pop	si
		else
			mov	dx,offset qq
			mov	ah,09h
			int	21h
		endif
		endm

print_dx	macro
		if	va
			push	si
			mov	si,dx
			mov	dh,80h
			mov	ah,02h
			int	83h
			pop	si
		else
			mov	ah,09h
			int	21h
		endif
		endm

debug		macro	qq
		push	es
		push	ax
		mov	ax,0a000h
		mov	es,ax
		inc	byte ptr es:[qq*2]
		pop	ax
		pop	es
		endm

debug2		macro	q1,q2
		push	es
		push	ax
		mov	ax,0a000h
		mov	es,ax
		mov	byte ptr es:[q1*2],q2
		pop	ax
		pop	es
		endm

debug_pcm	macro	qq
local		zzzz
		push	ax
		push	dx
		mov	dx,0a468h
		in	al,dx
		test	al,10h
		jz	zzzz
		debug	qq
zzzz:		pop	dx
		pop	ax
		endm

_wait		macro
		mov	cx,[wait_clock]
		loop	$
		endm

_waitP		macro
		push	cx
		mov	cx,[wait_clock]
		loop	$
		pop	cx
		endm

_rwait		macro			;リズム連続出力用wait
		push	cx
		mov	cx,[wait_clock]
		add	cx,cx
		add	cx,cx
		add	cx,cx
		add	cx,cx
		add	cx,cx			;x32
		loop	$
		pop	cx
		endm

rdychk		macro			;Address out時用	break:ax
local		loop
		in	al,dx		;無駄読み
loop:		in	al,dx
		test	al,al
		js	loop
		endm

_ppz		macro
local		exit
if		ppz
		cmp	[ppz_call_seg],2
		jc	exit
		call	dword ptr [ppz_call_ofs]
exit:
endif
		endm

;==============================================================================
;	定数
;==============================================================================
if	va

ms_cmd		equ	188h		; ８２５９マスタポート
ms_msk		equ	18ah		; ８２５９マスタ／マスク
sl_cmd		equ	184h		; ８２５９スレーブポート
sl_msk		equ	186h		; ８２５９スレーブ／マスク

else

ms_cmd		equ	000h		; ８２５９マスタポート
ms_msk		equ	002h		; ８２５９マスタ／マスク
sl_cmd		equ	008h		; ８２５９スレーブポート
sl_msk		equ	00ah		; ８２５９スレーブ／マスク

endif

;==============================================================================
;	Program Start
;==============================================================================

int60_head:	jmp	short	int60_main
		db	'PMD'	;+2  常駐チェック用
		db	vers	;+5
		db	verc	;+6
int60ofs	dw	?	;+7
int60seg	dw	?	;+9
int5ofs		dw	?	;+11
int5seg		dw	?	;+13
maskpush	db	?	;+15
vector		dw	?	;+16
int_level	db	?	;+18

_p		equ	2
_m		equ	3
_d		equ	4
_vers		equ	5
_verc		equ	6
_int60ofs	equ	7
_int60seg	equ	9
_int5ofs	equ	11
_int5seg	equ	13
_maskpush	equ	15
_vector		equ	16
_int_level	equ	18

int60_main:
	inc	cs:[int60flag]
	cmp	ah,int60_max+1
	jnc	int60_error
	cmp	cs:[board],0
	jnz	int60_start
	jmp	int60_start_not_board
int60_exit:
	cli
	dec	cs:[int60flag]
	mov	cs:[int60_result],0
	iret
int60_error:
if	sync
	cmp	ah,-1
	jnz	no_sync
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	call	opnint_sub
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	dec	cs:[int60flag]
	iret
no_sync:
endif
	cli
	dec	cs:[int60flag]
	mov	cs:[int60_result],-1
	iret

;==============================================================================
;	ＰＣＭドライバ　ＩＮＣＬＵＤＥ
;==============================================================================
if	board2
 if	pcm
	include	pcmdrv86.asm
 endif
 if	adpcm
  if	ademu
	include	pcmdrve.asm
  else
	include	pcmdrv.asm
  endif
 endif
 if	ppz
	include	ppzdrv.asm
 endif
endif

;==============================================================================
;	ＥＦＦＥＣＴドライバ　ＩＮＣＬＵＤＥ
;==============================================================================
	include	efcdrv.asm

getss:
	mov	ax,cs:[syousetu]
	ret

getst:
	mov	ah,cs:[status]
	mov	al,cs:[status2]
	ret

fout:	mov	cs:[fadeout_speed],al
	ret

;==============================================================================
;	ＦＭ効果音演奏メイン
;==============================================================================
fm_efcplay:
	mov	bx,[efcdat]
	mov	ax,254[bx]
	add	ax,bx
	mov	[prgdat_adr2],ax

	mov	di,offset part_e
if	board2
	push	[fm_port1]	;mmainでsel44状態でTimerA割り込みが来た時用の
	push	[fm_port2]	;対策
	mov	ah,[partb]
	mov	al,[fmsel]
	push	ax
	mov	[partb],3
	call	sel46		;ここでmmainが来てもsel46のまま
	call	fmmain
	pop	ax
	mov	[partb],ah
	mov	[fmsel],al
	pop	[fm_port2]
	pop	[fm_port1]
else
	mov	al,[partb]
	push	ax
	mov	[partb],3
	call	fmmain
	pop	ax
	mov	[partb],al
endif
	cmp	byte ptr [si],80h
	jnz	not_end_fmefc
	cmp	leng[di],0
	jnz	not_end_fmefc
	call	fm_effect_off

not_end_fmefc:
	ret

;==============================================================================
;	演奏開始
;==============================================================================
mstart_f:
	mov	al,[TimerAflag]
	or	al,[TimerBflag]
	jz	mstart
	or	[music_flag],1	;TA/TB処理中は 実行しない
	mov	[ah_push],-1
	ret
mstart:	
;------------------------------------------------------------------------------
;	演奏停止
;------------------------------------------------------------------------------
	pushf
	cli
	and	[music_flag],0feh
	call	mstop
	popf

;------------------------------------------------------------------------------
;	演奏準備
;------------------------------------------------------------------------------
	call	data_init
	call	play_init
	mov	[fadeout_volume],0

if	board2*adpcm
 if	ademu
	mov	ax,1800h
	mov	[adpcm_emulate],al
	call	ppz8_call		;ADPCMEmulate OFF
	mov	bx,offset part10	;PCMを
	or	partmask[bx],10h	;Mask(bit4)
 else
;------------------------------------------------------------------------------
;	NECなYM2608なら PCMパートをMASK
;------------------------------------------------------------------------------
	cmp	[pcm_gs_flag],0
	jz	not_mask_pcm
	mov	bx,offset part10	;PCMを
	or	partmask[bx],4		;Mask(bit2)
not_mask_pcm:
 endif
endif
if	ppz
;------------------------------------------------------------------------------
;	PPZ8初期化
;------------------------------------------------------------------------------
	cmp	[ppz_call_seg],0
	jz	not_init_ppz8
	mov	ax,1901h
	int	ppz_vec		;常駐解除禁止
	xor	ah,ah
	int	ppz_vec
	mov	ah,6
	int	ppz_vec
not_init_ppz8:
endif
;------------------------------------------------------------------------------
;	OPN初期化
;------------------------------------------------------------------------------
	call	opn_init

;------------------------------------------------------------------------------
;	音楽の演奏を開始
;------------------------------------------------------------------------------
	call	setint
	mov	[play_flag],1
	inc	[mstart_flag]
	ret

;==============================================================================
;	各パートのスタートアドレス及び初期値をセット
;==============================================================================
play_init:
	mov	si,[mmlbuf]
	mov	al,-1[si]
	mov	[x68_flg],al

	;２．６追加分
	cmp	byte ptr [si],2*(max_part2+1)
	jz	not_prg

	mov	bx,[si+(2*(max_part2+1))]

	add	bx,si
	mov	[prgdat_adr],bx

	mov	[prg_flg],1
	jmp	prg

not_prg:
	mov	[prg_flg],0

prg:
	mov	cx,max_part2
	xor	dl,dl
	mov	bx,offset part_data_table

din0:	
	mov	di,[bx]	; di = part workarea
	inc	bx
	inc	bx
	lodsw		; ax = part start addr

	add	ax,[mmlbuf]
	xchg	ax,bx
	cmp	byte ptr [bx],80h	;先頭が80hなら演奏しない
	jnz	din1
	xor	bx,bx
din1:
	xchg	ax,bx
	mov	address[di],ax
	mov	leng[di],1		; あと１カウントで演奏開始
	mov	al,-1
	mov	keyoff_flag[di],al	; 現在keyoff中
	mov	mdc[di],al		; MDepth Counter (無限)
	mov	mdc2[di],al		; //
	mov	_mdc[di],al		; //
	mov	_mdc2[di],al		; //
	mov	onkai[di],al		; rest
	mov	onkai_def[di],al	; rest

	cmp	dl,6
	jnc	din_not_fm

;	Part 0,1,2,3,4,5(FM1～6)の時
	mov	volume[di],108		; FM  VOLUME DEFAULT= 108
	mov	fmpan[di],0c0h		; FM PAN = Middle
if	board2
	mov	slotmask[di],0f0h	; FM SLOT MASK
	mov	neiromask[di],0ffh	; FM Neiro MASK
else
	cmp	dl,3
	jnc	din_fm_mask		; OPN 3,4,5 はneiro/slotmaskは0のまま
	mov	slotmask[di],0f0h	; FM SLOT MASK
	mov	neiromask[di],0ffh	; FM Neiro MASK
	jmp	init_exit
din_fm_mask:
	or	partmask[di],20h	; s0の時FMマスク
endif
	jmp	init_exit

din_not_fm:
	cmp	dl,9
	jnc	din_not_psg

;	Part 6,7,8(PSG1～3)の時
	mov	volume[di],8		; PSG VOLUME DEFAULT= 8
	mov	psgpat[di],7		; PSG = TONE
	mov	envf[di],3		; PSG ENV = NONE/normal
	jmp	init_exit

din_not_psg:
	jnz	din_not_pcm
if	board2
 if	adpcm
;	Part 9(OPNA/ADPCM)の時
	mov	volume[di],128		; PCM VOLUME DEFAULT= 128
	mov	fmpan[di],0c0h		; PCM PAN = Middle
 endif
 if	pcm
;	Part 9(OPNA/PCM)の時
	mov	volume[di],128		; PCM VOLUME DEFAULT= 128
	mov	fmpan[di],0
	mov	[pcm86_pan_flag],0	;Mid
	mov	[revpan],0		;逆相off
 endif
endif
	jmp	init_exit
din_not_pcm:

	cmp	dl,10
	jnz	not_rhythm
;	Part 10(Rhythm)の時
	mov	volume[di],15		; PPSDRV volume
	jmp	init_exit
not_rhythm:
init_exit:
	inc	dl
	loop	din0

;------------------------------------------------------------------------------
;	Rhythm のアドレステーブルをセット
;------------------------------------------------------------------------------
	lodsw
	add	ax,[mmlbuf]
	mov	[radtbl],ax
	mov	[rhyadr],offset rhydmy

	ret

;==============================================================================
;	DATA AREA の イニシャライズ
;==============================================================================
data_init:
	xor	al,al
	mov	[fadeout_volume],al
	mov	[fadeout_speed],al
	mov	[fadeout_flag],al

data_init2:
	mov	cx,max_part1
	mov	di,offset part1
di_loop:
	push	cx
	mov	bx,di
	mov	dh,partmask[bx]
	mov	dl,keyon_flag[bx]
	mov	cx,type qq
	pushf
	cli
	xor	al,al
rep	stosb
	and	dh,0fh	;0dh		;一時,s,m,ADE以外の
	mov	partmask[bx],dh		;partmaskのみ保存
	mov	keyon_flag[bx],dl	;keyon_flag保存
	mov	onkai[bx],-1		;onkaiを休符設定
	mov	onkai_def[bx],-1	;onkaiを休符設定
	popf
	pop	cx
	loop	di_loop

	xor	ax,ax
	mov	[tieflag],al
	mov	[status],al
	mov	[status2],al
	mov	[syousetu],ax
	mov	[opncount],al
	mov	[TimerAtime],al
	mov	[lastTimerAtime],al

	mov	di,offset omote_key1
	mov	cx,3
rep	stosw

	mov	[fm3_alg_fb],al
	mov	[af_check],al

	mov	[pcmstart],ax
	mov	[pcmstop],ax
	mov	[pcmrepeat1],ax
	mov	[pcmrepeat2],ax
	mov	[pcmrelease],8000h

	mov	[kshot_dat],ax
	mov	[rshot_dat],al
	mov	[last_shot_data],al

	mov	[slotdetune_flag],al
	mov	di,offset slot_detune1
	mov	cx,4
rep	stosw

	mov	[slot3_flag],al
	mov	[ch3mode],03fh

	mov	[fmsel],al

	mov	[syousetu_lng],96

	mov	ax,[fm1_port1]
	mov	[fm_port1],ax
	mov	ax,[fm1_port2]
	mov	[fm_port2],ax

	mov	al,[_fm_voldown]
	mov	[fm_voldown],al
	mov	al,[_ssg_voldown]
	mov	[ssg_voldown],al
	mov	al,[_pcm_voldown]
	mov	[pcm_voldown],al
if	ppz
	mov	al,[_ppz_voldown]
	mov	[ppz_voldown],al
endif
	mov	al,[_rhythm_voldown]
	mov	[rhythm_voldown],al

	mov	al,[_pcm86_vol]
	mov	[pcm86_vol],al

	ret

;==============================================================================
;	OPN INIT
;==============================================================================
opn_init:
	mov	dx,2983h
	call	opnset44

	mov	[psnoi],0
	cmp	[effon],0
	jnz	no_init_psnoi

	mov	dx,0600h	;PSG Noise
	call	opnset44
	mov	[psnoi_last],0
no_init_psnoi:
;==============================================================================
;	SSG-EG RESET (4.8s)
;==============================================================================
if	board2
	mov	bx,2
	call	sel44
sr01:
endif
	mov	cx,15		;効果音とか気にしない、でいいや…仕様で。
	mov	dx,09000h	;SSG-EG = 0
sr02:	mov	al,cl
	and	al,3
	jz	sr03
	call	opnset
sr03:	inc	dh
	loop	sr02
if	board2
	call	sel46
	dec	bx
	jnz	sr01
	call	sel44
endif
;==============================================================================
;	YM2203ならここでおしまい
;==============================================================================
ife	board2
	cmp	[ongen],0	;2203?
	jnz	init_2608
	ret
;==============================================================================
;	以下YM2608用
;	PAN/HARDLFO DEFAULT
;==============================================================================
init_2608:
endif
if	board2
	mov	bx,2
;;	call	sel44		;mmainには飛ばない状況下なので大丈夫
pd01:
endif
	mov	dx,0b4c0h	;PAN=MID/HARDLFO=OFF
	mov	cx,3
pd00:
	cmp	[fm_effec_flag],0
	jz	pd02
	cmp	cx,1
if	board2
	jnz	pd02
	cmp	bx,1
endif
	jz	pd03		;ここbugってたわ…(4.8s)
pd02:	call	opnset
pd03:	inc	dh
	loop	pd00

if	board2
	call	sel46		;mmainには飛ばない状況下なので大丈夫
	dec	bx
	jnz	pd01
	call	sel44		;mmainには飛ばない状況下なので大丈夫
endif

	mov	dx,02200h	;HARDLFO=OFF
	mov	[port22h],dl
	call	opnset44

if	board2
;==============================================================================
;	Rhythm Default = Pan : Mid , Vol : 15
;==============================================================================
	mov	di,offset rdat
	mov	cx,6
	mov	al,11001111b
rep	stosb
	mov	dx,10ffh
	call	opnset44	;Rhythm All Dump

;==============================================================================
;	リズムトータルレベル　セット
;==============================================================================
rtlset:	
	mov	dl,48
	mov	al,[rhythm_voldown]
	test	al,al
	jz	rtlset2r
	shl	dl,1
	shl	dl,1	; 0-63 > 0-255
	neg	al
	mul	dl
	mov	dl,ah
	shr	dl,1
	shr	dl,1	; 0-255 > 0-63
rtlset2r:
	mov	[rhyvol],dl
	mov	dh,11h

	call	opnset44

;==============================================================================
;	ＰＣＭ　reset & ＬＩＭＩＴ　ＳＥＴ
;==============================================================================
 ife	ademu
	cmp	[pcm_gs_flag],1
	jz	pr_non_pcm
	mov	dx,0cffh
	call	opnset46
	mov	dx,0dffh
	call	opnset46
pr_non_pcm:
 endif
;==============================================================================
;	PPZ Pan Init.
;==============================================================================
 if	ppz+ademu
	mov	dx,5
	mov	ax,1300h
	mov	cx,8
ppz_pan_init_loop:
	mov	al,cl
	dec	al
	call	ppz8_call
	loop	ppz_pan_init_loop
 endif
else
	mov	dx,[fm2_port1]
	pushf
	cli
	rdychk
	mov	al,10h
	out	dx,al
	mov	dx,[fm2_port2]
	_wait
	mov	al,80h
	out	dx,al
	_wait
	mov	al,18h
	out	dx,al
	popf
endif
	ret

;==============================================================================
;	ＭＵＳＩＣ　ＳＴＯＰ
;==============================================================================
mstop_f:
	mov	al,[TimerAflag]
	or	al,[TimerBflag]
	jz	_mstop
	or	[music_flag],2		;TA/TB処理中は 実行しない
	mov	[ah_push],-1
	ret
_mstop:	
	mov	[fadeout_flag],0	;外部からmstopさせた場合は0にする
mstop:	
	pushf
	cli
	and	[music_flag],0fdh
	xor	ax,ax
	mov	[play_flag],al
	mov	[pause_flag],al
	mov	[fadeout_speed],al
	dec	al
	mov	[status2],al
	mov	[fadeout_volume],al
	popf
	jmp	silence

;==============================================================================
;	MUSIC PLAYER MAIN [FROM TIMER-B]
;==============================================================================
mmain:
	mov	[loop_work],3

	cmp	[x68_flg],0
	jnz	mmain_fm

	mov	di,offset part7
	mov	[partb],1
	call	psgmain		;SSG1

	mov	di,offset part8
	mov	[partb],2
	call	psgmain		;SSG2

	mov	di,offset part9
	mov	[partb],3
	call	psgmain		;SSG3

mmain_fm:
if	board2
	call	sel46

	mov	di,offset part4
	mov	[partb],1
	call	fmmain		;FM4 OPNA

	mov	di,offset part5
	mov	[partb],2
	call	fmmain		;FM5 OPNA

	mov	di,offset part6
	mov	[partb],3
	call	fmmain		;FM6 OPNA

	call	sel44
endif
	mov	di,offset part1
	mov	[partb],1
	call	fmmain		;FM1

	mov	di,offset part2
	mov	[partb],2
	call	fmmain		;FM2

	mov	di,offset part3
	mov	[partb],3
	call	fmmain		;FM3

	mov	di,offset part3b
	call	fmmain		;FM3 拡張１

	mov	di,offset part3c
	call	fmmain		;FM3 拡張２

	mov	di,offset part3d
	call	fmmain		;FM3 拡張３

	cmp	[x68_flg],0
	jnz	mmain_exit

	mov	di,offset part11
	call	rhythmmain	;RHYTHM

if	board2
	mov	di,offset part10
	call	pcmmain		;ADPCM/PCM (IN "pcmdrv.asm"/"pcmdrv86.asm")
endif
if	ppz
	mov	di,offset part10a
	mov	[partb],0
	call	ppzmain
	mov	di,offset part10b
	mov	[partb],1
	call	ppzmain
	mov	di,offset part10c
	mov	[partb],2
	call	ppzmain
	mov	di,offset part10d
	mov	[partb],3
	call	ppzmain
	mov	di,offset part10e
	mov	[partb],4
	call	ppzmain
	mov	di,offset part10f
	mov	[partb],5
	call	ppzmain
	mov	di,offset part10g
	mov	[partb],6
	call	ppzmain
	mov	di,offset part10h
	mov	[partb],7
	call	ppzmain
endif

mmain_exit:
	cmp	[loop_work],0
	jnz	mmain_loop
	ret

mmain_loop:
	mov	cx,max_part1
	mov	bx,offset part_data_table
mm_din0:	
	mov	di,[bx]	; di = part workarea
	inc	bx
	inc	bx
	cmp	loopcheck[di],3
	jz	mm_notset
	mov	loopcheck[di],0
mm_notset:
	loop	mm_din0

	cmp	[loop_work],3
	jz	mml_fin

	inc	[status2]
	cmp	[status2],-1	; -1にはさせない
	jnz	mml_ret
	mov	[status2],1
mml_ret:
	ret
mml_fin:
	mov	[status2],-1
	ret

if	board2
;==============================================================================
;	裏ＦＭセレクト
;==============================================================================
sel46:	mov	ax,[fm2_port1]
	mov	[fm_port1],ax
	mov	ax,[fm2_port2]
	mov	[fm_port2],ax
	mov	[fmsel],1
	ret

;==============================================================================
;	表に戻す
;==============================================================================
sel44:	mov	ax,[fm1_port1]
	mov	[fm_port1],ax
	mov	ax,[fm1_port2]
	mov	[fm_port2],ax
	mov	[fmsel],0
	ret
endif

;==============================================================================
;	ＦＭ音源演奏メイン
;==============================================================================
fmmain_ret:
	ret

fmmain:
	mov	si,[di]	; si = PART DATA ADDRESS
	test	si,si
	jz	fmmain_ret
	cmp	partmask[di],0
	jnz	fmmain_nonplay

	; 音長 -1
	dec	leng[di]
	mov	al,leng[di]

	; KEYOFF CHECK & Keyoff
	test	keyoff_flag[di],3	; 既にkeyoffしたか？
	jnz	mp0
	cmp	al,qdat[di]		; Q値 => 残りLength値時 keyoff
	ja	mp0
	call	keyoff			; ALは壊さない
	mov	keyoff_flag[di],-1

mp0:	; LENGTH CHECK
	test	al,al
	jnz	mpexit
mp10:	and	lfoswi[di],0f7h		; Porta off

mp1:	; DATA READ
	lodsb
	cmp	al,80h
	jc	mp2
	jz	mp15

	; ELSE COMMANDS
	call	commands
	jmp	mp1

	; END OF MUSIC [ "L"があった時はそこに戻る ]
mp15:	dec	si
	mov	[di],si
	mov	loopcheck[di],3
	mov	onkai[di],-1
	mov	bx,partloop[di]
	test	bx,bx
	jz	mpexit

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	mp1

mp2:	; F-NUMBER SET
	call	lfoinit
	call	oshift
	call	fnumset

	lodsb
	mov	leng[di],al
	call	calc_q

porta_return:
	cmp	volpush[di],0
	jz	mp_new
	cmp	onkai[di],-1
	jz	mp_new
	dec	[volpush_flag]
	jz	mp_new
	mov	[volpush_flag],0
	mov	volpush[di],0
mp_new:	call	volset
	call	otodasi
	call	keyon
	inc	keyon_flag[di]

	mov	[di],si
	xor	al,al
	mov	[tieflag],al
	mov	[volpush_flag],al
	mov	keyoff_flag[di],al
	cmp	byte ptr [si],0fbh	; '&'が直後にあったらkeyoffしない
	jnz	mnp_ret
	mov	keyoff_flag[di],2
	jmp	mnp_ret

mpexit:	; LFO & Portament & Fadeout 処理 をして終了
if	board2
	cmp	hldelay_c[di],0
	jz	not_hldelay
	dec	hldelay_c[di]
	jnz	not_hldelay
	mov	dh,[partb]
	add	dh,0b4h-1
	mov	dl,fmpan[di]
	call	opnset	
not_hldelay:
endif
	cmp	sdelay_c[di],0
	jz	not_sdelay
	dec	sdelay_c[di]
	jnz	not_sdelay
	test	keyoff_flag[di],1	; 既にkeyoffしたか？
	jnz	not_sdelay
	call	keyon
not_sdelay:
	mov	cl,lfoswi[di]
	test	cl,cl
	jz	nolfosw

	mov	al,cl
	and	al,8
	mov	[lfo_switch],al

	test	cl,3
	jz	not_lfo
	call	lfo
	jnc	not_lfo

	mov	al,cl
	and	al,3
	or	[lfo_switch],al
not_lfo:
	test	cl,30h
	jz	not_lfo2
	pushf
	cli
	call	lfo_change
	call	lfo
	jnc	not_lfo1
	call	lfo_change
	popf
	mov	al,lfoswi[di]
	and	al,30h
	or	[lfo_switch],al
	jmp	not_lfo2
not_lfo1:
	call	lfo_change
	popf
not_lfo2:
	test	[lfo_switch],19h
	jz	vols
	test	[lfo_switch],8
	jz	not_porta
	call	porta_calc
not_porta:
	call	otodasi

vols:
	test	[lfo_switch],22h
	jnz	vol_set
nolfosw:
	cmp	[fadeout_speed],0
	jz	mnp_ret
vol_set:
	call	volset
mnp_ret:
	mov	al,[loop_work]
	and	al,loopcheck[di]
	mov	[loop_work],al
	_ppz
	ret

;==============================================================================
;	Q値の計算
;		break	dx
;==============================================================================
calc_q:
	cmp	byte ptr [si],0c1h	;&&
	jz	cq_sular
	mov	dl,qdata[di]
	cmp	qdatb[di],0
	jz	cq_set
	push	ax
	mov	al,leng[di]
	mul	qdatb[di]
	add	dl,ah
	pop	ax
cq_set:
	cmp	qdat3[di],0
	jz	cq_set2

;	Random-Q
	push	ax
	push	cx
	mov	al,qdat3[di]
	and	al,7fh
	cbw
	inc	ax
	push	dx
	call	rnd
	pop	dx
	test	qdat3[di],80h
	jnz	cqr_minus
	add	dl,al
	jmp	cqr_exit
cqr_minus:
	sub	dl,al
	jnc	cqr_exit
	xor	dl,dl
cqr_exit:
	pop	cx
	pop	ax

cq_set2:cmp	qdat2[di],0
	jz	cq_sete
	mov	dh,leng[di]
	sub	dh,qdat2[di]
	jc	cq_zero
	cmp	dl,dh
	jc	cq_sete
	mov	dl,dh		;最低保証gate値設定
cq_sete:
	mov	qdat[di],dl
	ret
cq_sular:
	inc	si		;スラー命令
cq_zero:mov	qdat[di],0
	ret

;==============================================================================
;	ＦＭ音源演奏メイン：パートマスクされている時
;==============================================================================
fmmain_nonplay:
	mov	keyoff_flag[di],-1
	dec	leng[di]
	jnz	mnp_ret

	test	partmask[di],2		;bit1(FM効果音中？)をcheck
	jz	fmmnp_1
	cmp	[fm_effec_flag],0	;効果音終了したか？
	jnz	fmmnp_1
	and	partmask[di],0fdh	;bit1をclear
	jz	mp10			;partmaskが0なら復活させる

fmmnp_1:
	lodsb
	cmp	al,80h
	jz	fmmnp_2
	jc	fmmnp_3
	call	commands
	jmp	fmmnp_1

fmmnp_2:
	; END OF MUSIC [ "L"があった時はそこに戻る ]
	dec	si
	mov	[di],si
	mov	loopcheck[di],3
	mov	onkai[di],-1
	mov	bx,partloop[di]
	test	bx,bx
	jz	fmmnp_4

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	fmmnp_1

fmmnp_3:
	mov	fnum[di],0	;休符に設定
	mov	onkai[di],-1
	mov	onkai_def[di],-1
	lodsb
	mov	leng[di],al	;音長設定
	inc	keyon_flag[di]
	mov	[di],si

	dec	[volpush_flag]
	jz	fmmnp_4
	mov	volpush[di],0
fmmnp_4:
	mov	[tieflag],0
	mov	[volpush_flag],0
	jmp	mnp_ret

;==============================================================================
;	ＳＳＧ音源　演奏　メイン
;==============================================================================
psgmain_ret:
	ret

psgmain:
	mov	si,[di]		; si = PART DATA ADDRESS
	test	si,si
	jz	psgmain_ret
	cmp	partmask[di],0
	jnz	psgmain_nonplay

	; 音長 -1
	dec	leng[di]
	mov	al,leng[di]

	; KEYOFF CHECK & Keyoff
	test	keyoff_flag[di],3	; 既にkeyoffしたか？
	jnz	mp0p
	cmp	al,qdat[di]		; Q値 => 残りLength値時 keyoff
	ja	mp0p
	call	keyoffp			; ALは壊さない
	mov	keyoff_flag[di],-1

mp0p:	; LENGTH CHECK
	test	al,al
	jnz	mpexitp
	and	lfoswi[di],0f7h		; Porta off

mp1p:	; DATA READ
	lodsb
	cmp	al,80h
	jc	mp2p
	jz	mp15p

	; ELSE COMMANDS
mp1cp:	call	commandsp
	jmp	mp1p

	; END OF MUSIC [ "L"があった時はそこに戻る ]
mp15p:	dec	si
	mov	[di],si
	mov	loopcheck[di],3
	mov	onkai[di],-1
	mov	bx,partloop[di]
	test	bx,bx
	jz	mpexitp

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	mp1p

mp2p:	; TONE SET
	call	lfoinitp
	call	oshiftp
	call	fnumsetp

	lodsb
	mov	leng[di],al
	call	calc_q

porta_returnp:
	cmp	volpush[di],0
	jz	mp_newp
	cmp	onkai[di],-1
	jz	mp_newp
	dec	[volpush_flag]
	jz	mp_newp
	mov	[volpush_flag],0
	mov	volpush[di],0
mp_newp:call	volsetp
	call	otodasip
	call	keyonp
	inc	keyon_flag[di]

	mov	[di],si
	xor	al,al
	mov	[tieflag],al
	mov	[volpush_flag],al
	mov	keyoff_flag[di],al
	cmp	byte ptr [si],0fbh	; '&'が直後にあったらkeyoffしない
	jnz	mnp_ret
	mov	keyoff_flag[di],2
	jmp	mnp_ret

mpexitp:
	mov	cl,lfoswi[di]
	mov	al,cl
	and	al,8
	mov	[lfo_switch],al
	test	cl,cl
	jz	volsp
	test	cl,3
	jz	not_lfop
	call	lfop
	jnc	not_lfop
	mov	al,cl
	and	al,3
	or	[lfo_switch],al
not_lfop:
	test	cl,30h
	jz	not_lfop2
	pushf
	cli
	call	lfo_change
	call	lfop
	jnc	not_lfop1
	call	lfo_change
	popf
	mov	al,lfoswi[di]
	and	al,30h
	or	[lfo_switch],al
	jmp	not_lfop2
not_lfop1:
	call	lfo_change
	popf
not_lfop2:
	test	[lfo_switch],19h
	jz	volsp

	test	[lfo_switch],8
	jz	not_portap
	call	porta_calc
not_portap:
	call	otodasip
volsp:
	call	soft_env
	jc	volsp2
	test	[lfo_switch],22h
	jnz	volsp2
	cmp	[fadeout_speed],0
	jz	mnp_ret
volsp2:	call	volsetp
	jmp	mnp_ret

;==============================================================================
;	ＳＳＧ音源演奏メイン：パートマスクされている時
;==============================================================================
psgmain_nonplay:
	mov	keyoff_flag[di],-1
	dec	leng[di]
	jnz	mnp_ret

	and	lfoswi[di],0f7h		;Porta off
psgmnp_1:
	lodsb
	cmp	al,80h
	jz	psgmnp_2
	jc	psgmnp_4

	cmp	al,0dah			;Portament?
	jnz	psgmnp_3
	call	ssgdrum_check		;の場合だけSSG復活Check
	jc	mp1cp			;復活の場合はメインの処理へ
psgmnp_3:
	call	commandsp
	jmp	psgmnp_1

	; END OF MUSIC [ "L"があった時はそこに戻る ]
psgmnp_2:
	dec	si
	mov	[di],si
	mov	loopcheck[di],3
	mov	onkai[di],-1
	mov	bx,partloop[di]
	test	bx,bx
	jz	fmmnp_4

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	psgmnp_1

psgmnp_4:
	call	ssgdrum_check
	jnc	fmmnp_3
	jmp	mp2p			;SSG復活

;==============================================================================
;	SSGドラムを消してSSGを復活させるかどうかcheck
;		input	AL <- Command
;		output	cy=1 : 復活させる
;==============================================================================
ssgdrum_check:
	test	partmask[di],1		;bit0(SSGマスク中？)をcheck
	jnz	sdrchk_2		;SSGマスク中はドラムを止めない
	test	partmask[di],2		;bit1(SSG効果音中？)をcheck
	jz	sdrchk_2		;SSGドラムは鳴ってない
	cmp	[effon],2		;SSGドラム以外の効果音が鳴っているか？
	jnc	sdrchk_2		;普通の効果音は消さない
	mov	ah,al			;ALは壊さない
	and	ah,0fh			;0DAH(portament)の時は0AHなので大丈夫
	cmp	ah,0fh			;休符？
	jz	sdrchk_2		;休符の時はドラムは止めない
	cmp	[effon],1		;SSGドラムはまだ再生中か？
	jnz	sdrchk_1		;既に消されている
	push	ax
	call	effend			;SSGドラムを消す
	pop	ax
sdrchk_1:
	and	partmask[di],0fdh	;bit1をclear
	jnz	sdrchk_2		;まだ何かでマスクされている
	stc
	ret				;partmaskが0なら復活させる
sdrchk_2:
	clc
	ret

;==============================================================================
;	リズムパート　演奏　メイン
;==============================================================================
rhythmmain_ret:
	ret

rhythmmain:
	mov	si,[di]		; si = PART DATA ADDRESS
	test	si,si
	jz	rhythmmain_ret

	; 音長 -1
	dec	leng[di]
	jnz	mnp_ret

rhyms0:	
	mov	bx,[rhyadr]
rhyms00:
	mov	al,[bx]
	inc	bx
	cmp	al,0ffh
	jz	reom
	test	al,80h
	jnz	rhythmon

	mov	[kshot_dat],0	;rest

rlnset:	mov	al,[bx]
	inc	bx
	mov	[rhyadr],bx
	mov	leng[di],al
	inc	keyon_flag[di]
	jmp	fmmnp_4

reom:	
	lodsb
	cmp	al,080h
	jz	rfin
	jc	re00
	call	commandsr
	jmp	reom

re00:
	mov	[di],si
	xor	ah,ah
	add	ax,ax
	add	ax,[radtbl]
	mov	bx,ax
	mov	ax,[bx]
	add	ax,[mmlbuf]
	mov	[rhyadr],ax
	mov	bx,ax
	jmp	rhyms00

rfin:	dec	si
	mov	[di],si
	mov	loopcheck[di],3
	mov	bx,partloop[di]
	test	bx,bx
	jz	rf00
	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	reom
rf00:
	mov	bx,offset rhydmy
	mov	[rhyadr],bx
	jmp	fmmnp_4

;==============================================================================
;	PSGﾘｽﾞﾑ ON
;==============================================================================
rhythmon:
	test	al,01000000b
	jz	rhy_shot

	xchg	si,bx
	push	bx
	call	commandsr
	pop	bx
	xchg	bx,si
	jmp	rhyms00

rhy_shot:
	cmp	partmask[di],0
	jz	r_nonmask
	mov	[kshot_dat],0
	inc	bx
	jmp	rlnset		;maskされている場合

r_nonmask:
	mov	ah,al
	mov	al,[bx]
	inc	bx
	and	ax,03fffh
	mov	[kshot_dat],ax
	jz	rlnset
	mov	[rhyadr],bx

if	board2
	cmp	[kp_rhythm_flag],0
	jz	rsb210
	push	ax
	mov	bx,offset rhydat
	mov	cx,11
rsb2lp:	ror	ax,1
	jc	rshot
	inc	bx
	inc	bx
rsb200:	inc	bx
	loop	rsb2lp
	pop	ax
endif

rsb210:	mov	bx,ax

	cmp	[fadeout_volume],0
	jz	rpsg
if	board2
	cmp	[kp_rhythm_flag],0
	jz	rpps_check
	mov	dl,[rhyvol]
	call	volset2rf
rpps_check:
endif
	cmp	[ppsdrv_flag],0
	jz	roret		;fadeout時ppsdrvでなら発音しない

rpsg:	mov	al,-1
rolop:	inc	al
	shr	bx,1
	jc	rhygo
	jmp	rolop

rhygo:	push	di
	push	si
	push	bx
	push	ax
	call	effgo
	pop	ax
	pop	bx
	pop	si
	pop	di

	cmp	[ppsdrv_flag],0
	jz	roret
	test	bx,bx
	jz	roret
	jmp	rolop	;PPSDRVなら２音目以上も鳴らしてみる

roret:	mov	bx,[rhyadr]
	jmp	rlnset

if	board2

rshot:	mov	dx,[bx]
	xchg	dh,dl
	inc	bx
	inc	bx
	call	opnset44
	mov	dh,10h
	mov	dl,[bx]
	and	dl,[rhythmmask]
	jz	rsb200
	jns	rshot00
	mov	dl,10000100b
	call	opnset44
	mov	dl,00001000b
	and	dl,[rhythmmask]
	jz	rsb200
	_rwait
rshot00:
	call	opnset44
	jmp	rsb200

endif

;==============================================================================
;	各種特殊コマンド処理
;==============================================================================
commands:
	mov	bx,offset cmdtbl
	jmp	command00

commandsr:
	mov	bx,offset cmdtblr
	jmp	command00

commandsp:
	mov	bx,offset cmdtblp

command00:
	cmp	al,com_end
	jc	out_of_commands
	not	al
	add	al,al
	xor	ah,ah
	add	bx,ax
	mov	ax,cs:[bx]
if	ppz
	push	ax
	_ppz
	pop	ax
endif
	jmp	ax

out_of_commands:
	dec	si
	mov	byte ptr [si],80h	;Part END
	ret

	even
cmdtbl:
	dw	com@		;0FFH
	dw	comq
	dw	comv
	dw	comt
	dw	comtie
	dw	comd
	dw	comstloop
	dw	comedloop
	dw	comexloop
	dw	comlopset
	dw	comshift
	dw	comvolup
	dw	comvoldown
	dw	lfoset
	dw	lfoswitch_f
	dw	jump4		;0F0H
	dw	comy		;0EFH
	dw	jump1
	dw	jump1
	; FOR SB2
	dw	panset
	dw	rhykey
	dw	rhyvs
	dw	rpnset
	dw	rmsvs		;0E8H
	;追加 for V2.0
	dw	comshift2	;0E7H
	dw	rmsvs_sft	;0E6H
	dw	rhyvs_sft	;0E5H
	;
	dw	hlfo_delay	;0E4H
	;追加 for V2.3
	dw	comvolup2	;0E3H
	dw	comvoldown2	;0E2H
	;追加 for V2.4
	dw	hlfo_set	;0E1H
	dw	hlfo_onoff	;0E0H
	;
	dw	syousetu_lng_set	;0DFH
	;
	dw	vol_one_up_fm	;0DEH
	dw	vol_one_down	;0DDH
	;
	dw	status_write	;0DCH
	dw	status_add	;0DBH
	;
	dw	porta		;0DAH
	;
	dw	jump1		;0D9H
	dw	jump1		;0D8H
	dw	jump1		;0D7H
	;
	dw	mdepth_set	;0D6H
	;
	dw	comdd		;0d5h
	;
	dw	ssg_efct_set	;0d4h
	dw	fm_efct_set	;0d3h
	dw	fade_set	;0d2h
	;
	dw	jump1
	dw	jump1		;0d0h
	;
	dw	slotmask_set	;0cfh
	dw	jump6		;0ceh
	dw	jump5		;0cdh
	dw	jump1		;0cch
	dw	lfowave_set	;0cbh
	dw	lfo_extend	;0cah
	dw	jump1		;0c9h
	dw	slotdetune_set	;0c8h
	dw	slotdetune_set2	;0c7h
	dw	fm3_extpartset	;0c6h
	dw	volmask_set	;0c5h
	dw	comq2		;0c4h
	dw	panset_ex	;0c3h
	dw	lfoset_delay	;0c2h
	dw	jump0		;0c1h,sular
	dw	fm_mml_part_mask	;0c0h
	dw	_lfoset		;0bfh
	dw	_lfoswitch_f	;0beh
	dw	_mdepth_set	;0bdh
	dw	_lfowave_set	;0bch
	dw	_lfo_extend	;0bbh
	dw	_volmask_set	;0bah
	dw	_lfoset_delay	;0b9h
	dw	tl_set		;0b8h
	dw	mdepth_count	;0b7h
	dw	fb_set		;0b6h
	dw	slot_delay	;0b5h
	dw	jump16		;0b4h
	dw	comq3		;0b3h
	dw	comshift_master	;0b2h
	dw	comq4		;0b1h

com_end	equ	0b1h

cmdtblp:
	dw	jump1
	dw	comq
	dw	comv
	dw	comt
	dw	comtie
	dw	comd
	dw	comstloop
	dw	comedloop	;0F8H
	dw	comexloop
	dw	comlopset
	dw	comshift
	dw	comvolupp
	dw	comvoldownp
	dw	lfoset
	dw	lfoswitch
	dw	psgenvset	;0F0H
	dw	comy
	dw	psgnoise
	dw	psgsel
	;
	dw	jump1
	dw	rhykey
	dw	rhyvs
	dw	rpnset
	dw	rmsvs		;0E8H
	;
	dw	comshift2
	dw	rmsvs_sft
	dw	rhyvs_sft
	;
	dw	jump1
	;追加 for V2.3
	dw	comvolupp2	;0E3H
	dw	comvoldownp2	;0E2H
	;
	dw	jump1		;0E1H
	dw	jump1		;0E0H
	;
	dw	syousetu_lng_set	;0DFH
	;
	dw	vol_one_up_psg	;0DEH
	dw	vol_one_down	;0DDH
	;
	dw	status_write	;0DCH
	dw	status_add	;0DBH
	;
	dw	portap		;0DAH
	;
	dw	jump1		;0D9H
	dw	jump1		;0D8H
	dw	jump1		;0D7H
	;
	dw	mdepth_set	;0D6H
	;
	dw	comdd		;0d5h
	;
	dw	ssg_efct_set	;0d4h
	dw	fm_efct_set	;0d3h
	dw	fade_set	;0d2h
	;
	dw	jump1
	dw	psgnoise_move	;0d0h
	;
	dw	jump1
	dw	jump6		;0ceh
	dw	extend_psgenvset;0cdh
	dw	detune_extend	;0cch
	dw	lfowave_set	;0cbh
	dw	lfo_extend	;0cah
	dw	envelope_extend	;0c9h
	dw	jump3		;0c8h
	dw	jump3		;0c7h
	dw	jump6		;0c6h
	dw	jump1		;0c5h
	dw	comq2		;0c4h
	dw	jump2		;0c3h
	dw	lfoset_delay	;0c2h
	dw	jump0		;0c1h,sular
	dw	ssg_mml_part_mask	;0c0h
	dw	_lfoset		;0bfh
	dw	_lfoswitch	;0beh
	dw	_mdepth_set	;0bdh
	dw	_lfowave_set	;0bch
	dw	_lfo_extend	;0bbh
	dw	jump1		;0bah
	dw	_lfoset_delay	;0b9h
	dw	jump2
	dw	mdepth_count	;0b7h
	dw	jump1
	dw	jump2
	dw	jump16		;0b4h
	dw	comq3		;0b3h
	dw	comshift_master	;0b2h
	dw	comq4		;0b1h

cmdtblr:
	dw	jump1
	dw	jump1
	dw	comv
	dw	comt
	dw	comtie
	dw	comd
	dw	comstloop
	dw	comedloop
	dw	comexloop
	dw	comlopset
	dw	jump1
	dw	comvolupp
	dw	comvoldownp
	dw	jump4
	dw	pdrswitch
	dw	jump4
	dw	comy
	dw	jump1
	dw	jump1
	;
	dw	jump1
	dw	rhykey
	dw	rhyvs
	dw	rpnset
	dw	rmsvs
	;
	dw	jump1
	dw	rmsvs_sft
	dw	rhyvs_sft
	;
	dw	jump1		;0E4H
	;
	dw	comvolupp2	;0E3H
	dw	comvoldownp2	;0E2H
	;
	dw	jump1		;0E1H
	dw	jump1		;0E0H
	;
	dw	syousetu_lng_set	;0DFH
	;
	dw	vol_one_up_psg	;0DEH
	dw	vol_one_down	;0DDH
	;
	dw	status_write	;0DCH
	dw	status_add	;0DBH
	;
	dw	jump1		;ポルタメント＝通常音程コマンドに
	;
	dw	jump1		;0D9H
	dw	jump1		;0D8H
	dw	jump1		;0D7H
	;
	dw	jump2		;0D6H
	;
	dw	comdd		;0d5h
	;
	dw	ssg_efct_set	;0d4h
	dw	fm_efct_set	;0d3h
	dw	fade_set	;0d2h
	;
	dw	jump1
	dw	jump1		;0d0h
	;
	dw	jump1
	dw	jump6		;0ceh
	dw	jump5		;0cdh
	dw	jump1		;0cch
	dw	jump1
	dw	jump1
	dw	jump1
	dw	jump3
	dw	jump3
	dw	jump6
	dw	jump1		;0c5h
	dw	jump1
	dw	jump2		;0c3h
	dw	jump1
	dw	jump0		;0c1h,sular
	dw	rhythm_mml_part_mask		;0c0h
	dw	jump4		;0bfh
	dw	jump1		;0beh
	dw	jump2		;0bdh
	dw	jump1		;0bch
	dw	jump1		;0bbh
	dw	jump1		;0bah
	dw	jump1		;0b9h
	dw	jump2
	dw	jump1
	dw	jump1
	dw	jump2
	dw	jump16		;0b4h
	dw	jump1
	dw	jump1		;0b2h
	dw	jump1		;0b1h

jump16:
	add	si,10
jump6:
	inc	si
jump5:
	inc	si
jump4:
	inc	si
jump3:
	inc	si
jump2:
	inc	si
jump1:
	inc	si
jump0:
	ret

;==============================================================================
;	0c0hの追加special命令
;==============================================================================
special_0c0h:
	cmp	al,com_end_0c0h
	jc	out_of_commands
	not	al
	add	al,al
	xor	ah,ah
	mov	bx,ax
	mov	ax,cs:comtbl0c0h[bx]
	jmp	ax

comtbl0c0h	dw	vd_fm		;0ffh
		dw	_vd_fm
		dw	vd_ssg
		dw	_vd_ssg
		dw	vd_pcm
		dw	_vd_pcm
		dw	vd_rhythm
		dw	_vd_rhythm	;0f8h
		dw	pmd86_s
		dw	vd_ppz
		dw	_vd_ppz		;0f5h

com_end_0c0h	equ	0f7h

;==============================================================================
;	/s option制御
;==============================================================================
pmd86_s:
	lodsb
	and	al,1
	mov	[pcm86_vol],al
	ret

;==============================================================================
;	各種Voldown
;==============================================================================
vd_fm:	mov	bx,offset fm_voldown
vd_main:
	lodsb
	mov	[bx],al
	ret

vd_ssg:	mov	bx,offset ssg_voldown
	jmp	vd_main

vd_pcm:	mov	bx,offset pcm_voldown
	jmp	vd_main

vd_rhythm:
	mov	bx,offset rhythm_voldown
	jmp	vd_main

vd_ppz:
	mov	bx,offset ppz_voldown
	jmp	vd_main

_vd_fm:	mov	bx,offset fm_voldown
	mov	dx,offset _fm_voldown
_vd_main:
	lodsb
	test	al,al
	jz	_vd_reset
	js	_vd_sign
	add	[bx],al
	jnc	_vd_ret
	mov	byte ptr [bx],255
_vd_ret:
	ret
_vd_sign:
	add	[bx],al
	jc	_vd_ret
	mov	byte ptr [bx],0
	ret

_vd_reset:
	xchg	dx,bx
	mov	al,[bx]
	xchg	dx,bx
	mov	[bx],al
	ret

_vd_ssg:
	mov	bx,offset ssg_voldown
	mov	dx,offset _ssg_voldown
	jmp	_vd_main

_vd_pcm:
	mov	bx,offset pcm_voldown
	mov	dx,offset _pcm_voldown
	jmp	_vd_main

_vd_rhythm:
	mov	bx,offset rhythm_voldown
	mov	dx,offset _rhythm_voldown
	jmp	_vd_main

_vd_ppz:
	mov	bx,offset ppz_voldown
	mov	dx,offset _ppz_voldown
	jmp	_vd_main

;==============================================================================
;	slot keyon delay
;==============================================================================
slot_delay:
	lodsb
	and	al,0fh
	xor	al,0fh
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	mov	sdelay_m[di],al
	lodsb
	mov	sdelay[di],al
	mov	sdelay_c[di],al
	ret

;==============================================================================
;	FB変化
;==============================================================================
fb_set:
	mov	dh,0b0h-1
	add	dh,[partb]		;dh=ALG/FB port address
	lodsb
	test	al,al
	js	_fb_set
fb_set2:		;in	al 00000xxx 設定するFB
	rol	al,1
	rol	al,1
	rol	al,1
fb_set3:		;in	al 00xxx000 設定するFB
	cmp	[partb],3
	jnz	fb_notfm3
if	board2
	cmp	[fmsel],0
	jnz	fb_notfm3
else
	cmp	di,offset part_e
	jz	fb_notfm3
endif
	test	slotmask[di],10h	;slot1を使用していなければ
	jz	fb_ret			;出力しない
	mov	dl,[fm3_alg_fb]
	and	dl,7
	or	dl,al
	mov	[fm3_alg_fb],dl
	jmp	fb_exit

fb_notfm3:
	mov	dl,alg_fb[di]
	and	dl,07h
	or	dl,al
fb_exit:
	call	opnset
	mov	alg_fb[di],dl
fb_ret:	ret

_fb_set:test	al,01000000b
	jnz	_fb_sign
	and	al,7
_fb_sign:
	cmp	[partb],3
	jnz	_fb_notfm3
if	board2
	cmp	[fmsel],0
	jnz	_fb_notfm3
else
	cmp	di,offset part_e
	jz	_fb_notfm3
endif
	mov	dl,[fm3_alg_fb]
	jmp	_fb_next
_fb_notfm3:
	mov	dl,alg_fb[di]
_fb_next:
	ror	dl,1
	ror	dl,1
	ror	dl,1
	and	dl,7
	add	al,dl
	js	_fb_zero
	cmp	al,8
	jc	fb_set2
	mov	al,00111000b
	jmp	fb_set3
_fb_zero:
	xor	al,al
	jmp	fb_set3

;==============================================================================
;	TL変化
;==============================================================================
tl_set:
	mov	dh,40h-1
	add	dh,[partb]		;dh=TL FM Port Address
	lodsb
	mov	ah,al
	and	ah,0fh
	mov	ch,slotmask[di]		;ch=slotmask 43210000
	ror	ch,1
	ror	ch,1
	ror	ch,1
	ror	ch,1
	and	ah,ch			;ah=変化させるslot 00004321
	mov	dl,[si]			;dl=変化値
	inc	si

	mov	bx,offset opnset
	cmp	partmask[di],0		;パートマスクされているか？
	jz	ts_00
	mov	bx,offset dummy_ret

ts_00:	test	al,al
	js	tl_slide

	and	dl,127
	ror	ah,1
	jnc	ts_01
	mov	slot1[di],dl
	call	bx
ts_01:	add	dh,8
	ror	ah,1
	jnc	ts_02
	mov	slot2[di],dl
	call	bx
ts_02:	sub	dh,4
	ror	ah,1
	jnc	ts_03
	mov	slot3[di],dl
	call	bx
ts_03:	add	dh,8
	ror	ah,1
	jnc	ts_04
	mov	slot4[di],dl
	call	bx
dummy_ret:
ts_04:	ret

;	相対変化
tl_slide:
	mov	al,dl

	ror	ah,1
	jnc	tls_01
	mov	dl,slot1[di]
	add	dl,al
	jns	tls_0b
	xor	dl,dl
	test	al,al
	js	tls_0b
	mov	dl,127
tls_0b:	call	bx
	mov	slot1[di],dl

tls_01:	add	dh,8

	ror	ah,1
	jnc	tls_02
	mov	dl,slot2[di]
	add	dl,al
	jns	tls_1b
	xor	dl,dl
	test	al,al
	js	tls_1b
	mov	dl,127
tls_1b:	call	bx
	mov	slot2[di],dl

tls_02:	sub	dh,4

	ror	ah,1
	jnc	tls_03
	mov	dl,slot3[di]
	add	dl,al
	jns	tls_2b
	xor	dl,dl
	test	al,al
	js	tls_2b
	mov	dl,127
tls_2b:	call	bx
	mov	slot3[di],dl

tls_03:	add	dh,8

	ror	ah,1
	jnc	tls_04
	mov	dl,slot4[di]
	add	dl,al
	jns	tls_3b
	xor	dl,dl
	test	al,al
	js	tls_3b
	mov	dl,127
tls_3b:	call	bx
	mov	slot4[di],dl

tls_04:	ret

;==============================================================================
;	演奏中パートのマスクon/off
;==============================================================================
fm_mml_part_mask:
	lodsb
	cmp	al,2
	jnc	special_0c0h
	test	al,al
	jz	fm_mml_part_maskoff
	or	partmask[di],40h
	cmp	partmask[di],40h
	jnz	fmpm_ret
	call	silence_fmpart	;音消去
fmpm_ret:
	pop	ax		;commands
	jmp	fmmnp_1		;パートマスク時の処理に移行

fm_mml_part_maskoff:
	and	partmask[di],0bfh
	jnz	fmpm_ret
	call	neiro_reset	;音色再設定
	pop	ax		;commands
	jmp	mp1		;パート復活

ssg_mml_part_mask:
	lodsb
	cmp	al,2
	jnc	special_0c0h
	test	al,al
	jz	ssg_part_maskoff_ret
	or	partmask[di],40h
	cmp	partmask[di],40h
	jnz	smpm_ret
	call	psgmsk		;AL=07h AH=Maskdata
	mov	dh,7
	mov	dl,al
	or	dl,ah
	call	opnset44	;PSG keyoff
smpm_ret:
	pop	ax		;commandsp
	jmp	psgmnp_1

ssg_part_maskoff_ret:
	and	partmask[di],0bfh
	jnz	smpm_ret
	pop	ax		;commandsp
	jmp	mp1p		;パート復活

rhythm_mml_part_mask:
	lodsb
	cmp	al,2
	jnc	special_0c0h
	test	al,al
	jz	rhythm_part_maskoff_ret
	or	partmask[di],40h
	ret
rhythm_part_maskoff_ret:
	and	partmask[di],0bfh
	ret

;==============================================================================
;	FM音源の音色を再設定
;==============================================================================
neiro_reset:
	cmp	neiromask[di],0
	jz	nr_ret

	mov	dl,voicenum[di]
	mov	bx,word ptr slot1[di]	;bh=s3 bl=s1
	mov	cx,word ptr slot2[di]	;ch=s4 cl=s2
	push	bx
	push	cx
	mov	[af_check],1
	call	neiroset		; 音色復帰
	mov	[af_check],0
	pop	cx
	pop	bx
	mov	word ptr slot1[di],bx
	mov	word ptr slot2[di],cx

	mov	al,carrier[di]
	not	al
	and	al,slotmask[di]		;al<- TLを再設定していいslot 4321xxxx
	jz	nr_exit

	mov	dh,4ch-1
	add	dh,[partb]		;dh=TL FM Port Address

	rol	al,1
	jnc	nr_s3
	mov	dl,ch		;slot 4
	call	opnset
nr_s3:
	sub	dh,8
	rol	al,1
	jnc	nr_s2
	mov	dl,bh		;slot 3
	call	opnset
nr_s2:
	add	dh,4
	rol	al,1
	jnc	nr_s1
	mov	dl,cl		;slot 2
	call	opnset
nr_s1:
	sub	dh,8
	rol	al,1
	jnc	nr_exit
	mov	dl,bl		;slot 1
	call	opnset

nr_exit:
if	board2
	mov	dh,[partb]
	add	dh,0b4h-1
	call	calc_panout
	call	opnset			; パン復帰
endif
nr_ret:
	ret

;==============================================================================
;	PDRのswitch
;==============================================================================
pdrswitch:
	lodsb
	cmp	[ppsdrv_flag],0
	jz	pdrsw_ret
	mov	dl,al
	and	dl,1
	shr	al,1
	mov	ah,5
	int	ppsdrv
pdrsw_ret:
	ret

;==============================================================================
;	音量マスクslotの設定
;==============================================================================
volmask_set:
	lodsb
	and	al,0fh
	jz	vms_zero
	rol	al,1
	rol	al,1
	rol	al,1
	rol	al,1		;上位4BITに移動
	or	al,0fh		;０以外を指定した=下位4BITを１にする
	mov	volmask[di],al
	jmp	ch3_setting

vms_zero:
	mov	al,carrier[di]
	mov	volmask[di],al	;キャリア位置を設定
	jmp	ch3_setting

_volmask_set:
	lodsb
	and	al,0fh
	jz	_vms_zero
	rol	al,1
	rol	al,1
	rol	al,1
	rol	al,1		;上位4BITに移動
	or	al,0fh		;０以外を指定した=下位4BITを１にする
	mov	_volmask[di],al
	jmp	ch3_setting
_vms_zero:
	mov	al,carrier[di]
	mov	_volmask[di],al	;キャリア位置を設定

;==============================================================================
;	パートを判別してch3ならmode設定
;==============================================================================
ch3_setting:
	cmp	[partb],3
	jnz	vms_not_p3
if	board2
	cmp	[fmsel],0
	jnz	vms_not_p3
else
	cmp	di,offset part_e
	jz	vms_not_p3
endif
	call	ch3mode_set	;FM3chの場合のみ ch3modeの変更処理
	stc
	ret

vms_not_p3:
	clc
	ret

;==============================================================================
;	FM3ch 拡張パートセット
;==============================================================================
fm3_extpartset:
	push	di

	lodsw
	test	ax,ax
	jz	fm3ext_part3c
	add	ax,[mmlbuf]
	mov	di,offset part3b
	call	fm3_partinit
fm3ext_part3c:
	lodsw
	test	ax,ax
	jz	fm3ext_part3d
	add	ax,[mmlbuf]
	mov	di,offset part3c
	call	fm3_partinit
fm3ext_part3d:
	lodsw
	test	ax,ax
	jz	fm3ext_exit
	add	ax,[mmlbuf]
	mov	di,offset part3d
	call	fm3_partinit
fm3ext_exit:
	pop	di
	ret

fm3_partinit:
	mov	address[di],ax
	mov	leng[di],1		; ｱﾄ 1ｶｳﾝﾄ ﾃﾞ ｴﾝｿｳ ｶｲｼ
	mov	al,-1
	mov	keyoff_flag[di],al	; 現在keyoff中
	mov	mdc[di],al		; MDepth Counter (無限)
	mov	mdc2[di],al		; //
	mov	_mdc[di],al		; //
	mov	_mdc2[di],al		; //
	mov	onkai[di],al		; rest
	mov	onkai_def[di],al	; rest
	mov	volume[di],108		; FM  VOLUME DEFAULT= 108
	mov	bx,offset part3
	mov	al,fmpan[bx]
	mov	fmpan[di],al		; FM PAN = CH3と同じ
	or	partmask[di],20h	; s0用 partmask
	ret

;==============================================================================
;	Detune Extend Set
;==============================================================================
detune_extend:
	lodsb
	and	al,1
	and	extendmode[di],0feh
	or	extendmode[di],al
	ret

;==============================================================================
;	LFO Extend Set
;==============================================================================
lfo_extend:
	lodsb
	and	al,1
	rol	al,1
	and	extendmode[di],0fdh
	or	extendmode[di],al
	ret

;==============================================================================
;	Envelope Extend Set
;==============================================================================
envelope_extend:
	lodsb
	and	al,1
	rol	al,1
	rol	al,1
	and	extendmode[di],0fbh
	or	extendmode[di],al
	ret

;==============================================================================
;	LFOのWave選択
;==============================================================================
lfowave_set:
	lodsb
	mov	lfo_wave[di],al
	ret

;==============================================================================
;	PSG Envelope set (Extend)
;==============================================================================
extend_psgenvset:
	lodsb
	and	al,1fh
	mov	eenv_ar[di],al
	lodsb
	and	al,1fh
	mov	eenv_dr[di],al
	lodsb
	and	al,1fh
	mov	eenv_sr[di],al
	lodsb
	mov	ah,al
	and	al,0fh
	mov	eenv_rr[di],al
	rol	ah,1
	rol	ah,1
	rol	ah,1
	rol	ah,1
	and	ah,0fh
	xor	ah,0fh
	mov	eenv_sl[di],ah
	lodsb
	and	al,0fh
	mov	eenv_al[di],al

	cmp	envf[di],-1
	jz	not_set_count		;ノーマル＞拡張に移行したか？
	mov	envf[di],-1
	mov	eenv_count[di],4	;RR
	mov	eenv_volume[di],0	;Volume
not_set_count:
	ret

;==============================================================================
;	Slot Detune Set(相対)
;==============================================================================
slotdetune_set2:
	cmp	[partb],3	;ＦＭ3CH目しか指定出来ない
	jnz	jump3
if	board2
	cmp	[fmsel],1	;裏では指定出来ない
	jz	jump3
endif
	lodsb
	mov	bl,al
	lodsw
	ror	bl,1
	jnc	sds2_slot2
	add	[slot_detune1],ax
sds2_slot2:
	ror	bl,1
	jnc	sds2_slot3
	add	[slot_detune2],ax
sds2_slot3:
	ror	bl,1
	jnc	sds2_slot4
	add	[slot_detune3],ax
sds2_slot4:
	ror	bl,1
	jnc	sds_check
	add	[slot_detune4],ax
	jmp	sds_check

;==============================================================================
;	Slot Detune Set
;==============================================================================
slotdetune_set:
	cmp	[partb],3	;ＦＭ3CH目しか指定出来ない
	jnz	jump3
if	board2
	cmp	[fmsel],1	;裏では指定出来ない
	jz	jump3
else
	cmp	di,offset part_e
	jz	jump3
endif
	lodsb
	mov	bl,al
	lodsw
	ror	bl,1
	jnc	sds_slot2
	mov	[slot_detune1],ax
sds_slot2:
	ror	bl,1
	jnc	sds_slot3
	mov	[slot_detune2],ax
sds_slot3:
	ror	bl,1
	jnc	sds_slot4
	mov	[slot_detune3],ax
sds_slot4:
	ror	bl,1
	jnc	sds_check
	mov	[slot_detune4],ax
sds_check:
	mov	ax,[slot_detune1]
	or	ax,[slot_detune2]
	or	ax,[slot_detune3]
	or	ax,[slot_detune4]	;全部０か？
	jz	sdf_set
	mov	al,1
sdf_set:
	mov	[slotdetune_flag],al

;==============================================================================
;	FM3のmodeを設定する
;==============================================================================
ch3mode_set:
	mov	al,1
	cmp	di,offset part3
	jz	cmset_00
	inc	al
	cmp	di,offset part3b
	jz	cmset_00
	mov	al,4
	cmp	di,offset part3c
	jz	cmset_00
	mov	al,8
cmset_00:
	test	slotmask[di],0f0h	;s0
	jz	cm_clear
	cmp	slotmask[di],0f0h
	jnz	cm_set
	test	volmask[di],0fh
	jz	cm_clear
	test	lfoswi[di],1
	jnz	cm_set
cm_noset1:
	test	_volmask[di],0fh
	jz	cm_clear
	test	lfoswi[di],10h
	jnz	cm_set
cm_clear:
	xor	al,0ffh
	and	[slot3_flag],al
	jnz	cm_set2
cm_clear2:
	cmp	[slotdetune_flag],1
	jz	cm_set2
	mov	ah,03fh
	jmp	cm_set_main
cm_set:
	or	[slot3_flag],al
cm_set2:mov	ah,07fh

cm_set_main:
ife	board2
	test	partmask[di],2		;Effect/パートマスクされているか？
	jnz	cm_nowefcplaying
endif
	cmp	ah,[ch3mode]
	jz	cm_exit		;以前と変更無しなら何もしない
	mov	[ch3mode],ah
	mov	dh,27h
	mov	dl,ah
	and	dl,11001111b	;Resetはしない
	call	opnset44

;	効果音モードに移った場合はそれ以前のFM3パートで音程書き換え
	cmp	ah,3fh
	jz	cm_exit
	cmp	di,offset part3
	jz	cm_exit
cm_otodasi:
	push	bp
	mov	bp,di
	push	di
	mov	di,offset part3
	call	otodasi_cm
cm_3bchk:
	cmp	bp,offset part3b
	jz	cm_exit2
	mov	di,offset part3b
	call	otodasi_cm
cm_3cchk:
	cmp	bp,offset part3c
	jz	cm_exit2
	mov	di,offset part3c
	call	otodasi_cm
cm_exit2:
	pop	di
	pop	bp
cm_exit:
	ret

otodasi_cm:
	cmp	partmask[di],0
	jnz	ocm_ret
	call	otodasi
ocm_ret:
	ret

ife	board2
cm_nowefcplaying:
	mov	[ch3mode_push],ah
	ret
endif

;==============================================================================
;	FM slotmask set
;==============================================================================
slotmask_set:
	lodsb
	mov	ah,al
	and	al,0fh
	jz	sm_not_car
	rol	al,1
	rol	al,1
	rol	al,1
	rol	al,1
	mov	carrier[di],al
	jmp	sm_set

sm_not_car:
	cmp	[partb],3
	jnz	sm_notfm3
if	board2
	cmp	[fmsel],0
	jnz	sm_notfm3
else
	cmp	di,offset part_e
	jz	sm_notfm3
endif
	mov	bl,[fm3_alg_fb]
	jmp	sm_car_set

sm_notfm3:
	mov	dl,voicenum[di]
	push	ax
	call	toneadr_calc
	pop	ax
	mov	bl,24[bx]

sm_car_set:
	xor	bh,bh
	and	bl,7
	add	bx,offset carrier_table
	mov	al,[bx]
	mov	carrier[di],al
sm_set:
	and	ah,0f0h
	cmp	slotmask[di],ah
	jz	sm_no_change

	mov	slotmask[di],ah
	test	ah,0f0h
	jnz	sm_noset_pm
	or	partmask[di],20h	;s0の時パートマスク
	jmp	sms_ns
sm_noset_pm:
	and	partmask[di],0dfh	;s0以外の時パートマスク解除
sms_ns:
	call	ch3_setting	;FM3chの場合のみ ch3modeの変更処理
	jnc	sms_nms

;	ch3なら、それ以前のFM3パートでkeyon処理
	cmp	di,offset part3
	jz	sm_exit
	push	bp
	mov	bp,di
	push	di
	mov	di,offset part3
	call	keyon_sm
sm_3bchk:
	cmp	bp,offset part3b
	jz	sm_exit2
	mov	di,offset part3b
	call	keyon_sm
sm_3cchk:
	cmp	bp,offset part3c
	jz	sm_exit2
	mov	di,offset part3c
	call	keyon_sm
sm_exit2:
	pop	di
	pop	bp
sm_exit:

sms_nms:
	xor	ah,ah
	mov	al,slotmask[di]
	rol	al,1	;slot4
	jnc	sms_n4
	or	ah,00010001b
sms_n4:
	rol	al,1	;slot3
	jnc	sms_n3
	or	ah,01000100b
sms_n3:
	rol	al,1	;slot2
	jnc	sms_n2
	or	ah,00100010b
sms_n2:
	rol	al,1	;slot1
	jnc	sms_n1
	or	ah,10001000b
sms_n1:
	mov	neiromask[di],ah

	pop	bx	;commands
	cmp	partmask[di],0
	jz	mp1	;パート復活
	jmp	fmmnp_1

sm_no_change:
	ret

keyon_sm:
	cmp	partmask[di],0
	jnz	ksm_ret
	test	keyoff_flag[di],1	;keyon中か？
	jnz	ksm_ret			;keyoff中
	call	keyon
ksm_ret:
	ret

;==============================================================================
;	ssg effect
;==============================================================================
ssg_efct_set:
	lodsb
	cmp	partmask[di],0
	jnz	ses_ret
	test	al,al
	jz	ses_off
	push	si
	push	di
	call	eff_on2
	pop	di
	pop	si
ses_ret:
	ret
ses_off:
	push	si
	push	di
	call	effoff
	pop	di
	pop	si
	ret

;==============================================================================
;	fm effect
;==============================================================================
fm_efct_set:
	lodsb
	cmp	partmask[di],0
	jnz	ses_ret	;↑
	test	al,al
	jz	fes_off
if	board2
	mov	bh,[fmsel]
endif
	mov	bl,[partb]
	push	bx
	push	si
	push	di
	call	fm_effect_on
	pop	di
	pop	si
	pop	ax
	mov	[partb],al
if	board2
	test	ah,ah
	jz	sel44
	jmp	sel46
else
	ret
endif
fes_off:
if	board2
	mov	bh,[fmsel]
endif
	mov	bl,[partb]
	push	bx
	push	si
	push	di
	call	fm_effect_off
	pop	di
	pop	si
	pop	ax
	mov	[partb],al
if	board2
	test	ah,ah
	jz	sel44
	jmp	sel46
else
	ret
endif
;==============================================================================
;	fadeout
;==============================================================================
fade_set:
	mov	[fadeout_flag],1
	lodsb
	jmp	fout

;==============================================================================
;	LFO depth +- set
;==============================================================================
mdepth_set:
	lodsb
	mov	mdspd[di],al
	mov	mdspd2[di],al
	lodsb
	mov	mdepth[di],al
	ret

mdepth_count:
	lodsb
	or	al,al
	js	mdc_lfo2
	jnz	mdc_no_deca
	dec	al	;255
mdc_no_deca:
	mov	mdc[di],al
	mov	mdc2[di],al
	ret
mdc_lfo2:
	and	al,7fh
	jnz	mdc_no_decb
	dec	al	;255
mdc_no_decb:
	mov	_mdc[di],al
	mov	_mdc2[di],al
	ret

;==============================================================================
;	ポルタメント計算なのね
;==============================================================================
porta_calc:
	mov	ax,porta_num2[di]
	add	porta_num[di],ax
	cmp	porta_num3[di],0
	jz	pc_ret
	js	pc_minus
	dec	porta_num3[di]
	inc	porta_num[di]
	ret
pc_minus:
	inc	porta_num3[di]
	dec	porta_num[di]
pc_ret:
	ret

;==============================================================================
;	ポルタメント(FM)
;==============================================================================
porta:
	cmp	partmask[di],0
	jnz	porta_notset
	lodsb

	call	lfoinit
	call	oshift
	call	fnumset

	mov	ax,fnum[di]
	push	ax
	mov	al,onkai[di]
	push	ax

	lodsb
	call	oshift
	call	fnumset
	mov	bx,fnum[di]	;bx=ポルタメント先のfnum値

	pop	cx
	mov	onkai[di],cl
	pop	cx
	mov	fnum[di],cx	;cx=ポルタメント元のfnum値

	xor	ax,ax
	push	cx
	push	bx
	and	ch,38h
	and	bh,38h
	sub	bh,ch		;先のoctarb - 元のoctarb
	jz	not_octarb
	sar	bh,1
	sar	bh,1
	sar	bh,1
	mov	al,bh
	cbw			;ax=octarb差
	mov	bx,26ah
	imul	bx		;(dx)ax = 26ah * octarb差
not_octarb:
	pop	bx
	pop	cx

	and	cx,7ffh
	and	bx,7ffh
	sub	bx,cx
	add	ax,bx		;ax=26ah*octarb差 + 音程差

	mov	bl,[si]
	inc	si
	mov	leng[di],bl
	call	calc_q

	xor	bh,bh
	cwd
	idiv	bx		;ax=(26ah*ovtarb差 + 音程差) / 音長

	mov	porta_num2[di],ax	;商
	mov	porta_num3[di],dx	;余り
	or	lfoswi[di],8		;Porta ON

	pop	ax	;commands
	jmp	porta_return

porta_notset:
	lodsb	;最初の音程を読み飛ばす	(Mask時)
	ret

;==============================================================================
;	ポルタメント(PSG)
;==============================================================================
portap:
	cmp	partmask[di],0
	jnz	porta_notset

	lodsb
	call	lfoinitp
	call	oshiftp
	call	fnumsetp

	mov	ax,fnum[di]
	push	ax
	mov	al,onkai[di]
	push	ax

	lodsb
	call	oshiftp
	call	fnumsetp
	mov	ax,fnum[di]	; ax = ポルタメント先のpsg_tune値

	pop	bx
	mov	onkai[di],bl
	pop	bx		; bx = ポルタメント元のpsg_tune値
	mov	fnum[di],bx

	sub	ax,bx		; ax = psg_tune差

	mov	bl,[si]
	inc	si
	mov	leng[di],bl
	call	calc_q

	xor	bh,bh
	cwd
	idiv	bx		; ax = psg_tune差 / 音長

	mov	porta_num2[di],ax	;商
	mov	porta_num3[di],dx	;余り
	or	lfoswi[di],8		;Porta ON

	pop	ax	;commandsp
	jmp	porta_returnp

;==============================================================================
;	ＳＴＡＴＵＳに値を出力
;==============================================================================
status_write:
	lodsb
	mov	[status],al
	ret

;==============================================================================
;	ＳＴＡＴＵＳに値を加算
;==============================================================================
status_add:
	lodsb
	mov	bx,offset status
	add	al,[bx]
	mov	[bx],al
	ret

;==============================================================================
;	ボリュームを次の一個だけ変更（Ｖ２．７拡張分）
;==============================================================================
vol_one_up_fm:
	lodsb
	add	al,volume[di]
	cmp	al,128
	jc	vo_vset	
	mov	al,127
vo_vset:inc	al
	mov	volpush[di],al
	mov	[volpush_flag],1
	ret

vol_one_up_psg:
	lodsb
	add	al,volume[di]
	cmp	al,16
	jc	vo_vset
	mov	al,15
	jmp	vo_vset

vol_one_up_pcm:
	lodsb
	add	al,volume[di]
	jc	voup_over
vmax_check:
	cmp	al,255
	jc	vo_vset
voup_over:
	mov	al,254
	jmp	vo_vset

vol_one_down:
	lodsb
	mov	ah,al
	mov	al,volume[di]
	sub	al,ah
	jnc	vmax_check
	xor	al,al
	jmp	vo_vset

;==============================================================================
;	ＦＭ音源ハードＬＦＯの設定（Ｖ２．４拡張分）
;==============================================================================
hlfo_set:
	lodsb

if	board2
	mov	ah,al

	mov	al,fmpan[di]
	and	al,11000000b
	or	al,ah
	mov	fmpan[di],al

	cmp	[partb],3
	jnz	hlfoset_notfm3
	cmp	[fmsel],0
	jnz	hlfoset_notfm3
	;2608の時のみなので part_eはありえない

;	FM3の場合は 4つのパート総て設定
	push	di
	mov	di,offset part3
	mov	fmpan[di],al
	mov	di,offset part3b
	mov	fmpan[di],al
	mov	di,offset part3c
	mov	fmpan[di],al
	mov	di,offset part3d
	mov	fmpan[di],al
	pop	di

hlfoset_notfm3:
	cmp	partmask[di],0		;パートマスクされているか？
	jnz	hlfo_exit

	mov	dh,[partb]
	add	dh,0b4h-1
	call	calc_panout
	call	opnset
endif
hlfo_exit:
	ret

;==============================================================================
;	ＦＭ音源ハードＬＦＯのスイッチ（Ｖ２．４拡張分）
;==============================================================================
hlfo_onoff:
	lodsb
if	board2
	mov	dl,al
	mov	dh,022h
	mov	[port22h],dl
	jmp	opnset44
else
	ret
endif

;==============================================================================
;	ＦＭ音源ハードＬＦＯのディレイ設定
;==============================================================================
hlfo_delay:
	lodsb
if	board2
	mov	hldelay[di],al
endif
	ret

;==============================================================================
;	COMMAND 'Z' （小節の長さの変更）
;==============================================================================
syousetu_lng_set:
	lodsb
	mov	[syousetu_lng],al
	ret

;==============================================================================
;	COMMAND '@' [PROGRAM CHANGE]
;==============================================================================
com@:
	lodsb
	mov	voicenum[di],al
	mov	dl,al
	cmp	partmask[di],0		;パートマスクされているか？
	jnz	com@_mask
	jmp	neiroset

com@_mask:
	call	toneadr_calc
	mov	dl,24[bx]
	mov	alg_fb[di],dl	;alg/fb設定
	add	bx,4
	call	neiroset_tl	;tl設定(NO break dl)

;	FM3chで、マスクされていた場合、fm3_alg_fbを設定
	cmp	[partb],3
	jnz	com@_exit
	cmp	neiromask[di],0
	jz	com@_exit
if	board2
	cmp	[fmsel],0
	jz	com@_afset
else
	cmp	di,offset part_e
	jnz	com@_afset
endif
com@_exit:
	ret

com@_afset:	;in. dl = alg/fb
	test	slotmask[di],10h	;slot1を使用していなければ
	jnz	com@_notslot1
	mov	al,[fm3_alg_fb]
	and	al,00111000b		;fbは前の値を使用
	and	dl,00000111b
	or	dl,al
com@_notslot1:
	mov	[fm3_alg_fb],dl
	mov	alg_fb[di],al
	ret

;==============================================================================
;	COMMAND 'q' [STEP-GATE CHANGE]
;==============================================================================
comq:
	lodsb
	mov	qdata[di],al
	mov	qdat3[di],0
	ret
comq3:
	lodsb
	mov	qdat2[di],al
	ret
comq4:
	lodsb
	mov	qdat3[di],al
	ret

;==============================================================================
;	COMMAND 'Q' [STEP-GATE CHANGE 2]
;==============================================================================
comq2:
	lodsb
	mov	qdatb[di],al
	ret

;==============================================================================
;	COMMAND 'V' [VOLUME CHANGE]
;==============================================================================
comv:	
	lodsb
	mov	volume[di],al
	ret

;==============================================================================
;	COMMAND 't' [TEMPO CHANGE1]
;	COMMAND 'T' [TEMPO CHANGE2]
;	COMMAND 't±' [TEMPO CHANGE 相対1]
;	COMMAND 'T±' [TEMPO CHANGE 相対2]
;==============================================================================
comt:	lodsb
	cmp	al,251
	jnc	comt_sp0
comt_exit1:
	mov	[tempo_d],al	;T (FC)
	mov	[tempo_d_push],al
	jmp	calc_tb_tempo

comt_sp0:
	inc	al
	jnz	comt_sp1

	lodsb			;t (FC FF)
comt_exit2c:		
	cmp	al,18
	jnc	comt_exit2
comt_2c_over:
	mov	al,18
comt_exit2:
	mov	[tempo_48],al
	mov	[tempo_48_push],al
	jmp	calc_tempo_tb

comt_sp1:
	inc	al
	lodsb
	jnz	comt_sp2

	mov	ah,[tempo_d_push]	;T± (FC FE)
	test	al,al
	js	comt_sp1_minus
	add	al,ah
	jnc	comt_sp1_exitc
	mov	al,250
	jmp	comt_exit1
comt_sp1_minus:
	add	al,ah
	jc	comt_sp1_exitc
	xor	al,al
comt_sp1_exitc:
	cmp	al,251
	jc	comt_exit1
	mov	al,250
	jmp	comt_exit1

comt_sp2:
	mov	ah,[tempo_48_push]	;t± (FC FD)
	test	al,al
	js	comt_sp2_minus
	add	al,ah
	jnc	comt_exit2
	mov	al,255
	jmp	comt_exit2
comt_sp2_minus:
	add	al,ah
	jnc	comt_2c_over
	jmp	comt_exit2c

;==============================================================================
;	T->t 変換
;		input	[tempo_d]
;		output	[tempo_48]
;==============================================================================
calc_tb_tempo:
;	TEMPO = 112CH / [ 256 - TB ]	timerB -> tempo
	xor	bl,bl
	sub	bl,[tempo_d]
	mov	al,255
	cmp	bl,18
	jc	ctbt_exit
	mov	ax,112ch
	div	bl
	test	ah,ah
	jns	ctbt_exit
	inc	al		;四捨五入
ctbt_exit:
	mov	[tempo_48],al
	mov	[tempo_48_push],al
	ret

;==============================================================================
;	t->T 変換
;		input	[tempo_48]
;		output	[tempo_d]
;==============================================================================
calc_tempo_tb:
;	TB = 256 - [ 112CH / TEMPO ]	tempo -> timerB
	mov	bl,[tempo_48]
	xor	al,al
	cmp	bl,18
	jc	cttb_exit
	mov	ax,112ch
	div	bl
	xor	dl,dl
	sub	dl,al
	mov	al,dl
	test	ah,ah
	jns	cttb_exit
	dec	al	;四捨五入
cttb_exit:
	mov	[tempo_d],al
	mov	[tempo_d_push],al
	ret

;==============================================================================
;	COMMAND '&' [タイ]
;==============================================================================
comtie:
	or	[tieflag],1
	ret

;==============================================================================
;	COMMAND 'D' [ﾃﾞﾁｭｰﾝ]
;==============================================================================
comd:	lodsw
	mov	detune[di],ax
	ret

;==============================================================================
;	COMMAND 'DD' [相対ﾃﾞﾁｭｰﾝ]
;==============================================================================
comdd:	lodsw
	add	detune[di],ax
	ret

;==============================================================================
;	COMMAND '[' [ﾙｰﾌﾟ ｽﾀｰﾄ]
;==============================================================================
comstloop:
	lodsw
	mov	bx,ax
	mov	ax,[mmlbuf]
	cmp	di,offset part_e
	jnz	comst_nonefc
	mov	ax,[efcdat]
comst_nonefc:
	add	bx,ax
	inc	bx
	mov	byte ptr [bx],0
	ret	

;==============================================================================
;	COMMAND	']' [ﾙｰﾌﾟ ｴﾝﾄﾞ]
;==============================================================================
comedloop:
	lodsb
	test	al,al
	jz	muloop	; 0 ﾅﾗ ﾑｼﾞｮｳｹﾝ ﾙｰﾌﾟ
	mov	ah,al
	inc	byte ptr [si]
	lodsb
	cmp	ah,al
	jnz	reloop
	inc	si
	inc	si
	ret
muloop:	inc	si
	mov	loopcheck[di],1
reloop:	lodsw
	inc	ax
	inc	ax
	mov	bx,[mmlbuf]
	cmp	di,offset part_e
	jnz	comed_nonefc
	mov	bx,[efcdat]
comed_nonefc:
	add	ax,bx
	mov	si,ax
	ret		

;==============================================================================
;	COMMAND	':' [ﾙｰﾌﾟ ﾀﾞｯｼｭﾂ]
;==============================================================================
comexloop:
	lodsw
	mov	bx,ax
	mov	ax,[mmlbuf]
	cmp	di,offset part_e
	jnz	comex_nonefc
	mov	ax,[efcdat]
comex_nonefc:
	add	bx,ax
	mov	dl,[bx]
	dec	dl
	inc	bx
	cmp	dl,[bx]
	jz	loopexit
	ret
loopexit:
	add	bx,3
	mov	si,bx
	ret

;==============================================================================
;	COMMAND 'L' [ｸﾘｶｴｼ ﾙｰﾌﾟ ｾｯﾄ]
;==============================================================================
comlopset:
	mov	partloop[di],si
	ret

;==============================================================================
;	COMMAND '_' [ｵﾝｶｲ ｼﾌﾄ]
;==============================================================================
comshift:	
	lodsb
	mov	shift[di],al
	ret

;==============================================================================
;	COMMAND '__' [相対転調]
;==============================================================================
comshift2:
	lodsb
	add	al,shift[di]
	mov	shift[di],al
	ret

;==============================================================================
;	COMMAND '_M' [Master転調値]
;==============================================================================
comshift_master:
	lodsb
	mov	shift_def[di],al
	ret

;==============================================================================
;	COMMAND ')' [VOLUME UP]
;==============================================================================
	;	ＦＯＲ　ＦＭ
comvolup:
	mov	al,volume[di]
	add	al,4
volupck:
	cmp	al,128
	jc	vset
	mov	al,127
vset:	mov	volume[di],al
	ret

	;数字付き
comvolup2:
	lodsb
	add	al,volume[di]
	jmp	volupck

	;	ＦＯＲ　ＰＳＧ
comvolupp:
	mov	al,volume[di]	
	inc	al
volupckp:
	cmp	al,16
	jc	vset
	mov	al,15
	jmp	vset

	;数字付き
comvolupp2:
	lodsb
	add	al,volume[di]
	jmp	volupckp

;==============================================================================
;	COMMAND '(' [VOLUME DOWN]
;==============================================================================
	;	ＦＯＲ　ＦＭ
comvoldown:
	mov	al,volume[di]
	sub	al,4
	jnc	vset
	xor	al,al
	jmp	vset

	;数字付き
comvoldown2:
	lodsb
	mov	ah,al
	mov	al,volume[di]
	sub	al,ah
	jnc	vset
	xor	al,al
	jmp	vset

	;	ＦＯＲ　ＰＳＧ
comvoldownp:
	mov	al,volume[di]
	test	al,al
	jz	vset
	dec	al
	jmp	vset

	;数字付き
comvoldownp2:
	lodsb
	mov	ah,al
	mov	al,volume[di]
	sub	al,ah
	jnc	vset
	xor	al,al
	jmp	vset

;==============================================================================
;	ＬＦＯ２用処理
;==============================================================================
_lfoset:
	mov	ax,offset lfoset
_lfo_main:
	pushf
	cli
	push	ax
	call	lfo_change
	pop	ax
	call	ax
	call	lfo_change
	popf
	ret

_mdepth_set:
	mov	ax,offset mdepth_set
	jmp	_lfo_main

_lfowave_set:
	mov	ax,offset lfowave_set
	jmp	_lfo_main

_lfo_extend:
	mov	ax,offset lfo_extend
	jmp	_lfo_main

_lfoset_delay:
	mov	ax,offset lfoset_delay
	jmp	_lfo_main

_lfoswitch:
	lodsb
	and	al,7
	rol	al,1
	rol	al,1
	rol	al,1
	rol	al,1
	and	lfoswi[di],08fh
	or	lfoswi[di],al
	call	lfo_change
	call	lfoinit_main
	jmp	lfo_change

_lfoswitch_f:
	call	_lfoswitch
	jmp	ch3_setting

;==============================================================================
;	LFO1<->LFO2 change
;==============================================================================
lfo_change:
	mov	ax,lfodat[di]
	xchg	ax,_lfodat[di]
	mov	lfodat[di],ax

	mov	cl,4
	rol	lfoswi[di],cl
	rol	extendmode[di],cl

	mov	ax,word ptr delay[di]
	xchg	ax,word ptr _delay[di]
	mov	word ptr delay[di],ax

	mov	ax,word ptr step[di]
	xchg	ax,word ptr _step[di]
	mov	word ptr step[di],ax

	mov	ax,word ptr delay2[di]
	xchg	ax,word ptr _delay2[di]
	mov	word ptr delay2[di],ax

	mov	ax,word ptr step2[di]
	xchg	ax,word ptr _step2[di]
	mov	word ptr step2[di],ax

	mov	ax,word ptr mdepth[di]
	xchg	ax,word ptr _mdepth[di]
	mov	word ptr mdepth[di],ax

	mov	al,mdspd2[di]
	mov	ah,lfo_wave[di]
	xchg	ax,word ptr _mdspd2[di]
	mov	mdspd2[di],al
	mov	lfo_wave[di],ah

	mov	ax,word ptr mdc[di]
	xchg	ax,word ptr _mdc[di]
	mov	word ptr mdc[di],ax
	
	ret

;==============================================================================
;	LFO ﾊﾟﾗﾒｰﾀ ｾｯﾄ
;==============================================================================
lfoset:	lodsb
	mov	delay[di],al
	mov	delay2[di],al
	lodsb
	mov	speed[di],al
	mov	speed2[di],al
	lodsb
	mov	step[di],al
	mov	step2[di],al
	lodsb
	mov	time[di],al
	mov	time2[di],al
	jmp	lfoinit_main

lfoset_delay:
	lodsb
	mov	delay[di],al
	mov	delay2[di],al
	jmp	lfoinit_main

;==============================================================================
;	LFO SWITCH
;==============================================================================
lfoswitch:
	lodsb
	test	al,11111000b
	jz	ls_00
	mov	al,1
ls_00:
	and	al,7
	and	lfoswi[di],0f8h
	or	lfoswi[di],al
	jmp	lfoinit_main

lfoswitch_f:
	call	lfoswitch
	jmp	ch3_setting

;==============================================================================
;	PSG ENVELOPE SET
;==============================================================================
psgenvset:
	lodsb
	mov	pat[di],al
	mov	patb[di],al
	lodsb
	mov	pv2[di],al
	lodsb
	mov	pr1[di],al
	mov	pr1b[di],al
	lodsb
	mov	pr2[di],al
	mov	pr2b[di],al
	cmp	envf[di],-1
	jnz	not_set_count2		;拡張＞ノーマルに移行したか？
	mov	envf[di],2	;RR
	mov	penv[di],-15	;Volume
not_set_count2:
	ret

;==============================================================================
;	'y' COMMAND [ｺｲﾂｶﾞ ｲﾁﾊﾞﾝ ｶﾝﾀﾝ]
;==============================================================================
comy:
	lodsw
	mov	dh,al
	mov	dl,ah
	jmp	opnset

;==============================================================================
;	'w' COMMAND [PSG NOISE ﾍｲｷﾝ ｼｭｳﾊｽｳ]
;==============================================================================
psgnoise:
	lodsb
	mov	[psnoi],al
	ret
psgnoise_move:
	lodsb
	add	al,[psnoi]
	test	al,al
	jns	pnm_nminus
	xor	al,al
pnm_nminus:
	cmp	al,32
	jc	pnm_set
	mov	al,31
pnm_set:
	mov	[psnoi],al
	ret

;==============================================================================
;	'P' COMMAND [PSG TONE/NOISE/MIX SET]
;==============================================================================
psgsel:
	lodsb
	mov	psgpat[di],al
	ret

;==============================================================================
;	'p' COMMAND [FM PANNING SET]
;==============================================================================
panset:
	lodsb
if	board2
panset_main:
	ror	al,1
	ror	al,1
	and	al,11000000b
	mov	ah,al	;ah <- pan data
	mov	al,fmpan[di]
	and	al,00111111b
	or	al,ah
	mov	fmpan[di],al

	cmp	[partb],3
	jnz	panset_notfm3
	cmp	[fmsel],0
	jnz	panset_notfm3

;	FM3の場合は 4つのパート総て設定
	push	di
	mov	di,offset part3
	mov	fmpan[di],al
	mov	di,offset part3b
	mov	fmpan[di],al
	mov	di,offset part3c
	mov	fmpan[di],al
	mov	di,offset part3d
	mov	fmpan[di],al
	pop	di

panset_notfm3:
	cmp	partmask[di],0		;パートマスクされているか？
	jnz	panset_exit

	mov	dl,al
	mov	dh,[partb]
	add	dh,0b4h-1
	call	calc_panout
	call	opnset
endif
panset_exit:
	ret

if	board2
;==============================================================================
;	0b4h～に設定するデータを取得 out.dl
;==============================================================================
calc_panout:
	mov	dl,fmpan[di]
	cmp	hldelay_c[di],0
	jz	cpo_ret
	and	dl,0c0h		;HLFO Delayが残ってる場合はパンのみ設定
cpo_ret:
	ret
endif
;==============================================================================
;	Pan setting Extend
;==============================================================================
panset_ex:
	lodsb
	inc	si	;逆走flagは読み飛ばす
if	board2
	test	al,al
	jz	pex_mid
	js	pex_left
	mov	al,2
	jmp	panset_main
pex_mid:
	mov	al,3
	jmp	panset_main
pex_left:
	mov	al,1
	jmp	panset_main
else
	ret
endif

;==============================================================================
;	"\?" COMMAND [ OPNA Rhythm Keyon/Dump ]
;==============================================================================
rhykey:
if	board2
	mov	dh,10h
	lodsb
	and	al,[rhythmmask]
	jz	rhst_ret
	mov	dl,al

	cmp	[fadeout_volume],0
	jz	rk_00
	push	dx
	mov	dl,[rhyvol]
	call	volset2rf
	pop	dx
rk_00:
	test	dl,dl
	js	rhyset

	mov	al,dl
	mov	bx,offset rdat
	push	dx
	mov	cx,6
	mov	dh,18h
rklp:	ror	al,1
	jnc	rk00
	mov	dl,[bx]
	call	opnset44
rk00:	inc	bx
	inc	dh
	loop	rklp
	pop	dx

rhyset:
	call	opnset44
	test	dl,dl
	jns	rhst_00
	mov	bx,offset rdump_bd
	call	rflag_inc
	not	dl
	and	[rshot_dat],dl
	jmp	rhst_ret2
rhst_00:
	mov	bx,offset rshot_bd
	call	rflag_inc
	or	[rshot_dat],dl
rhst_ret2:
	cmp	byte ptr [si],0ebh
	jnz	rhst_ret
	_rwait
rhst_ret:
	ret
rflag_inc:
	mov	al,dl
	mov	cx,6
ri_loop:
	ror	al,1
	jnc	ri_not
	inc	byte ptr [bx]
ri_not:	inc	bx
	loop	ri_loop
	ret

else
	inc	si
	ret
endif

;==============================================================================
;	"\v?n" COMMAND
;==============================================================================
rhyvs:
if	board2
	lodsb

	mov	cl,0c0h

	mov	dl,1fh
	and	dl,al
rs002:
	rol	al,1
	rol	al,1
	rol	al,1
	and	al,07h
	mov	bx,offset rdat-1
	mov	dh,al

	xor	ah,ah
	add	bx,ax

	mov	al,18h-1
	add	al,dh
	mov	dh,al
	mov	al,[bx]
	and	al,cl
	or	dl,al
	mov	[bx],dl
	jmp	opnset44

else
	inc	si
	ret
endif

rhyvs_sft:
if	board2
	lodsb
	mov	bx,offset rdat-1
	mov	dh,al

	xor	ah,ah
	add	bx,ax

	add	dh,18h-1
	mov	al,[bx]
	and	al,00011111b
	mov	dl,al
	lodsb
	add	al,dl
	cmp	al,32
	jc	rvss00
	test	al,80h
	jnz	rvss01

	mov	al,31
	jmp	rvss00
rvss01:	xor	al,al
rvss00:	and	al,00011111b
	mov	dl,al
	mov	al,[bx]
	and	al,11100000b
	or	dl,al
	mov	[bx],dl
	jmp	opnset44
else
	inc	si
	inc	si
	ret
endif

;==============================================================================
;	"\p?" COMMAND
;==============================================================================
rpnset:
if	board2

	lodsb
	mov	ah,al
	mov	cl,1fh
	and	ah,3
	ror	ah,1
	ror	ah,1
	mov	dl,ah
	jmp	rs002
else
	inc	si
	ret
endif

;==============================================================================
;	"\Vn" COMMAND
;==============================================================================
rmsvs:
if	board2
	lodsb

	mov	dl,al
	mov	al,[rhythm_voldown]
	test	al,al
	jz	volset2r
	neg	al
	mul	dl
	mov	dl,ah
volset2r:
	mov	[rhyvol],dl

volset2rf:
	mov	dh,11h
	mov	al,[fadeout_volume]
	test	al,al
	jz	vs2r_000
	neg	al
	mul	dl
	mov	dl,ah
vs2r_000:
	jmp	opnset44
else
	inc	si
	ret
endif

rmsvs_sft:
if	board2
	mov	dh,11h
	lodsb
	mov	dl,al
	mov	al,[rhyvol]
	add	al,dl
	cmp	al,64
	jc	rmss00
	test	al,80h
	jnz	rmss01
	mov	al,63
	jmp	rmss00
rmss01:	xor	al,al
rmss00:	mov	dl,al
	jmp	volset2r
else
	inc	si
	ret
endif

;==============================================================================
;	SHIFT[di] 分移調する
;==============================================================================
oshift:
oshiftp:
	cmp	al,0fh	;休符
	jz	osret
	mov	dl,shift[di]
	add	dl,shift_def[di]
	test	dl,dl
	jz	osret
	
	mov	bl,al
	and	bl,0fh
	and	al,0f0h
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	mov	bh,al	;bh=OCT bl=ONKAI

	test	dl,80h
	jz	shiftplus
	;
	; - ﾎｳｺｳ ｼﾌﾄ
	;
shiftminus:
	add	bl,dl
	jc	sfm2
sfm1:	dec	bh
	add	bl,12
	jnc	sfm1
sfm2:	mov	al,bh
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	or	al,bl
	ret
	;
	; + ﾎｳｺｳ ｼﾌﾄ
	;
shiftplus:
	add	bl,dl
spm1:	cmp	bl,0ch
	jc	spm2
	inc	bh
	sub	bl,12
	jmp	spm1
spm2:	mov	al,bh
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	or	al,bl
osret:	ret

;==============================================================================
;	ＦＭ　BLOCK,F-NUMBER SET
;		INPUTS	-- AL [KEY#,0-7F]
;==============================================================================
fnumset:
	mov	ah,al
	and	ah,0fh
	cmp	ah,0fh
	jz	fnrest	; 休符の場合
	mov	onkai[di],al

	;
	; BLOCK/FNUM CALICULATE
	;
	mov	ch,al
	ror	ch,1
	and	ch,38h	; ch=BLOCK

	mov	bl,al
	and	bl,0fh	; bl=ONKAI

	mov	bh,0
	add	bx,bx
	mov	ax,fnum_data[bx]
	;
	; BLOCK SET
	;
	or	ah,ch
	mov	fnum[di],ax
	ret
fnrest:	
	mov	onkai[di],-1
	test	lfoswi[di],11h
	jnz	fnr_ret
	mov	fnum[di],0	;音程LFO未使用
fnr_ret:
	ret
	;
	; PSG TUNE SET
	;
fnumsetp:
	mov	ah,al
	and	ah,0fh
	cmp	ah,0fh
	jz	fnrest	; ｷｭｳﾌ ﾅﾗ FNUM ﾆ 0 ｦ ｾｯﾄ
	mov	onkai[di],al

	mov	cl,al
	ror	cl,1
	ror	cl,1
	ror	cl,1
	ror	cl,1
	and	cl,0fh	;cl=oct

	mov	bl,al
	and	bl,0fh
	mov	bh,0	;bx=onkai

	add	bx,bx
	mov	ax,psg_tune_data[bx]

	shr	ax,cl
	jnc	pt_non_inc
	inc	ax
pt_non_inc:

	mov	fnum[di],ax

	ret

;==============================================================================
;	Set [ FNUM/BLOCK + DETUNE + LFO ]
;==============================================================================
otodasi:
	mov	ax,fnum[di]
	test	ax,ax
	jnz	od_00
	ret
od_00:
	cmp	slotmask[di],0
	jz	od_exit
	mov	cx,ax
	and	cx,3800h	; cx=BLOCK
	and	ah,7		; ax=FNUM

	;
	; Portament/LFO/Detune SET
	;
	add	ax,porta_num[di]
	add	ax,detune[di]

	mov	dh,[partb]
	cmp	dh,3		;Ch 3
	jnz	od_non_ch3
if	board2
	cmp	[fmsel],0
	jnz	od_non_ch3
else
	cmp	di,offset part_e
	jz	od_non_ch3
endif
	cmp	[ch3mode],3fh
	jnz	ch3_special

od_non_ch3:
	test	lfoswi[di],1
	jz	od_not_lfo1
	add	ax,lfodat[di]
od_not_lfo1:
	test	lfoswi[di],10h
	jz	od_not_lfo2
	add	ax,_lfodat[di]
od_not_lfo2:
	call	fm_block_calc

	;
	; SET BLOCK/FNUM TO OPN
	;	input CX:AX

	or	ax,cx	;AX=block/Fnum
	add	dh,0a4h-1
	mov	dl,ah
	pushf
	cli
	call	opnset
	sub	dh,4
	mov	dl,al
	call	opnset
	popf
od_exit:
	ret

;==============================================================================
;	ch3=効果音モード を使用する場合の音程設定
;			input CX:block AX:fnum
;==============================================================================
ch3_special:
	push	si
	mov	si,cx		;si=block

	mov	bl,slotmask[di]	;bl=slot mask 4321xxxx
	mov	cl,lfoswi[di]	;cl=lfoswitch
	mov	bh,volmask[di]	;bh=lfo1 mask 4321xxxx
	test	bh,0fh
	jnz	c3s_00
	mov	bh,0f0h		;all
c3s_00:	mov	ch,_volmask[di]	;ch=lfo2 mask 4321xxxx
	test	ch,0fh
	jnz	ns_sl4
	mov	ch,0f0h		;all

;	slot	4
ns_sl4:	rol	bl,1
	jnc	ns_sl3
	push	ax
	add	ax,[slot_detune4]
	rol	bh,1
	jnc	ns_sl4b
	test	cl,1
	jz	ns_sl4b
	add	ax,lfodat[di]
ns_sl4b:
	rol	ch,1
	jnc	ns_sl4c
	test	cl,10h
	jz	ns_sl4c
	add	ax,_lfodat[di]
ns_sl4c:
	push	cx
	mov	cx,si
	call	fm_block_calc
	or	ax,cx
	pop	cx
	mov	dh,0a6h
	mov	dl,ah
	pushf
	cli
	call	opnset
	mov	dh,0a2h
	mov	dl,al
	call	opnset
	popf
	pop	ax

;	slot	3
ns_sl3:	rol	bl,1
	jnc	ns_sl2
	push	ax
	add	ax,[slot_detune3]
	rol	bh,1
	jnc	ns_sl3b
	test	cl,1
	jz	ns_sl3b
	add	ax,lfodat[di]
ns_sl3b:
	rol	ch,1
	jnc	ns_sl3c
	test	cl,10h
	jz	ns_sl3c
	add	ax,_lfodat[di]
ns_sl3c:
	push	cx
	mov	cx,si
	call	fm_block_calc
	or	ax,cx
	pop	cx
	mov	dh,0ach
	mov	dl,ah
	pushf
	cli
	call	opnset
	mov	dh,0a8h
	mov	dl,al
	call	opnset
	popf
	pop	ax

;	slot	2
ns_sl2:	rol	bl,1
	jnc	ns_sl1
	push	ax
	add	ax,[slot_detune2]
	rol	bh,1
	jnc	ns_sl2b
	test	cl,1
	jz	ns_sl2b
	add	ax,lfodat[di]
ns_sl2b:
	rol	ch,1
	jnc	ns_sl2c
	test	cl,10h
	jz	ns_sl2c
	add	ax,_lfodat[di]
ns_sl2c:
	push	cx
	mov	cx,si
	call	fm_block_calc
	or	ax,cx
	pop	cx
	mov	dh,0aeh
	mov	dl,ah
	pushf
	cli
	call	opnset
	mov	dh,0aah
	mov	dl,al
	call	opnset
	popf
	pop	ax

;	slot	1
ns_sl1:	rol	bl,1
	jnc	ns_exit
	add	ax,[slot_detune1]
	rol	bh,1
	jnc	ns_sl1b
	test	cl,1
	jz	ns_sl1b
	add	ax,lfodat[di]
ns_sl1b:
	rol	ch,1
	jnc	ns_sl1c
	test	cl,10h
	jz	ns_sl1c
	add	ax,_lfodat[di]
ns_sl1c:
	mov	cx,si
	call	fm_block_calc
	or	ax,cx
	mov	dh,0adh
	mov	dl,ah
	pushf
	cli
	call	opnset
	mov	dh,0a9h
	mov	dl,al
	call	opnset
	popf
ns_exit:
	pop	si
	ret

;==============================================================================
;	FM音源のdetuneでオクターブが変わる時の修正
;		input	CX:block / AX:fnum+detune
;		output	CX:block / AX:fnum
;==============================================================================
fm_block_calc:
	test	ax,ax
od0:	js	od1
	cmp	ax,26ah
	jc	od1
	;
	cmp	ax,26ah*2	;04d2h
	jc	od2
	;
	add	cx,0800h	;oct.up
	cmp	cx,4000h
	jz	od05
	sub	ax,26ah		;4d2h-26ah
	jmp	od0
od05:	; ﾓｳ ｺﾚｲｼﾞｮｳ ｱｶﾞﾝﾅｲﾖﾝ
	mov	cx,3800h
	cmp	ax,800h
	jc	od_ret
	mov	ax,7ffh		;04d2h
od_ret:	ret
	;
od1:	
	sub	cx,0800h	;oct.down
	jc	od15
	add	ax,26ah		;4d2h-26ah
	jmp	od0
od15:	; ﾓｳ ｺﾚｲｼﾞｮｳ ｻｶﾞﾝﾅｲﾖﾝ
	xor	cx,cx
	test	ax,ax
	js	od16
	cmp	ax,8	;4
	jnc	od2
od16:	mov	ax,8	;4
	;
od2:	ret

;==============================================================================
;	ＰＳＧ　音程設定
;==============================================================================
otodasip:
	mov	ax,fnum[di]
	test	ax,ax
	jnz	od_00p
	ret

od_00p:
	;
	; PSG Portament set
	;
	add	ax,porta_num[di]

	;
	; PSG Detune/LFO set
	;
	test	extendmode[di],1
	jnz	od_ext_detune

	sub	ax,detune[di]
	test	lfoswi[di],1
	jz	od_notlfo1
	sub	ax,lfodat[di]
od_notlfo1:
	test	lfoswi[di],10h
	jz	tonesetp
	sub	ax,_lfodat[di]
	jmp	tonesetp

od_ext_detune:	;拡張DETUNE(DETUNE)の計算
	push	ax
	mov	bx,detune[di]
	test	bx,bx
	jz	od_ext_lfo	;LFOへ
	imul	bx
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	test	dx,dx
	js	extdet_minus
	inc	dx
	jmp	extdet_set
extdet_minus:
	dec	dx
extdet_set:
	pop	ax
	sub	ax,dx	; Detuneをずらす
	push	ax

od_ext_lfo:	;拡張DETUNE(LFO)の計算
	xor	dx,dx
	test	lfoswi[di],11h
	jz	extlfo_set
	xor	dx,dx
	test	lfoswi[di],1
	jz	od_ext_notlfo1
	mov	dx,lfodat[di]
od_ext_notlfo1:
	test	lfoswi[di],10h
	jz	od_ext_notlfo2
	add	dx,_lfodat[di]
od_ext_notlfo2:
	test	dx,dx
	jz	extlfo_set
	imul	dx
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	test	dx,dx
	js	extlfo_minus
	inc	dx
	jmp	extlfo_set
extlfo_minus:
	dec	dx
extlfo_set:
	pop	ax
	sub	ax,dx	;LFOをずらす
	;
	; TONE SET
	;
tonesetp:
if	1			;突撃mixでは0
	cmp	ax,1000h
	jc	tsp_01
	test	ax,ax
	js	tsp_00
	mov	ax,0fffh
	jmp	tsp_01
tsp_00:	xor	ax,ax
endif
tsp_01:	mov	dh,[partb]
	dec	dh
	add	dh,dh
	mov	dl,al
	pushf
	cli
	call	opnset44
	inc	dh
	mov	dl,ah
	call	opnset44
	popf
	ret

;==============================================================================
;	ＦＭ　ＶＯＬＵＭＥ　ＳＥＴ
;==============================================================================
;------------------------------------------------------------------------------
;	スロット毎の計算 & 出力 マクロ
;			in.	dl	元のTL値
;				dh	Outするレジスタ
;				al	音量変動値 中心=80h
;------------------------------------------------------------------------------
volset_slot	macro
local	vsl_noover1,vsl_noover2
	add	al,dl
	jnc	vsl_noover1
	mov	al,255
vsl_noover1:
	sub	al,80h
	jnc	vsl_noover2
	xor	al,al
vsl_noover2:
	mov	dl,al
	call	opnset
	endm

;------------------------------------------------------------------------------
;	ＦＭ音量設定メイン
;------------------------------------------------------------------------------
volset:	
	mov	bl,slotmask[di]		;bl<- slotmask
	test	bl,bl
	jnz	vs_exec
	ret				;SlotMaskが0の時
vs_exec:
	mov	al,volpush[di]
	test	al,al
	jz	vs_00a
	dec	al
	jmp	vs_00
vs_00a:	mov	al,volume[di]
vs_00:	mov	cl,al

	cmp	di,offset part_e
	jz	fmvs			;効果音の場合はvoldown/fadeout影響無し

;------------------------------------------------------------------------------
;	音量down計算
;------------------------------------------------------------------------------
	mov	al,[fm_voldown]
	test	al,al
	jz	fm_fade_calc
	neg	al
	mul	cl
	mov	cl,ah

;------------------------------------------------------------------------------
;	Fadeout計算
;------------------------------------------------------------------------------
fm_fade_calc:
	mov	al,[fadeout_volume]
	cmp	al,2
	jc	fmvs
	shr	al,1	;50%下げれば充分
	neg	al
	mul	cl
	mov	cl,ah

;------------------------------------------------------------------------------
;	音量をcarrierに設定 & 音量LFO処理
;		input	cl to Volume[0-127]
;			bl to SlotMask
;------------------------------------------------------------------------------
fmvs:
	xor	bh,bh			;Vol Slot Mask
	mov	ch,bl			;ch=SlotMask Push

	push	si
	mov	si,offset vol_tbl

	mov	word ptr [si],8080h
	mov	word ptr 2[si],8080h

	not	cl			;cl=carrierに設定する音量+80H(add)
	and	bl,carrier[di]		;bl=音量   を設定するSLOT xxxx0000b
	or	bh,bl

	rol	bl,1
	jnc	fmvs_01
	mov	[si],cl
fmvs_01:inc	si

	rol	bl,1
	jnc	fmvs_02
	mov	[si],cl
fmvs_02:inc	si

	rol	bl,1
	jnc	fmvs_03
	mov	[si],cl
fmvs_03:inc	si

	rol	bl,1
	jnc	fmvs_04
	mov	[si],cl
fmvs_04:sub	si,3

	cmp	cl,255		;音量0?
	jz	fmvs_no_lfo

	test	lfoswi[di],2
	jz	fmvs_not_vollfo1
	mov	bl,volmask[di]
	and	bl,ch			;bl=音量LFOを設定するSLOT xxxx0000b
	or	bh,bl
	mov	ax,lfodat[di]		;ax=音量LFO変動値(sub)
	call	fmlfo_sub

fmvs_not_vollfo1:

	test	lfoswi[di],20h
	jz	fmvs_no_lfo
	mov	bl,_volmask[di]
	and	bl,ch			;bh=音量LFOを設定するSLOT xxxx0000b
	or	bh,bl
	mov	ax,_lfodat[di]		;ax=音量LFO変動値(sub)
	call	fmlfo_sub

fmvs_no_lfo:
	mov	dh,4ch-1
	add	dh,[partb]		;dh=FM Port Address

	lodsb
	rol	bh,1
	jnc	fmvm_01
	mov	dl,slot4[di]
	volset_slot

fmvm_01:sub	dh,8
	lodsb
	rol	bh,1
	jnc	fmvm_02
	mov	dl,slot3[di]
	volset_slot

fmvm_02:add	dh,4
	lodsb
	rol	bh,1
	jnc	fmvm_03
	mov	dl,slot2[di]
	volset_slot

fmvm_03:rol	bh,1
	jnc	fmvm_04
	sub	dh,8
	lodsb
	mov	dl,slot1[di]
	volset_slot

fmvm_04:pop	si
	ret

vol_tbl	db	0,0,0,0

;------------------------------------------------------------------------------
;	音量LFO用サブ
;------------------------------------------------------------------------------
fmlfo_sub:
	push	cx
	mov	cx,4
fmlfo_loop:
	rol	bl,1
	jnc	fml_exit
	test	al,al
	js	fmls_minus
	sub	[si],al
	jnc	fml_exit
	mov	byte ptr [si],0
	jmp	fml_exit
fmls_minus:
	sub	[si],al
	jc	fml_exit
	mov	byte ptr [si],0ffh
fml_exit:
	inc	si
	loop	fmlfo_loop
	pop	cx
	sub	si,4
	ret

;==============================================================================
;	ＰＳＧ　ＶＯＬＵＭＥ　ＳＥＴ
;==============================================================================
volsetp:
	cmp	envf[di],3
	jz	volsetp_ret
	cmp	envf[di],-1
	jnz	vsp_00
	cmp	eenv_count[di],0
	jnz	vsp_00
volsetp_ret:
	ret
vsp_00:
	mov	al,volpush[di]
	test	al,al
	jz	vsp_01a
	dec	al
	jmp	vsp_01
vsp_01a:mov	al,volume[di]
vsp_01:	mov	dl,al

;------------------------------------------------------------------------------
;	音量down計算
;------------------------------------------------------------------------------
	mov	al,[ssg_voldown]
	test	al,al
	jz	psg_fade_calc
	neg	al
	mul	dl
	mov	dl,ah

;------------------------------------------------------------------------------
;	Fadeout計算
;------------------------------------------------------------------------------
psg_fade_calc:
	mov	al,[fadeout_volume]
	test	al,al
	jz	psg_env_calc
	neg	al
	mul	dl
	mov	dl,ah

;------------------------------------------------------------------------------
;	ENVELOPE 計算
;------------------------------------------------------------------------------
psg_env_calc:
	test	dl,dl	;音量0?
	jz	pv_out

	cmp	envf[di],-1
	jnz	normal_pvset
	mov	al,dl	;拡張版 音量=dl*(eenv_vol+1)/16
	mov	dl,eenv_volume[di]
	test	dl,dl
	jz	pv_min
	inc	dl
	mul	dl
	mov	dl,al
	shr	dl,1
	shr	dl,1
	shr	dl,1
	shr	dl,1
	jnc	pv1
	inc	dl
	jmp	pv1

normal_pvset:
	add	dl,penv[di]
	jns	pv0
pv_min:	xor	dl,dl
pv0:	jz	pv_out		;0になったら音量LFOは掛けない
	cmp	dl,16
	jc	pv1
	mov	dl,15

;------------------------------------------------------------------------------
;	音量LFO計算
;------------------------------------------------------------------------------
pv1:	test	lfoswi[di],22h
	jz	pv_out

	xor	ax,ax
	test	lfoswi[di],2
	jz	pv_nolfo1
	mov	ax,lfodat[di]
pv_nolfo1:
	test	lfoswi[di],20h
	jz	pv_nolfo2
	add	ax,_lfodat[di]
pv_nolfo2:

	xor	dh,dh
	add	dx,ax
	jns	pv10
	xor	dl,dl
	jmp	pv_out
pv10:	cmp	dx,16
	jc	pv_out
	mov	dl,15

;------------------------------------------------------------------------------
;	出力
;------------------------------------------------------------------------------
pv_out:
	mov	dh,[partb]
	add	dh,8-1
	jmp	opnset44

;==============================================================================
;	ＦＭ　ＫＥＹＯＮ
;==============================================================================
keyon:
	cmp	onkai[di],-1
	jnz	ko1
keyon_ret:
	ret			; ｷｭｳﾌ ﾉ ﾄｷ
ko1:
	mov	dh,28h
	mov	dl,[partb]
	dec	dl
	xor	bh,bh
	mov	bl,dl
if	board2
	cmp	[fmsel],bh	;0
	jnz	ura_keyon
endif
	add	bx,offset omote_key1
	mov	al,[bx]
	or	al,slotmask[di]
	cmp	sdelay_c[di],0
	jz	no_sdm
	and	al,sdelay_m[di]
no_sdm:	mov	[bx],al
	or	dl,al
	jmp	opnset44
if	board2
ura_keyon:
	add	bx,offset ura_key1
	mov	al,[bx]
	or	al,slotmask[di]
	cmp	sdelay_c[di],0
	jz	no_sdm2
	and	al,sdelay_m[di]
no_sdm2:mov	[bx],al
	or	dl,al
	or	dl,00000100b	;Ura Port
	jmp	opnset44
endif

;==============================================================================
;	ＰＳＧ　ＫＥＹＯＮ
;==============================================================================
keyonp:
	cmp	onkai[di],-1
	jnz	ko1p
	ret			; ｷｭｳﾌ ﾉ ﾄｷ
ko1p:
	pushf
	cli
	call	psgmsk		;AL=07h AH=Maskdata
	or	al,ah
	and	ah,psgpat[di]
	not	ah
	and	al,ah
	mov	dh,7
	mov	dl,al
	call	opnset44
	popf
	;
	; PSG ﾉｲｽﾞ ｼｭｳﾊｽｳ ﾉ ｾｯﾄ
	;
	mov	dl,[psnoi]
	cmp	dl,[psnoi_last]
	jz	psnoi_ret	;同じなら定義しない
	test	[psgefcnum],80h
	jz	psnoi_ret	;PSG効果音発音中は変更しない
	mov	dh,6
	call	opnset44
	mov	[psnoi_last],dl
psnoi_ret:
	ret

;==============================================================================
;	ＰＳＧ07hポートのKEYON/OFF準備 (07Hを読み、マスクする値を算出)
;		OUTPUT ... al <- 07h Read Data
;			   ah <- Mask Data
;==============================================================================
psgmsk:
	mov	cl,[partb]
	xor	al,al
	stc
	rcl	al,cl
	mov	ah,al
	shl	al,1
	shl	al,1
	shl	al,1
	or	ah,al

	jmp	get07

;==============================================================================
;	KEY OFF
;		don't Break AL
;==============================================================================
keyoff:
	cmp	onkai[di],-1
	jnz	kof1
	ret			; ｷｭｳﾌ ﾉ ﾄｷ
kof1:
	mov	dh,28h
	mov	dl,[partb]
	dec	dl
	xor	bh,bh
	mov	bl,dl
if	board2
	cmp	[fmsel],0
	jnz	ura_keyoff
endif
	add	bx,offset omote_key1
	mov	cl,slotmask[di]
	not	cl
	and	cl,[bx]
	mov	[bx],cl
	or	dl,cl
	jmp	opnset44

if	board2
ura_keyoff:
	add	bx,offset ura_key1
	mov	cl,slotmask[di]
	not	cl
	and	cl,[bx]
	mov	[bx],cl
	or	dl,cl
	or	dl,00000100b	;FM Ura Port
	jmp	opnset44
endif

keyoffp:
	cmp	onkai[di],-1
	jnz	kofp1
	ret			; ｷｭｳﾌ ﾉ ﾄｷ
kofp1:
	cmp	envf[di],-1
	jz	kofp1_ext
	mov	envf[di],2
	ret
kofp1_ext:
	mov	eenv_count[di],4
	ret

;==============================================================================
;	音色の設定
;		INPUTS	-- [PARTB]			
;			-- dl [TONE_NUMBER]
;			-- di [PART_DATA_ADDRESS]
;==============================================================================
neiroset:
	call	toneadr_calc
	call	silence_fmpart
	jnc	neiroset_main

;	neiromask=0の時 (TLのworkのみ設定)
	add	bx,4
	jmp	neiroset_tl

;==============================================================================
;	音色設定メイン
;==============================================================================
;------------------------------------------------------------------------------
;	AL/FBを設定
;------------------------------------------------------------------------------
neiroset_main:
	mov	dh,0b0h-1
	add	dh,[partb]
	mov	dl,24[bx]

	cmp	[af_check],0	;ALG/FBは設定しないmodeか？
	jz	no_af
	mov	dl,alg_fb[di]
no_af:
	cmp	[partb],3
	jnz	nss_notfm3
if	board2
	cmp	[fmsel],0
	jnz	nss_notfm3
else
	cmp	di,offset part_e
	jz	nss_notfm3
endif
	cmp	[af_check],0	;ALG/FBは設定しないmodeか？
	jz	set_fm3_alg_fb

	mov	dl,[fm3_alg_fb]
	jmp	nss_notfm3

set_fm3_alg_fb:
	test	slotmask[di],10h	;slot1を使用していなければ
	jnz	nss_notslot1
	mov	al,[fm3_alg_fb]
	and	al,00111000b		;fbは前の値を使用
	and	dl,00000111b
	or	dl,al
nss_notslot1:
	mov	[fm3_alg_fb],dl
nss_notfm3:
	call	opnset
	mov	alg_fb[di],dl
	and	dl,7	;dl=algo

;------------------------------------------------------------------------------
;	Carrierの位置を調べる (VolMaskにも設定)
;------------------------------------------------------------------------------
check_carrier:
	push	bx
	xor	bh,bh
	mov	bl,dl
	add	bx,offset carrier_table
	mov	al,[bx]
	test	volmask[di],0fh
	jnz	not_set_volmask	; Volmask値が0以外の場合は設定しない
	mov	volmask[di],al
not_set_volmask:
	test	_volmask[di],0fh
	jnz	not_set_volmask2
	mov	_volmask[di],al
not_set_volmask2:
	mov	carrier[di],al
	mov	ah,[bx+8]	; slot2/3の逆転データ(not済み)
	pop	bx

	mov	al,neiromask[di]
	and	ah,al		;AH=TL用のmask / AL=その他用のmask

;------------------------------------------------------------------------------
;	各音色パラメータを設定 (TLはモジュレータのみ)
;------------------------------------------------------------------------------
	mov	dh,30h-1
	add	dh,[partb]

	mov	cx,4	;DT/ML
ns01:	mov	dl,[bx]
	inc	bx
	rol	al,1
	jnc	ns_ns
	call	opnset
ns_ns:	add	dh,4
	loop	ns01

	mov	cx,4	;TL
ns01b:	mov	dl,[bx]
	inc	bx
	rol	ah,1
	jnc	ns_nsb
	call	opnset
ns_nsb:	add	dh,4
	loop	ns01b

	mov	cx,16	;残り
ns01c:	mov	dl,[bx]
	inc	bx
	rol	al,1
	jnc	ns_nsc
	call	opnset
ns_nsc:	add	dh,4
	loop	ns01c

;------------------------------------------------------------------------------
;	SLOT毎のTLをワークに保存
;------------------------------------------------------------------------------
	sub	bx,20
neiroset_tl:
	push	si
	push	di
	mov	si,bx
	add	di,slot1
	movsw
	movsw
	pop	di
	pop	si
	ret

;==============================================================================
;	TONE DATA START ADDRESS を計算
;		input	dl	tone_number
;		output	bx	address
;==============================================================================
toneadr_calc:
	cmp	[prg_flg],0
	jnz	prgdat_get
	cmp	di,offset part_e
	jz	prgdat_get
	mov	bx,[tondat]
	mov	al,dl
	xor	ah,ah
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	bx,ax
	ret
prgdat_get:
	mov	bx,[prgdat_adr]
	cmp	di,offset part_e
	jnz	gpd_loop
	mov	bx,[prgdat_adr2]	;FM効果音の場合
gpd_loop:
	cmp	[bx],dl
	jz	gpd_exit
	add	bx,26
	jmp	gpd_loop
gpd_exit:
	inc	bx
	ret

;==============================================================================
;	[PartB]のパートの音を完璧に消す (TL=127 and RR=15 and KEY-OFF)
;		cy=1 ･･･ 全スロットneiromaskされている
;==============================================================================
silence_fmpart:
	mov	al,neiromask[di]
	test	al,al
	jz	sfm_exit
	push	dx
	mov	dh,[partb]
	add	dh,40h-1

	mov	cx,4
	mov	dl,127	; TL = 127 / RR=15
ns00c:	rol	al,1
	jnc	ns00d
	call	opnset
	add	dh,40h
	call	opnset
	sub	dh,40h
ns00d:	add	dh,4
	loop	ns00c

	push	bx
	call	kof1	; KEY OFF
	pop	bx
	pop	dx
	clc
	ret
sfm_exit:
	stc
	ret

;==============================================================================
;	ＬＦＯ処理
;		Don't Break cl
;		output		cy=1	変化があった
;==============================================================================
lfo:	
lfop:
	cmp	delay[di],0
	jz	lfo1
	dec	delay[di]	;cy=0
lfo_ret:
	ret
lfo1:
	test	extendmode[di],2	;TimerAと合わせるか？
	jz	lfo_normal		;そうじゃないなら無条件にlfo処理
	mov	ch,[TimerAtime]
	sub	ch,[lastTimerAtime]
	jz	lfo_ret			;前回の値と同じなら何もしない cy=0
	mov	ax,lfodat[di]
	push	ax
lfo_loop:
	call	lfo_main
	dec	ch
	jnz	lfo_loop
	jmp	lfo_check

lfo_normal:
	mov	ax,lfodat[di]
	push	ax
	call	lfo_main
lfo_check:
	pop	ax
	cmp	ax,lfodat[di]
	jnz	lfo_stc_ret
	ret	;c=0
lfo_stc_ret:
	stc
	ret

lfo_main:
	cmp	speed[di],1
	jz	lfo2
	cmp	speed[di],-1
	jz	lfom_ret
	dec	speed[di]
lfom_ret:
	ret
lfo2:
	mov	al,speed2[di]
	mov	speed[di],al
	
	mov	bl,lfo_wave[di]
	test	bl,bl
	jz	lfo_sankaku
	cmp	bl,4
	jz	lfo_sankaku
	cmp	bl,2
	jz	lfo_kukei
	cmp	bl,6
	jz	lfo_oneshot
	cmp	bl,5
	jnz	not_sankaku

;	三角波		lfowave = 0,4,5
	mov	al,step[di]
	mov	ah,al
	or	ah,ah
	jns	lfo2ns
	neg	ah
lfo2ns:	imul	ah	;lfowave=5の場合 1step = step×｜step｜
	jmp	lfo20

lfo_sankaku:
	mov	al,step[di]
	cbw
lfo20:	add	lfodat[di],ax
	jnz	lfo21
	call	md_inc
lfo21:
	mov	al,time[di]
	cmp	al,255
	jz	lfo3
	dec	al
	jnz	lfo3
	mov	al,time2[di]
	cmp	bl,4
	jz	lfo22
	add	al,al	;lfowave=0,5の場合 timeを反転時２倍にする
lfo22:	mov	time[di],al
	mov	al,step[di]
	neg	al
	mov	step[di],al
	ret
lfo3:
	mov	time[di],al
	ret

not_sankaku:
	dec	bl
	jnz	not_nokogiri
;	ノコギリ波	lfowave = 1,6
	mov	al,step[di]
	cbw
	add	lfodat[di],ax

	mov	al,time[di]
	cmp	al,-1
	jz	nk_lfo3
	dec	al
	jnz	nk_lfo3
	neg	lfodat[di]
	call	md_inc
	mov	al,time2[di]
	add	al,al
nk_lfo3:
	mov	time[di],al
	ret

lfo_oneshot:
;	ワンショット	lfowave = 6
	mov	al,time[di]
	test	al,al
	jz	lfoone_ret
	cmp	al,-1
	jz	lfoone_nodec
	dec	al
	mov	time[di],al
lfoone_nodec:
	mov	al,step[di]
	cbw
	add	lfodat[di],ax
lfoone_ret:
	ret

lfo_kukei:
;	矩形波		lfowave = 2
	mov	al,step[di]
	imul	time[di]
	mov	lfodat[di],ax
	call	md_inc
	neg	step[di]
	ret

not_nokogiri:
;	ランダム波	lfowave = 3
	mov	al,step[di]
	test	al,al
	jns	ns_plus
	neg	al
ns_plus:
	mul	time[di]
	push	ax
	push	cx
	add	ax,ax
	call	rnd
	pop	cx
	pop	bx
	sub	ax,bx
	mov	lfodat[di],ax

;==============================================================================
;	MDコマンドの値によってSTEP値を変更
;==============================================================================
md_inc:
	dec	mdspd[di]
	jnz	md_exit
	mov	al,mdspd2[di]
	mov	mdspd[di],al

	mov	al,mdc[di]
	test	al,al
	jz	md_exit		;count =0
	js	mdi21		;count > 127 (255)
	dec	al
	mov	mdc[di],al

mdi21:	mov	al,step[di]
	test	al,al
	jns	mdi22
	neg	al
	add	al,mdepth[di]
	js	mdi21_ov
	neg	al
mdi21_s:
	mov	step[di],al
md_exit:
	ret

mdi21_ov:
	xor	al,al
	test	mdepth[di],80h
	jnz	mdi21_s
	mov	al,-127
	jmp	mdi21_s

mdi22:
	add	al,mdepth[di]
	js	mdi22_ov
mdi22_s:
	mov	step[di],al
	ret
mdi22_ov:
	xor	al,al
	test	mdepth[di],80h
	jnz	mdi22_s
	mov	al,+127
	jmp	mdi22_s

;==============================================================================
;	乱数発生ルーチン	INPUT : AX=MAX_RANDOM
;				OUTPUT: AX=RANDOM_NUMBER
;==============================================================================
rnd:
	mov	cx,ax
	mov	ax,259
	mul	[seed]
	add	ax,3
	and	ax,32767

	mov	[seed],ax
	mul	cx
	mov	cx,32767
	div	cx
	ret
seed	dw	?

;==============================================================================
;	ＬＦＯとＰＳＧ／ＰＣＭのソフトウエアエンベロープの初期化
;==============================================================================
;==============================================================================
;	ＰＳＧ／ＰＣＭ音源用　Entry
;==============================================================================
lfoinitp:
	mov	ah,al	; ｷｭｰﾌ ﾉ ﾄｷ ﾊ INIT ｼﾅｲﾖ
	and	ah,0fh
	cmp	ah,0ch
	jnz	lip_00
	mov	al,onkai_def[di]
	mov	ah,al
	and	ah,0fh
lip_00:	mov	onkai_def[di],al
	cmp	ah,0fh
;	4.8r	修正
	jz	lfo_exitp
	mov	porta_num[di],0	;ポルタメントは初期化

	test	[tieflag],1	; ﾏｴ ｶﾞ & ﾉ ﾄｷ ﾓ INIT ｼﾅｲ｡
	jz	seinit
lfo_exitp:
	push	ax
	call	soft_env	; 前が & の場合 -> 1回 SoftEnv処理
	pop	ax
	jmp	lfo_exit
;	ここまで
;==============================================================================
;	ソフトウエアエンベロープ初期化
;==============================================================================
seinit:
	cmp	envf[di],-1
	jz	extenv_init
	mov	envf[di],0
	mov	penv[di],0
	mov	ah,patb[di]
	mov	pat[di],ah
	test	ah,ah
	jnz	lfin2
	mov	envf[di],1	;ATTACK=0 ... ｽｸﾞ Decay ﾆ
	mov	ah,pv2[di]	;
	mov	penv[di],ah	;
lfin2:	mov	ah,pr1b[di]
	mov	pr1[di],ah
	mov	ah,pr2b[di]
	mov	pr2[di],ah
	jmp	lfin1

;	拡張ssg_envelope用
extenv_init:
	mov	ah,eenv_ar[di]
	sub	ah,16
	mov	eenv_arc[di],ah
	mov	ah,eenv_dr[di]
	sub	ah,16
	jns	eei_dr_notx
	add	ah,ah
eei_dr_notx:
	mov	eenv_drc[di],ah
	mov	ah,eenv_sr[di]
	sub	ah,16
	jns	eei_sr_notx
	add	ah,ah
eei_sr_notx:
	mov	eenv_src[di],ah
	mov	ah,eenv_rr[di]
	add	ah,ah
	sub	ah,16
	mov	eenv_rrc[di],ah

	mov	ah,eenv_al[di]
	mov	eenv_volume[di],ah

	mov	eenv_count[di],1
	push	ax
	call	ext_ssgenv_main	;最初の１回
	pop	ax
	jmp	lfin1

;==============================================================================
;	ＦＭ音源用　Entry
;==============================================================================
lfoinit:
	mov	ah,al	; ｷｭｰﾌ ﾉ ﾄｷ ﾊ INIT ｼﾅｲﾖ
	and	ah,0fh
	cmp	ah,0ch
	jnz	li_00
	mov	al,onkai_def[di]
	mov	ah,al
	and	ah,0fh
li_00:	mov	onkai_def[di],al
	cmp	ah,0fh
	jz	lfo_exit
	mov	porta_num[di],0	;ポルタメントは初期化

	test	[tieflag],1	; ﾏｴ ｶﾞ & ﾉ ﾄｷ ﾓ INIT ｼﾅｲ｡
	jz	lfin1

lfo_exit:
	test	lfoswi[di],3	; LFO使用中か？
	jz	le_no_one_lfo1	; 前が & の場合 -> 1回 LFO処理
	push	ax
	call	lfo
	pop	ax
le_no_one_lfo1:
	test	lfoswi[di],30h	; LFO使用中か？
	jz	le_no_one_lfo2	; 前が & の場合 -> 1回 LFO処理
	push	ax
	pushf
	cli
	call	lfo_change
	call	lfo
	call	lfo_change
	popf
	pop	ax
le_no_one_lfo2:
	ret

;==============================================================================
;	ＬＦＯ初期化
;==============================================================================
lfin1:
if	board2
	mov	ah,hldelay[di]
	mov	hldelay_c[di],ah
	test	ah,ah
	jz	non_hldelay
	mov	dh,[partb]
	add	dh,0b4h-1
	mov	dl,fmpan[di]
	and	dl,0c0h		;HLFO = OFF
	call	opnset
non_hldelay:
endif
	mov	ah,sdelay[di]
	mov	sdelay_c[di],ah

	mov	cl,lfoswi[di]
	test	cl,3
	jz	li_lfo1_exit	; LFOは未使用
	test	cl,4		;keyon非同期か?
	jnz	li_lfo1_next
	call	lfoinit_main
li_lfo1_next:
	push	ax
	call	lfo
	pop	ax
li_lfo1_exit:

	test	cl,30h
	jz	li_lfo2_exit	; LFOは未使用
	test	cl,40h		;keyon非同期か?
	jnz	li_lfo2_next
	push	ax
	pushf
	cli
	call	lfo_change
	call	lfoinit_main
	call	lfo_change
	popf
	pop	ax

li_lfo2_next:
	push	ax
	pushf
	cli
	call	lfo_change
	call	lfo
	call	lfo_change
	popf
	pop	ax
li_lfo2_exit:
	ret

lfoinit_main:
	mov	lfodat[di],0

	mov	dx,word ptr delay2[di]
	mov	word ptr delay[di],dx
	mov	dx,word ptr step2[di]
	mov	word ptr step[di],dx
	mov	dl,mdc2[di]
	mov	mdc[di],dl

	cmp	lfo_wave[di],2	;矩形波または
	jz	lim_first
	cmp	lfo_wave[di],3	;ランダム波の場合は
	jnz	lim_nofirst
lim_first:
	mov	speed[di],1	;delay直後にLFOが掛かるようにする
	ret
lim_nofirst:
	inc	speed[di]	;それ以外の場合はdelay直後のspeed値を +1
	ret

;==============================================================================
;	ＰＳＧ／ＰＣＭのソフトウエアエンベロープ
;==============================================================================
soft_env:
	test	extendmode[di],4	;TimerAと合わせるか？
	jz	soft_env_main		;そうじゃないなら無条件にsenv処理
	mov	ch,[TimerAtime]
	sub	ch,[lastTimerAtime]
	jz	senv_ret		;前回の値と同じなら何もしない	cy=0
	xor	cl,cl
senv_loop:
	call	soft_env_main
	jnc	sel00
	mov	cl,1
sel00:	dec	ch
	jnz	senv_loop
	ror	cl,1		;cy setting
senv_ret:
	ret

soft_env_main:
	cmp	envf[di],-1
	jz	ext_ssgenv_main

	mov	dl,penv[di]
	call	soft_env_sub
	cmp	dl,penv[di]
	jz	sem_ret	;cy=0
	stc
sem_ret:ret

soft_env_sub:
	cmp	envf[di],0
	jnz	se1
	;
	; Attack
	;
	dec	pat[di]
	jnz	se2
	mov	envf[di],1
	mov	al,pv2[di]
	mov	penv[di],al
	stc
	ret
se1:
	cmp	envf[di],2
	jz	se3
	;
	; Decay
	;
	cmp	pr1[di],0
	jz	se2		;ＤＲ＝０の時は減衰しない
	dec	pr1[di]
	jnz	se2
	mov	al,pr1b[di]
	mov	pr1[di],al
	dec	penv[di]

se4:	cmp	penv[di],-15
	jnc	se2
	cmp	penv[di],15
	jc	se2
se5:	mov	penv[di],-15
se2:	ret
	;
	; Release
	;
se3:	cmp	pr2[di],0
	jz	se5		;ＲＲ＝０の時はすぐに音消し
	dec	pr2[di]
	jnz	se2
	mov	al,pr2b[di]
	mov	pr2[di],al
	dec	penv[di]
	jmp	se4

;	拡張版
ext_ssgenv_main:
	mov	ah,eenv_count[di]
	test	ah,ah
	jnz	esm_main2
esm_ret:ret	;cy=0

esm_main2:
	mov	dl,eenv_volume[di]
	call	esm_sub
	cmp	dl,eenv_volume[di]
	jz	esm_ret	;cy=0
	stc
	ret

esm_sub:
esm_ar_check:
	dec	ah
	jnz	esm_dr_check
;
;	[[[ Attack Rate ]]]
;
	mov	al,eenv_arc[di]
	dec	al
	js	arc_count_check	;0以下の場合はカウントCHECK
	inc	al
	add	eenv_volume[di],al
	cmp	eenv_volume[di],15
	jnc	esm_ar_next
	mov	ah,eenv_ar[di]
	sub	ah,16
	mov	eenv_arc[di],ah
	ret
esm_ar_next:
	mov	eenv_volume[di],15
	inc	eenv_count[di]
	cmp	eenv_sl[di],15	;SL=0の場合はすぐSRに
	jnz	esm_ret
	inc	eenv_count[di]
	ret
arc_count_check:
	cmp	eenv_ar[di],0	;AR=0?
	jz	esm_ret
	inc	eenv_arc[di]
	ret

esm_dr_check:
	dec	ah
	jnz	esm_sr_check
;
;	[[[ Decay Rate ]]]
;
	mov	al,eenv_drc[di]
	dec	al
	js	drc_count_check	;0以下の場合はカウントCHECK
	inc	al
	sub	eenv_volume[di],al
	mov	al,eenv_sl[di]
	jc	dr_slset
	cmp	eenv_volume[di],al
	jc	dr_slset
	mov	ah,eenv_dr[di]
	sub	ah,16
	jns	esm_dr_notx
	add	ah,ah
esm_dr_notx:
	mov	eenv_drc[di],ah
	ret
dr_slset:
	mov	eenv_volume[di],al
	inc	eenv_count[di]
	ret
drc_count_check:
	cmp	eenv_dr[di],0	;DR=0?
	jz	esm_ret
	inc	eenv_drc[di]
	ret

esm_sr_check:
	dec	ah
	jnz	esm_rr
;
;	[[[ Sustain Rate ]]]
;
	mov	al,eenv_src[di]
	dec	al
	js	src_count_check	;0以下の場合はカウントCHECK
	inc	al
	sub	eenv_volume[di],al
	jnc	esm_sr_exit
	mov	eenv_volume[di],0
esm_sr_exit:
	mov	ah,eenv_sr[di]
	sub	ah,16
	jns	esm_sr_notx
	add	ah,ah
esm_sr_notx:
	mov	eenv_src[di],ah
	ret
src_count_check:
	cmp	eenv_sr[di],0	;SR=0?
	jz	esm_ret
	inc	eenv_src[di]
	ret

esm_rr:
;
;	[[[ Release Rate ]]]
;
	mov	al,eenv_rrc[di]
	dec	al
	js	rrc_count_check	;0以下の場合はカウントCHECK
	inc	al
	sub	eenv_volume[di],al
	jnc	esm_rr_exit
	mov	eenv_volume[di],0
esm_rr_exit:
	mov	ah,eenv_rr[di]
	add	ah,ah
	sub	ah,16
	mov	eenv_rrc[di],ah
	ret
rrc_count_check:
	cmp	eenv_rr[di],0	;RR=0?
	jz	esm_ret
	inc	eenv_rrc[di]
	ret

;==============================================================================
;	FADE IN / OUT ROUTINE
;
;		FROM Timer-A
;==============================================================================
fadeout:
	cmp	[pause_flag],1	;pause中はfadeoutしない
	jz	fade_exit
	mov	al,[fadeout_speed]
	test	al,al
	jz	fade_exit
	js	fade_in
	add	al,[fadeout_volume]
	jc	fadeout_end
	mov	[fadeout_volume],al
	ret
fadeout_end:
	mov	[fadeout_volume],255
	mov	[fadeout_speed],0
	cmp	[fade_stop_flag],1
	jnz	fade_exit
	or	[music_flag],2
fade_exit:
	ret

fade_in:
	add	al,[fadeout_volume]
	jnc	fadein_end
	mov	[fadeout_volume],al
	ret
fadein_end:
	mov	[fadeout_volume],0
	mov	[fadeout_speed],0
if	board2
	mov	dl,[rhyvol]
	call	volset2rf
endif
	ret

;==============================================================================
;	インタラプト　設定
;	FM音源専用
;==============================================================================
setint:
	pushf
	cli	;割り込み禁止
	;
	; ＯＰＮ割り込み初期設定
	;
	mov	[tempo_d],200		; TIMER B SET
	mov	[tempo_d_push],200
	call	calc_tb_tempo
	call	settempo_b

	mov	dx,2500h
	call	opnset44
	mov	dx,2400h	; TIMER A SET (9216μs固定)
	call	opnset44	; 一番遅くて丁度いい

	mov	dh,27h
	mov	dl,00111111b	; TIMER ENABLE
	call	opnset44

	popf

	;
	;　小節カウンタリセット
	;
	xor	ax,ax
	mov	[opncount],al
	mov	[syousetu],ax
	mov	[syousetu_lng],96

	ret

;==============================================================================
;	ALL SILENCE
;==============================================================================
silence:
if	board2
	call	sel44		;mmainには飛ばない状況下なので大丈夫
	mov	ah,2
endif
oploop:
	cmp	[fm_effec_flag],1
	jnz	opi_nef
if	board2
	cmp	ah,1
	jnz	opi_nef
endif
	mov	bx,offset fmoff_ef
	jmp	opi_ef
opi_nef:
	mov	bx,offset fmoff_nef
opi_ef:
opi0:	mov	dh,[bx]
	inc	bx
	cmp	dh,-1
	jz	opi1b
	add	dh,80h
	mov	dl,0ffh		; FM Release = 15
	call	opnset
	jmp	opi0
opi1b:
if	board2
	push	ax
	call	sel46		;mmainには飛ばない状況下なので大丈夫
	pop	ax
	dec	ah
	jnz	oploop
endif
	
	mov	dx,2800h	; FM KEYOFF
	mov	cx,3
ife	board2
	cmp	[fm_effec_flag],1
	jnz	opi1
	dec	cx
endif
opi1:	call	opnset44
	inc	dl
	loop	opi1

if	board2
	mov	dx,2804h	; FM KEYOFF [URA]
	cmp	[fm_effec_flag],1
	mov	cx,3
	jnz	opi2
	dec	cx
opi2:	call	opnset44
	inc	dl
	loop	opi2
endif

	cmp	[effon],0
	jnz	psg_ef
	cmp	[ppsdrv_flag],0
	jz	opi_nonppsdrv
	xor	ah,ah
	int	ppsdrv		; ppsdrv keyoff

opi_nonppsdrv:
	mov	dx,07bfh	; PSG KEYOFF
	call	opnset44
	jmp	s_pcm
psg_ef:
	pushf
	cli
	call	get07
	mov	dl,al
	and	dl,00111111b
	or	dl,10011011b
	mov	dh,07h
	call	opnset44
	popf

s_pcm:
if	board2
	cmp	[pcmflag],0	; PCM効果音発声中か？
	jnz	pcm_ef

 if	adpcm
  ife	ademu
	cmp	[pcm_gs_flag],1
	jz	pcm_ef
	mov	dx,0102h	; PAN=0 / x8 bit mode
	call	opnset46
	mov	dx,0001h	; PCM RESET
	call	opnset46
  endif
 endif
	mov	dx,1080h	;TA/TB/EOS を RESET
	call	opnset46
	mov	dx,1018h	;TIMERB/A/EOSのみbit変化あり
	call	opnset46	;(NEC音源でも一応実行)

 if	pcm
	call	stop_86pcm
 endif
pcm_ef:
 if	ppz
	cmp	[ppz_call_seg],0
	jz	_not_ppz8

	mov	ah,12h
	int	ppz_vec		;FIFO割り込み停止

	mov	ax,0200h
ppz_off_loop:
	push	ax
	int	ppz_vec		;ppz keyoff
	pop	ax
	inc	al
	cmp	al,8
	jc	ppz_off_loop

_not_ppz8:
 endif
endif
	ret

fmoff_nef	db	0,1,2,4,5,6,8,9,10,12,13,14,-1
fmoff_ef	db	0,1,4,5,8,9,12,13,-1

;==============================================================================
;	SET DATA TO OPN
;		INPUTS ---- D,E
;==============================================================================
;
;	表
;
opnset44:
	push	ax
	push	dx
	push	bx
	mov	bx,dx

	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,bh
	out	dx,al
	_waitP
	mov	dx,[fm1_port2]
	mov	al,bl
	out	dx,al
	popf

	pop	bx
	pop	dx
	pop	ax
	ret

if	board2
;
;	裏
;
opnset46:
	push	ax
	push	bx
	push	dx
	mov	bx,dx

	mov	dx,[fm2_port1]
	pushf
	cli
	rdychk
	mov	al,bh
	out	dx,al
	_waitP
	mov	dx,[fm2_port2]
	mov	al,bl
	out	dx,al
	popf

	pop	dx
	pop	bx
	pop	ax
	ret
endif
;
;	表／裏
;
opnset:	
	push	ax
	push	bx
	push	dx
	mov	bx,dx

	mov	dx,[fm_port1]
	pushf
	cli
	rdychk
	mov	al,bh
	out	dx,al
	_waitP
	mov	dx,[fm_port2]
	mov	al,bl
	out	dx,al
	popf

	pop	dx
	pop	bx
	pop	ax
	ret

;==============================================================================
;	READ PSG 07H Port
;		cliしてから来ること
;==============================================================================
get07:	push	dx
	mov	dx,[fm1_port1]
	rdychk
	mov	al,7
	out	dx,al
	_waitP			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx
	pop	dx
	ret

;==============================================================================
;	ＩＮＴ６０Ｈのメイン
;==============================================================================
int60_start:
	cld

	push	es
	push	bx
	push	cx
	push	si
	push	di

	mov	si,ds
	push	cs:[ds_push]
	mov	cs:[ds_push],si

	mov	si,cs
	mov	ds,si
	mov	es,si

	push	word ptr [ah_push]
	mov	[al_push],al
	mov	[ah_push],ah
	push	[dx_push]
	mov	[dx_push],dx

;	TimerA/B 再入check
	mov	bl,ah
	xor	bh,bh
	mov	bl,reint_chk[bx]
	ror	bl,1
	jnc	non_chk_TimerB
	cmp	[TimerBflag],0
	jnz	reint_error
non_chk_TimerB:
	ror	bl,1
	jnc	non_chk_TimerA
	cmp	[TimerAflag],0
	jnz	reint_error
non_chk_TimerA:
	ror	bl,1
	jnc	non_chk_int60
	cmp	[int60flag],1
	jnz	reint_error
non_chk_int60:

	cmp	[disint],1
	jz	I60_not_sti
	sti
I60_not_sti:
	add	ah,ah
	mov	bl,ah
	mov	si,int60_jumptable[bx]
	call	si

	mov	dx,[dx_push]
	mov	ax,[ds_push]
	mov	ds,ax
	mov	al,cs:[al_push]
	mov	ah,cs:[ah_push]

	pop	cs:[dx_push]
	pop	word ptr cs:[ah_push]
	pop	cs:[ds_push]

	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	es

	jmp	int60_exit

reint_error:
	cmp	[disint],1
	jz	Rei_not_sti
	sti
Rei_not_sti:

	mov	dx,[dx_push]
	mov	ax,[ds_push]
	mov	ds,ax
	mov	al,cs:[al_push]
	mov	ah,cs:[ah_push]

	pop	cs:[dx_push]
	pop	word ptr cs:[ah_push]
	pop	cs:[ds_push]

	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	es

	jmp	int60_error

;	再入check用code / bit0=TimerBint 1=TimerAint 2=INT60
reint_chk	db	4,4,0,6,6,0,0,0,0,0,0,0,7,7,0,5
		db	0,0,0,0,0,0,0,0,7,0,5,5,7,0,7,0
		db	0,0

int60_jumptable	label	word
	dw	mstart_f	;0
	dw	mstop_f		;1
	dw	fout		;2
	dw	eff_on		;3
	dw	effoff		;4
	dw	get_ss		;5
	dw	get_musdat_adr	;6
	dw	get_tondat_adr	;7
	dw	get_fv		;8
	dw	drv_chk		;9
	dw	get_status	;A
	dw	get_efcdat_adr	;B
	dw	fm_effect_on	;C
	dw	fm_effect_off	;D
	dw	get_pcm_adr	;E
if	board2
	dw	pcm_effect	;F
else
	dw	nothing		;F
endif
	dw	get_workadr	;10
	dw	get_fmefc_num	;11
	dw	get_pcmefc_num	;12
	dw	set_fm_int	;13
	dw	set_efc_int	;14
	dw	get_psgefcnum	;15
	dw	get_joy		;16
	dw	get_ppsdrv_flag	;17
	dw	set_ppsdrv_flag	;18
	dw	set_fv		;19
	dw	pause_on	;1A
	dw	pause_off	;1B
	dw	ff_music	;1C
	dw	get_memo	;1D
	dw	part_mask	;1E
	dw	get_fm_int	;1F
	dw	get_efc_int	;20
	dw	get_mus_name	;21
	dw	get_size	;22
int60_max	equ	22h

get_ss:			;5
	call	getss
	mov	[al_push],al
	mov	[ah_push],ah
	ret

get_musdat_adr:		;6
	mov	ax,cs
	mov	[ds_push],ax
	mov	ax,[mmlbuf]
	dec	ax
	mov	[dx_push],ax
	ret

get_tondat_adr:		;7
	mov	ax,cs
	mov	[ds_push],ax
	mov	ax,[tondat]
	mov	[dx_push],ax
	ret

get_efcdat_adr:		;7
	mov	ax,cs
	mov	[ds_push],ax
	mov	ax,[efcdat]
	mov	[dx_push],ax
	ret

get_fv:			;8
	mov	al,[fadeout_volume]
	mov	[al_push],al
	ret

set_fv:			;19
	mov	[fadeout_volume],al
if	board2
	test	al,al
	jnz	set_fv_ret
	mov	dl,[rhyvol]
	call	volset2rf
set_fv_ret:
endif
	ret

drv_chk:
if	board2
 if	ppz
  if	ademu
	mov	[al_push],5
  else
	mov	[al_push],4
  endif
 else
  if	pcm
	mov	[al_push],2
  else
	mov	[al_push],1
  endif
 endif
else
	mov	[al_push],0
endif
	mov	ah,vers
	mov	al,verc
	mov	[ah_push],ah
	mov	[dx_push],ax
	ret

get_status:
	call	getst
	mov	[al_push],al
	mov	[ah_push],ah
	ret

get_pcm_adr:
	mov	ax,cs
	mov	[ds_push],ax
	mov	[dx_push],offset pcm_table
	ret

get_workadr:
	mov	ax,cs
	mov	[ds_push],ax
	mov	[dx_push],offset part_data_table
	ret

get_fmefc_num:
	mov	al,[fm_effec_num]
	mov	[al_push],al
	ret

get_pcmefc_num:
	mov	al,[pcm_effec_num]
	mov	[al_push],al
	ret

set_fm_int:
	mov	ax,[ds_push]
	mov	[fmint_seg],ax
	mov	bx,[dx_push]
	mov	[fmint_ofs],bx
	or	[intfook_flag],1
	or	[rescut_cant],80h	;常駐解除禁止フラグをセット
	or	ax,bx
	jnz	sfi_ret
	and	[intfook_flag],0feh
	and	[rescut_cant],7fh
sfi_ret:
	ret

set_efc_int:
	mov	ax,[ds_push]
	mov	[efcint_seg],ax
	mov	bx,[dx_push]
	mov	[efcint_ofs],bx
	or	[intfook_flag],2
	or	[rescut_cant],40h	;常駐解除禁止フラグをセット
	or	ax,bx
	jnz	sei_ret
	and	[intfook_flag],0fdh
	and	[rescut_cant],0bfh
sei_ret:
	ret

get_fm_int:
	mov	ax,[fmint_seg]
	mov	[ds_push],ax
	mov	ax,[fmint_ofs]
	mov	[dx_push],ax
	ret

get_efc_int:
	mov	ax,[efcint_seg]
	mov	[ds_push],ax
	mov	ax,[efcint_ofs]
	mov	[dx_push],ax
	ret

get_psgefcnum:
	mov	al,[psgefcnum]
	mov	[ah_push],al
	mov	al,[effon]
	mov	[al_push],al
	ret

get_ppsdrv_flag:
	mov	al,[ppsdrv_flag]
	mov	[al_push],al
	ret

set_ppsdrv_flag:
	mov	[ppsdrv_flag],0

	xor	ax,ax
	mov	es,ax
	les	bx,es:[ppsdrv*4]
	cmp	word ptr es:2[bx],"MP"
	jnz	spf_exit
	cmp	byte ptr es:4[bx],"P"
	jnz	spf_exit

	mov	al,[al_push]
	mov	[ppsdrv_flag],al
spf_exit:
	ret

get_mus_name:	;21h
	mov	ax,offset mus_filename
	mov	[dx_push],ax
	mov	[ds_push],cs
	ret

get_size:	;22h
	mov	al,[mmldat_lng]
	mov	[al_push],al
	mov	al,[voicedat_lng]
	mov	[ah_push],al
	mov	al,[effecdat_lng]
	mov	byte ptr [dx_push],al
	ret

;==============================================================================
;	Joystick Data Get
;==============================================================================
get_joy:
	pushf
	cli
	call	get07
	mov	dl,al
	and	dl,03fh
	or	dl,080h
	mov	dh,07
	call	opnset44	;mode set
	popf

	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,0fh
	out	dx,al
	_wait			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx		;input now
	and	al,0fh
	or	al,80h
	out	dx,al		;joystick init (1)
	popf

	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,0eh
	out	dx,al
	_wait			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx
	popf
	and	al,3fh		;joystick data (1)
	mov	[al_push],al

	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,0fh
	out	dx,al
	_wait			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx		;input now
	and	al,0fh
	or	al,0c0h
	out	dx,al		;joystick init (2)
	popf

	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,0eh
	out	dx,al
	_wait			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx
	popf
	and	al,3fh		;joystick data (2)

	mov	[ah_push],al

	ret

;==============================================================================
;	Pause on
;==============================================================================
pause_on:
	cmp	[play_flag],0
	jz	pauon_exit
	mov	[play_flag],0
	mov	[pause_flag],1
	call	silence
pauon_exit:
	ret

;==============================================================================
;	Pause off
;==============================================================================
pause_off:
	cmp	[play_flag],0
	jnz	pauoff_exit2
	cmp	[pause_flag],1
	jnz	pauoff_exit2

if	board2
	call	sel44		;mmainには飛ばない状況下なので大丈夫
endif
	mov	di,offset part1
	mov	dl,voicenum[di]
	mov	[partb],1
	call	neiro_reset
	mov	di,offset part2
	mov	dl,voicenum[di]
	mov	[partb],2
	call	neiro_reset
ife	board2
	cmp	[fm_effec_flag],1
	jz	pauoff_exit
endif
	mov	di,offset part3
	mov	dl,voicenum[di]
	mov	[partb],3
	call	neiro_reset
	mov	di,offset part3b
	mov	dl,voicenum[di]
	call	neiro_reset
	mov	di,offset part3c
	mov	dl,voicenum[di]
	call	neiro_reset
	mov	di,offset part3d
	mov	dl,voicenum[di]
	call	neiro_reset

if	board2
	call	sel46		;mmainには飛ばない状況下なので大丈夫

	mov	di,offset part4
	mov	[partb],1
	mov	dl,voicenum[di]
	call	neiro_reset

	mov	di,offset part5
	mov	[partb],2
	mov	dl,voicenum[di]
	call	neiro_reset

	cmp	[fm_effec_flag],1
	jz	pauoff_exit

	mov	di,offset part6
	mov	[partb],3
	mov	dl,voicenum[di]
	call	neiro_reset
endif

pauoff_exit:
	mov	[pause_flag],0
	mov	[play_flag],1
pauoff_exit2:
	ret

;==============================================================================
;	メモ文字列の取り出し
;==============================================================================
get_memo:
	mov	si,[mmlbuf]
	cmp	word ptr [si],1ah
	jnz	getmemo_errret	;音色がないfile=メモのアドレス取得不能
	add	si,18h
	mov	si,[si]
	add	si,[mmlbuf]
	sub	si,4
	mov	bx,2[si]		;bh=0feh,bl=ver
	cmp	bl,40h			;Ver4.0 & 00Hの場合
	jz	getmemo_exec
	cmp	bh,0feh
	jnz	getmemo_errret		;Ver.4.1以降は 0feh
	cmp	bl,41h
	jc	getmemo_errret		;MC version 4.1以前だったらError
getmemo_exec:
	cmp	bl,42h			;Ver.4.2以降か？
	jc	getmemo_oldver41
	inc	al			;ならalを +1 (0FFHで#PPSFile)
getmemo_oldver41:
	cmp	bl,48h			;Ver.4.8以降か？
	jc	getmemo_oldver47
	inc	al			;ならalを +1 (0FEHで#PPZFile)
getmemo_oldver47:

	mov	si,[si]
	add	si,[mmlbuf]
	inc	al

getmemo_loop:
	mov	dx,[si]
	test	dx,dx
	jz	getmemo_errret
	inc	si
	inc	si
	dec	al
	jnz	getmemo_loop

getmemo_exit:
	add	dx,[mmlbuf]
	mov	[ds_push],cs
	mov	[dx_push],dx
	ret

getmemo_errret:
	mov	[ds_push],0
	mov	[dx_push],0
	ret

;==============================================================================
;	曲の頭だし
;		input	DX <- 小節番号
;		output	AL <- return code	0:正常終了
;						1:その小節まで曲がない
;						2:曲が演奏されていない
;==============================================================================
ff_music:
	push	dx
	mov	dx,[mask_adr]
	pushf
	cli
	in	al,dx
	or	al,[mask_data]
	out	dx,al			;FM割り込みを禁止
	popf
	pop	dx

	call	ff_music_main
	mov	[al_push],al

	mov	dx,[mask_adr]
	pushf
	cli
	in	al,dx
	and	al,[mask_data2]
	out	dx,al			;FM割り込みを許可
	popf
	ret

ff_music_main:
	cmp	[status2],255
	jz	ffm_exit2

	mov	[skip_flag],1
	cmp	dx,[syousetu]
	jnbe	ffm_main

	mov	[skip_flag],2
	push	dx
	cmp	[effon],1
	jnz	ff_no_ssg_dr
	call	effend		;ssgdrums cut
ff_no_ssg_dr:
	call	data_init2
	call	play_init
	call	opn_init
	pop	dx

	test	dx,dx
	jnz	ffm_main
	call	silence
	jmp	ffm_exit0b

ffm_main:
	push	dx
	call	maskon_all
if	board2
	mov	dx,10ffh
	call	opnset44		;Rhythm音源を全部Dump
endif
	pop	dx

	mov	ah,[fadeout_volume]
	mov	al,[rhythmmask]
	mov	[fadeout_volume],255
	mov	[rhythmmask],0

	push	ax
	push	bp
	mov	bp,dx
ffm_loop:
	call	mmain
	call	syousetu_count
	cmp	[status2],255
	jz	ffm_exit1
	cmp	bp,[syousetu]
	jnbe	ffm_loop
	pop	bp
	pop	ax

	mov	[fadeout_volume],ah
	mov	[rhythmmask],al
if	board2
	test	ah,ah
	jnz	ffm_exit0
	mov	dl,[rhyvol]
	call	volset2rf
endif
ffm_exit0:
	call	maskoff_all
ffm_exit0b:
	mov	dl,[ff_tempo]
	dec	dl		;ffより1少ないtempo
	call	stb_ff
	xor	al,al
	jmp	ffm_exit
ffm_exit1:
	pop	bp
	pop	ax
	call	maskoff_all
	mov	al,1
	jmp	ffm_exit
ffm_exit2:
	mov	al,2
ffm_exit:
	mov	[skip_flag],0
	ret

;==============================================================================
;	全パート一時マスク
;==============================================================================
maskon_all:
	mov	si,offset part_table
	mov	cx,max_part1
	mov	di,offset part1
maskon_loop:
if	ppz
	lodsb
	cmp	al,-1
	jnz	monl_main
	add	si,6		;skip Rhythm & Effects(for PPZ parts)
monl_main:
else
	inc	si
endif
	lodsw			;ah=音源 al=partb
	or	partmask[di],80h
	cmp	partmask[di],80h
	jnz	maskon_next	;既に他でマスクされてた
	push	cx
	push	di
	push	si
	call	maskon_main	;1パートマスク
	pop	si
	pop	di
	pop	cx
maskon_next:
	add	di,type qq
	loop	maskon_loop
	ret

;==============================================================================
;	全パート一時マスク解除
;==============================================================================
maskoff_all:
	mov	si,offset part_table
	mov	cx,max_part1
	mov	di,offset part1
maskoff_loop:
if	ppz
	lodsb
	cmp	al,-1
	jnz	moffl_main
	add	si,6		;skip Rhythm & Effects(for PPZ parts)
moffl_main:
else
	inc	si
endif
	lodsw			;ah=音源 al=partb
	and	partmask[di],7fh
	jnz	maskoff_next	;まだ他でマスクされてる
	push	cx
	push	di
	push	si
	call	maskoff_main	;1パート復帰
	pop	si
	pop	di
	pop	cx
maskoff_next:
	add	di,type qq
	loop	maskoff_loop
	ret

;==============================================================================
;	パートのマスク & Keyoff
;==============================================================================
part_mask:
	mov	ah,al
	and	ah,7fh
if	ppz
	cmp	ah,16+8
else
	cmp	ah,16
endif
	jnc	pm_ret
	test	al,al
	js	part_on
	xor	bh,bh
	mov	bl,al
	add	bl,bl
	add	bl,al
	add	bx,offset part_table
	mov	dl,[bx]		;dl <- Part番号
	test	dl,dl
	js	rhythm_mask
	inc	bx
	mov	ax,[bx]		;AH=音源 AL=partb

	xor	bh,bh
	mov	bl,dl
	add	bx,bx
	add	bx,offset part_data_table
	mov	di,[bx]
	mov	dl,partmask[di]
	or	partmask[di],1
	test	dl,dl
	jnz	pm_ret		;既にマスクされていた
	cmp	[play_flag],0
	jz	pm_ret		;曲が止まっている

maskon_main:
	test	ah,ah
	jz	pm_fm1
	dec	ah
if	board2
	jz	pm_fm2
endif
	dec	ah
	jz	pm_ssg
	dec	ah
if	board2
	jz	pm_pcm
endif
	dec	ah
	jz	pm_drums
if	ppz
	dec	ah
	jz	pm_ppz
endif
pm_ret:
	ret
pm_fm1:
	pushf
	cli
	mov	[partb],al
if	board2
	call	sel44
endif
	call	silence_fmpart	;音を完璧に消す
	popf
	ret

if	board2
pm_fm2:
	pushf
	cli
	mov	[partb],al
	call	sel46
	call	silence_fmpart	;音を完璧に消す
	popf
	ret
endif

pm_drums:
	cmp	[psgefcnum],11
	jnc	pm_ssg_ret
	jmp	effend
pm_ssg:
	pushf
	cli
	mov	[partb],al
	call	psgmsk		;AL=07h AH=Maskdata
	mov	dh,7
	mov	dl,al
	or	dl,ah
	call	opnset44	;PSG keyoff
	popf
pm_ssg_ret:
	ret

if	board2
pm_pcm:
 if	adpcm
  if	ademu
	cmp	[adpcm_emulate],1
	jnz	pmpcm_noadpcm
	mov	ax,0207h
	call	ppz8_call	; PPZ8 ch7 発音停止
pmpcm_noadpcm:
  else
	pushf
	cli
	mov	dx,0102h	; PAN=0 / x8 bit mode
	call	opnset46
	mov	dx,0001h	; PCM RESET
	call	opnset46
	popf
  endif
 endif
 if	pcm
	call	stop_86pcm
 endif
	ret
endif
if	ppz
pm_ppz:
if	ademu
	cmp	al,7
	jnz	pmppz_exec
	cmp	[adpcm_emulate],1
	jz	pmppz_noexec
pmppz_exec:
endif
	mov	ah,2
	call	ppz8_call	;ppz stop (al=partb)
pmppz_noexec:
	ret
endif

rhythm_mask:
	mov	[rhythmmask],00h	;Rhythm音源をMask
if	board2
	mov	dx,10ffh
	call	opnset44		;Rhythm音源を全部Dump
endif
	ret

;==============================================================================
;	パートのマスク解除 & FM音源音色設定	in.AH=part番号
;==============================================================================
part_on:
	xor	bh,bh
	mov	bl,ah
	add	bl,bl
	add	bl,ah
	add	bx,offset part_table
	mov	dl,[bx]		;dl <- Part番号
	test	dl,dl
	js	rhythm_on
	inc	bx
	mov	ax,[bx]		;AH=音源 AL=partb

	xor	bh,bh
	mov	bl,dl
	add	bx,bx
	add	bx,offset part_data_table
	mov	di,[bx]
	cmp	partmask[di],0
	jz	po_ret		;マスクされてない
	and	partmask[di],0feh
	jnz	po_ret		;効果音でまだマスクされている
	cmp	[play_flag],0
	jz	po_ret		;曲が止まっている

maskoff_main:
	test	ah,ah
	jz	po_fm1	;FM音源の場合は
if	board2
	dec	ah
	jz	po_fm2	;音色設定処理
endif
po_ret:
	ret
po_fm1:
	mov	dl,voicenum[di]
	pushf
	cli
	mov	[partb],al
if	board2
	call	sel44
endif
	cmp	address[di],0
	jz	pof1_not_set
	call	neiro_reset
pof1_not_set:
	popf
	ret

if	board2
po_fm2:
	mov	dl,voicenum[di]
	pushf
	cli
	mov	[partb],al
	call	sel46
	cmp	address[di],0
	jz	pof2_not_set
	call	neiro_reset
pof2_not_set:
	popf
	ret
endif
rhythm_on:
	mov	[rhythmmask],0ffh	;Rhythm音源をMask解除
	ret

if	board2
 if	ppz
;			Part番号,Partb,音源番号
part_table	db	00,1,0	;A
		db	01,2,0	;B
		db	02,3,0	;C
		db	03,1,1	;D
		db	04,2,1	;E
		db	05,3,1	;F
		db	06,1,2	;G
		db	07,2,2	;H
		db	08,3,2	;I
		db	09,1,3	;J
		db	10,3,4	;K
		db	11,3,0	;c2
		db	12,3,0	;c3
		db	13,3,0	;c4
		db	-1,0,-1	;Rhythm
		db	22,3,1	;Effect
		db	14,0,5	;PPZ1
		db	15,1,5	;PPZ2
		db	16,2,5	;PPZ3
		db	17,3,5	;PPZ4
		db	18,4,5	;PPZ5
		db	19,5,5	;PPZ6
		db	20,6,5	;PPZ7
		db	21,7,5	;PPZ8
 else
;			Part番号,Partb,音源番号
part_table	db	00,1,0	;A
		db	01,2,0	;B
		db	02,3,0	;C
		db	03,1,1	;D
		db	04,2,1	;E
		db	05,3,1	;F
		db	06,1,2	;G
		db	07,2,2	;H
		db	08,3,2	;I
		db	09,1,3	;J
		db	10,3,4	;K
		db	11,3,0	;c2
		db	12,3,0	;c3
		db	13,3,0	;c4
		db	-1,0,-1	;Rhythm
		db	14,3,1	;Effect
 endif
else
;			Part番号,Partb,音源番号
part_table	db	00,1,0	;A
		db	01,2,0	;B
		db	02,3,0	;C
		db	03,3,0	;c2
		db	04,3,0	;c3
		db	05,3,0	;c4
		db	06,1,2	;G
		db	07,2,2	;H
		db	08,3,2	;I
		db	09,1,3	;J
		db	10,3,4	;K
		db	03,3,0	;c2
		db	04,3,0	;c3
		db	05,3,0	;c4
		db	-1,0,-1	;Rhythm
		db	11,3,0	;Effect
endif

;==============================================================================
;	ボードがない時
;==============================================================================
int60_start_not_board:

	cld

	push	es
	push	bx
	push	cx
	push	si
	push	di

	mov	bx,ds
	push	cs:[ds_push]
	mov	cs:[ds_push],bx

	mov	bx,cs
	mov	ds,bx
	mov	es,bx

	push	word ptr [ah_push]
	mov	[al_push],al
	mov	[ah_push],ah
	push	[dx_push]
	mov	[dx_push],dx

	add	ah,ah
	mov	bl,ah
	xor	bh,bh
	mov	si,n_int60_jumptable[bx]
	call	si

	mov	dx,[dx_push]
	mov	ax,[ds_push]
	mov	ds,ax
	mov	al,cs:[al_push]
	mov	ah,cs:[ah_push]

	pop	cs:[dx_push]
	pop	word ptr cs:[ah_push]
	pop	cs:[ds_push]

	pop	di
	pop	si
	pop	cx
	pop	bx
	pop	es

	jmp	int60_exit

n_int60_jumptable	label	word
	dw	nothing		;0
	dw	nothing		;1
	dw	nothing		;2
	dw	nothing		;3
	dw	nothing		;4
	dw	get_255		;5
	dw	get_musdat_adr	;6
	dw	get_tondat_adr	;7
	dw	get_255		;8
	dw	drv_chk2	;9
	dw	get_65535	;A
	dw	get_efcdat_adr	;B
	dw	nothing		;C
	dw	nothing		;D
	dw	get_pcm_adr	;E
	dw	nothing		;F
	dw	get_workadr	;10
	dw	get_255		;11
	dw	get_255		;12
	dw	nothing		;13
	dw	nothing		;14
	dw	get_65535	;15
	dw	get_65535	;16
	dw	get_255		;17
	dw	nothing		;18
	dw	nothing		;19
	dw	nothing		;1A
	dw	nothing		;1B
	dw	nothing		;1C
	dw	get_memo	;1D
	dw	nothing		;1E
	dw	get_fm_int	;1F
	dw	get_efc_int	;20
	dw	get_mus_name	;21
	dw	get_size	;22

get_255:
	mov	[al_push],255
nothing:
	ret
get_65535:
	mov	[ah_push],255
	jmp	get_255

drv_chk2:
	mov	ah,vers
	mov	al,verc
	mov	[ah_push],ah
	mov	[dx_push],ax
	jmp	get_255

;==============================================================================
;	ＦＭ効果音ルーチン
;==============================================================================

;==============================================================================
;	発音
;		input	AL to number_of_data
;==============================================================================
fm_effect_on:
	pushf
	cli
	cmp	[fm_effec_flag],0
	jz	not_e_flag

	push	ax
	call	fm_effect_off
	pop	ax

not_e_flag:
	mov	[fm_effec_num],al
	mov	[fm_effec_flag],1	; 効果音発声してね

	mov	[partb],3
ife	board2
	mov	di,offset part3
	or	partmask[di],2		; Part Mask
	mov	di,offset part3b
	or	partmask[di],2		; Part Mask
	mov	di,offset part3c
	or	partmask[di],2		; Part Mask
	mov	di,offset part3d
	or	partmask[di],2		; Part Mask
else
	mov	di,offset part6
	or	partmask[di],2		; Part Mask
endif

	xor	bh,bh
	mov	bl,[fm_effec_num]	; bx = effect no.
	mov	di,offset part_e
	mov	cx,type qq
	xor	al,al
rep	stosb				; PartData 初期化

	add	bx,bx
	add	bx,[efcdat]
	mov	ax,[bx]
	add	ax,[efcdat]

	mov	di,offset part_e
	mov	address[di],ax		; アドレスのセット
	mov	leng[di],1		; あと1カウントで演奏開始
	mov	volume[di],108		; FM  VOLUME DEFAULT= 108
	mov	slotmask[di],0f0h	; FM  SLOTMASK
	mov	neiromask[di],0ffh	; FM  Neiro MASK
if	board2
	mov	dl,0c0h
	mov	fmpan[di],dl		; FM PAN = Middle
	mov	dh,0b6h
	call	sel46			;ここでmmainが来てもsel46のまま
	call	opnset
else
	mov	al,[ch3mode]
	mov	[ch3mode_push],al
	mov	[ch3mode],3fh
endif

	popf
	ret

;==============================================================================
;	消音
;==============================================================================
fm_effect_off:
	pushf
	cli

	cmp	[fm_effec_flag],0
	jz	feo_ret

	mov	[fm_effec_num],-1
	mov	[fm_effec_flag],0	; 効果音止めてね

if	board2
	call	sel46			;ここでmmainが来てもsel46のまま
endif
	mov	di,offset part_e
	mov	[partb],3
	call	silence_fmpart

	cmp	[play_flag],0
	jz	feo_ret		;曲が止まっている

if	board2
	mov	di,offset part6
	mov	dl,voicenum[di]
	call	neiro_reset
else
	mov	di,offset part3
	mov	dl,voicenum[di]
	call	neiro_reset
	mov	di,offset part3b
	mov	dl,voicenum[di]
	call	neiro_reset
	mov	di,offset part3c
	mov	dl,voicenum[di]
	call	neiro_reset
	mov	di,offset part3d
	mov	dl,voicenum[di]
	call	neiro_reset

	mov	al,[ch3mode_push]
	mov	[ch3mode],al
	mov	dh,27h
	mov	dl,al
	and	dl,11001111b	;Resetはしない
	call	opnset44
endif
feo_ret:
	popf
	ret

;==============================================================================
;	PPZ8 Interrupt Routine (FMint割り込み中)
;==============================================================================
if	ppz
;;ppzint:	push	ds
;;	push	ax
;;	push	dx
;;	mov	ax,cs
;;	mov	ds,ax
;;	call	eoi_send	;EOIを送る
;;	call	dword ptr [ppz_call_ofs]
;;	pop	dx
;;	pop	ax
;;	pop	ds
;;	iret
endif

;==============================================================================
;	OPN Interrupt Routine
;==============================================================================
	even
if	vsync
	dw	0	;PMD86とPMD86Vで割り込みベクトルをずらす
endif
opnint:	
	cli
	cld
if	ppz
;;	cmp	cs:[int5_flag],0
;;	jnz	ppzint
endif
	inc	cs:[int5_flag]
	push	ax
	mov	cs:[ss_push],ss
	mov	cs:[sp_push],sp
	mov	ax,cs
	mov	ss,ax
	mov	sp,offset _stack-2
	push	dx
	push	ds
	mov	ds,ax

;------------------------------------------------------------------------------
;	8259/INT5をmask
;------------------------------------------------------------------------------
if	ppz
;;	cmp	[ppz_call_seg],2
;;	jnc	mask_skip
endif
	mov	dx,[mask_adr]
	in	al,dx
	jmp	$+2
	or	al,[mask_data]
	out	dx,al
mask_skip:

if	vsync
	jmp	$+2
	jmp	$+2
	in	al,2
	push	ax
	or	al,4
	out	2,al	;VSync STOP
endif

	call	eoi_send	;EOIを送る

;------------------------------------------------------------------------------
;	割り込みが入っているかどうかのcheck & 実行
;------------------------------------------------------------------------------
INT_check:

if	pcm
;------------------------------------------------------------------------------
;	FIFOをcheck
;------------------------------------------------------------------------------
	mov	dx,0a468h
	in	al,dx
	test	al,010h		;FIFO割り込みか？
	jz	not_fifo
	call	fifo_main
	jmp	INT_check	;最初からやりなおし
not_fifo:
endif

;------------------------------------------------------------------------------
;	PPZ8をcheck
;------------------------------------------------------------------------------
	_ppz

;------------------------------------------------------------------------------
;	TimerA/Bをcheck
;------------------------------------------------------------------------------
	mov	dx,[fm1_port1]
	rdychk
	and	al,3
	jz	opnint_fin	;Timer割り込みが来ていない
	call	FM_Timer_main
	jmp	INT_check	;最初からやりなおし

;------------------------------------------------------------------------------
;	OPN割り込み終了
;------------------------------------------------------------------------------
opnint_fin:
	cmp	[maskpush],0
	jnz	int5_no_fook

;------------------------------------------------------------------------------
;	常駐前に使用していたint5ルーチンを処理
;------------------------------------------------------------------------------
int5_fook:
	pushf
	call	dword ptr [int5ofs]
;------------------------------------------------------------------------------
;	Check Timer
;------------------------------------------------------------------------------
	mov	dx,[fm1_port1]
	rdychk
	and	al,3
	jnz	INT_check	;やりなおし
;------------------------------------------------------------------------------
;	Check FIFO
;------------------------------------------------------------------------------
if	pcm
	mov	dx,0a468h
	in	al,dx
	test	al,10h
	jnz	INT_check	;やりなおし
endif
int5_no_fook:
;------------------------------------------------------------------------------
;	割り込み禁止
;------------------------------------------------------------------------------
	cli

;------------------------------------------------------------------------------
;	8259/INT5 Mask解除
;------------------------------------------------------------------------------
if	vsync
	in	al,2
	pop	dx
	or	dl,11111011b
	and	al,dl
	out	2,al	;VSync 復帰
	jmp	$+2
endif
if	ppz
;;	cmp	[ppz_call_seg],2
;;	jnc	maskreset_skip
endif
	mov	dx,[mask_adr]
	in	al,dx
	jmp	$+2
	and	al,[mask_data2]
	out	dx,al
maskreset_skip:

;------------------------------------------------------------------------------
;	おしまい
;------------------------------------------------------------------------------
	pop	ds
	pop	dx
	mov	ss,cs:[ss_push]
	mov	sp,cs:[sp_push]
	pop	ax
	dec	cs:[int5_flag]
	iret

;==============================================================================
;	EOIを送る
;==============================================================================
eoi_send:
	mov	dx,[eoi_adr]
	mov	al,[eoi_data]
	out	dx,al		;(特殊EOI)FM音源のINTのみEOI

	cmp	dx,ms_cmd	;Masterだったら
	jz	eoi_1		;SlaveのISRを調べない
	mov	al,0bh
	mov	dx,sl_cmd
	out	dx,al
	jmp	$+2
	in	al,dx		;SlaveのISRを読む
	test	al,al
	jnz	eoi_1		;Slaveにサービス中の割り込みが残っている
	mov	dx,ms_cmd
	mov	al,67h		;Master をEOI
	out	dx,al
eoi_1:	ret

;==============================================================================
;	FM TimerA/B 処理 Main
;		*Timerが来ている事を確認してから飛んで来ること。
;		 pushしてあるレジスタは ax/dx/ds のみ。
;==============================================================================
FM_Timer_main:
	push	cx
;------------------------------------------------------------------------------
;	Timer Reset
;	同時にＦＭ割り込み Timer AorB どちらが来たかを読み取る
;------------------------------------------------------------------------------
	mov	dx,[fm1_port1]
	rdychk
	mov	al,27h
	out	dx,al
	_wait
	mov	ah,[ch3mode]	;ah = 27hに出力する値
	in	al,dx	;rdychk	;al = status
	xchg	ah,al		;ah = status / al=27hに出力する値
	mov	dx,[fm1_port2]
	out	dx,al		;Timer Reset

	and	ah,3		;ah = TimerA/B flag

;------------------------------------------------------------------------------
;	割り込み許可
;------------------------------------------------------------------------------
	cmp	[disint],1
	jz	not_sti
	sti
not_sti:

;------------------------------------------------------------------------------
;	どちらが来たかで場合分け処理
;------------------------------------------------------------------------------
	push	bx
	push	si
	push	di
	push	es

	mov	bx,cs
	mov	es,bx

	dec	ah		;Timer Aか？
	jz	TimerA_int	;Timer Aの方を処理
	dec	ah		;Timer Bか？
	jz	TimerB_int	;Timer Bの方を処理

	call	TimerB_main	;同時
TimerA_int:
	call	TimerA_main
	jmp	exit_Timer

TimerB_int:
	call	TimerB_main
exit_Timer:
	pop	es
	pop	di
	pop	si
	pop	bx
	pop	cx
	cli
	ret

;==============================================================================
;	TimerBの処理[メイン]
;==============================================================================
TimerB_main:
if	sync
	ret
opnint_sub:
endif
	mov	[TimerBflag],1

	cmp	[music_flag],0
	jz	not_mstop

	test	[music_flag],1
	jz	not_mstart
	call	mstart
not_mstart:
	test	[music_flag],2
	jz	not_mstop
	call	mstop
not_mstop:

	cmp	[play_flag],0
	jz	not_play

	call	mmain
	call	settempo_b
	call	syousetu_count
	mov	al,[TimerAtime]
	mov	[lastTimerAtime],al
not_play:
	mov	[TimerBflag],0

	test	[intfook_flag],1
	jz	TimerB_nojump
	call	dword ptr [fmint_ofs]
TimerB_nojump:
	ret

;==============================================================================
;	TimerAの処理[メイン]
;==============================================================================
TimerA_main:
	mov	[TimerAflag],1

	inc	[TimerAtime]

	mov	al,[TimerAtime]
	and	al,7
	jnz	not_fade
	call	fadeout		;Fadeout処理
	call	rew		;Rew処理

not_fade:
	cmp	[effon],0
	jz	not_psgeffec
	cmp	[ppsdrv_flag],0
	jz	ta_not_ppsdrv
	test	[psgefcnum],80h
	jnz	not_psgeffec	;ppsdrvの方で鳴らしている
ta_not_ppsdrv:
	call	effplay		;SSG効果音処理

not_psgeffec:
	cmp	[fm_effec_flag],0
	jz	not_fmeffec
	call	fm_efcplay	;FM効果音処理
not_fmeffec:

	cmp	[key_check],0
	jz	vtc000
	cmp	[play_flag],0
	jz	vtc000

if	va
	in	al,8
	mov	ah,[esc_sp_key]
	test	ah,al
	jnz	vtc000
	in	al,9
	test	al,10000000b
	jnz	vtc000
else
	xor	ax,ax
	mov	es,ax
	mov	bx,052ah
	mov	al,[esc_sp_key]
	and	al,byte ptr es:0eh[bx]
	cmp	al,[esc_sp_key]
	jnz	vtc000
	test	byte ptr es:[bx],00000001b	;esc
	jz	vtc000
	mov	ax,cs
	mov	es,ax
endif
	or	[music_flag],2		;次のTimerBでMSTOP
	mov	[fadeout_flag],0	;CTRL+ESCで止めた=外部扱い
vtc000:
	mov	[TimerAflag],0

	test	[intfook_flag],2
	jz	TimerA_nojump
	call	dword ptr [efcint_ofs]
TimerA_nojump:
	ret

;==============================================================================
;	小節のカウント
;==============================================================================
syousetu_count:
	mov	al,[opncount]
	inc	al
	cmp	al,[syousetu_lng]
	jnz	sc_ret
	xor	al,al
	inc	[syousetu]
sc_ret:	mov	[opncount],al
	ret

;==============================================================================
;	テンポ設定
;==============================================================================
settempo_b:
	mov	ah,[grph_sp_key]
	call	check_grph
	jnc	stb_n
	mov	dl,[ff_tempo]
	jmp	stb_ff

stb_n:	mov	dl,[tempo_d]
stb_ff:	cmp	dl,[TimerB_speed]
	jz	stb_ret
	mov	[TimerB_speed],dl
	mov	dh,26h
	jmp	opnset44

stb_ret:
	ret

;==============================================================================
;	巻き戻し処理
;==============================================================================
rew:	mov	ah,[rew_sp_key]
	call	check_grph
	jnc	rew_ret

	mov	dx,[syousetu]
	mov	al,[syousetu_lng]
	shr	al,1
	shr	al,1
	cmp	[opncount],al
	jnc	ff_music_main
	test	dx,dx
	jz	ff_music_main
	dec	dx
	jmp	ff_music_main

rew_ret:
	ret

;==============================================================================
;	GRPH key check
;		in	AH	sp_key
;		out	CY	1で押されている
;==============================================================================
check_grph:
	cmp	[key_check],0	;cy=0
	jnz	cgr_main
	ret

cgr_main:
if	va
	in	al,8
	test	ah,al		;cy=0
	jnz	cgr_ret
	test	al,00010000b	;cy=0
	jnz	cgr_ret
	stc
cgr_ret:
	ret
else
	mov	cx,es
	xor	bx,bx
	mov	es,bx
	mov	bx,052ah+0eh
	mov	al,ah
	and	al,byte ptr es:[bx]
	cmp	al,ah
	jnz	cgr_ret
	test	byte ptr es:[bx],00001000b	;grph
	jz	cgr_ret
	mov	es,cx
	stc
	ret
cgr_ret:
	mov	es,cx
	clc
	ret
endif

;==============================================================================
;	ｵﾝｶｲ DATA
;==============================================================================
fnum_data	label	word

	dw	026ah	; C
	dw	028fh	; D-
	dw	02b6h	; D
	dw	02dfh	; E-
	dw	030bh	; E
	dw	0339h	; F
	dw	036ah	; G-
	dw	039eh	; G
	dw	03d5h	; A-
	dw	0410h	; A
	dw	044eh	; B-
	dw	048fh	; B

psg_tune_data	label	word

	dw	0ee8h	; C
	dw	0e12h	; D-
	dw	0d48h	; D
	dw	0c89h	; E-
	dw	0bd5h	; E
	dw	0b2bh	; F
	dw	0a8ah	; G-
	dw	09f3h	; G
	dw	0964h	; A-
	dw	08ddh	; A
	dw	085eh	; B-
	dw	07e6h	; B

;==============================================================================
;	ＦＭ音色のキャリアのテーブル
;==============================================================================
carrier_table	label	byte
	db	10000000b,10000000b,10000000b,10000000b
	db	10100000b,11100000b,11100000b,11110000b

	db	11101110b,11101110b,11101110b,11101110b
	db	11001100b,10001000b,10001000b,00000000b

;==============================================================================
;	効果音データ　ＩＮＣＬＵＤＥ
;==============================================================================
efftbl		label	word
	include effect.inc
efftblend	label	word

;==============================================================================
;	WORK AREA
;==============================================================================
fm_port1	dw	?		;FM音源 I/O port work (1)
fm_port2	dw	?		;FM音源 I/O port work (2)
ds_push		dw	?		;INT60用 ds push
dx_push		dw	?		;INT60用 dx push
ah_push		db	?		;INT60用 ah push
al_push		db	?		;INT60用 al push
partb		db	?		;処理中パート番号
tieflag		db	?		;&のフラグ
volpush_flag	db	?		;次の１音音量down用のflag
rhydmy		db	?		;R part ダミー演奏データ
fmsel		db	?		;FM 表か裏か　flag
omote_key1	db	?		;FM keyondata表1
omote_key2	db	?		;FM keyondata表2
omote_key3	db	?		;FM keyondata表3
ura_key1	db	?		;FM keyondata裏1
ura_key2	db	?		;FM keyondata裏2
ura_key3	db	?		;FM keyondata裏3
loop_work	db	?		;Loop Work
ppsdrv_flag	db	?		;ppsdrv flag
prgdat_adr2	dw	?		;曲データ中音色データ先頭番地(効果音用)
pcmrepeat1	dw	?		;PCMのリピートアドレス1
pcmrepeat2	dw	?		;PCMのリピートアドレス2
pcmrelease	dw	?		;PCMのRelease開始アドレス
lastTimerAtime	db	?		;一個前の割り込み時のTimerATime値
music_flag	db	?		;B0:次でMSTART 1:次でMSTOP のFlag
slotdetune_flag	db	?		;FM3 Slot Detuneを使っているか
slot3_flag	db	?		;FM3 Slot毎 要効果音モードフラグ
eoi_adr		dw	?		;EOIをsendするI/Oアドレス
eoi_data	db	?		;EOI用のデータ
mask_adr	dw	?		;MaskをするI/Oアドレス
mask_data	db	?		;Mask用のデータ(OrでMask)
mask_data2	db	?		;Mask用のデータ(AndでMask解除)
ss_push		dw	?		;FMint中 SSのpush
sp_push		dw	?		;FMint中 SPのpush
fm3_alg_fb	db	?		;FM3chの最後に定義した音色のalg/fb
af_check	db	?		;FM3chのalg/fbを設定するかしないかflag
ongen		db	?		;音源 0=無し/2203 1=2608
lfo_switch	db	?		;局所LFOスイッチ

rhydat:					;ドラムス用リズムデータ
	;	PT  PAN/VOLUME	KEYON
	db	18h,11011111b,	00000001b	;バス
	db	19h,11011111b,	00000010b	;スネア
	db	1ch,01011111b,	00010000b	;タム[LOW]
	db	1ch,11011111b,	00010000b	;タム[MID]
	db	1ch,10011111b,	00010000b	;タム[HIGH]
	db	1dh,11010011b,	00100000b	;リム
	db	19h,11011111b,	00000010b	;クラップ
	db	1bh,10011100b,	10001000b	;Cハイハット
	db	1ah,10011101b,	00000100b	;Oハイハット
	db	1ah,11011111b,	00000100b	;シンバル
	db	1ah,01011110b,	00000100b	;RIDEシンバル

	even
;	
open_work	label	byte
mmlbuf		dw	?		;Musicdataのaddress+1
tondat		dw	?		;Voicedataのaddress
efcdat		dw	?		;FM  Effecdataのaddress
fm1_port1	dw	?		;FM音源 I/O port (表1)
fm1_port2	dw	?		;FM音源 I/O port (表2)
fm2_port1	dw	?		;FM音源 I/O port (裏1)
fm2_port2	dw	?		;FM音源 I/O port (裏2)
fmint_ofs	dw	?		;FM割り込みフックアドレス offset
fmint_seg	dw	?		;FM割り込みフックアドレス address
efcint_ofs	dw	?		;効果音割り込みフックアドレス offset
efcint_seg	dw	?		;効果音割り込みフックアドレス address
prgdat_adr	dw	?		;曲データ中音色データ先頭番地
radtbl		dw	?		;R part offset table 先頭番地
rhyadr		dw	?		;R part 演奏中番地
rhythmmask	db	?		;Rhythm音源のマスク x8c/10hのbitに対応
board		db	?		;FM音源ボードあり／なしflag
key_check	db	?		;ESC/GRPH key Check flag
fm_voldown	db	?		;FM voldown 数値
ssg_voldown	db	?		;PSG voldown 数値
pcm_voldown	db	?		;PCM voldown 数値
rhythm_voldown	db	?		;RHYTHM voldown 数値
prg_flg		db	?		;曲データに音色が含まれているかflag
x68_flg		db	?		;OPM flag
status		db	?		;status1
status2		db	?		;status2
tempo_d		db	?		;tempo (TIMER-B)
fadeout_speed	db	?		;Fadeout速度
fadeout_volume	db	?		;Fadeout音量
tempo_d_push	db	?		;tempo (TIMER-B) / 保存用
syousetu_lng	db	?		;小節の長さ
opncount	db	?		;最短音符カウンタ
TimerAtime	db	?		;TimerAカウンタ
effflag		db	?		;PSG効果音発声on/off flag
psnoi		db	?		;PSG noise周波数
psnoi_last	db	?		;PSG noise周波数(最後に定義した数値)
fm_effec_num	db	?		;発声中のFM効果音番号
fm_effec_flag	db	?		;FM効果音発声中flag (1)
disint		db	?		;FM割り込み中に割り込みを禁止するかflag
pcmflag		db	?		;PCM効果音発声中flag
pcmstart	dw	?		;PCM音色のstart値
pcmstop		dw	?		;PCM音色のstop値
pcm_effec_num	db	?		;発声中のPCM効果音番号
_pcmstart	dw	?		;PCM効果音のstart値
_pcmstop	dw	?		;PCM効果音のstop値
_voice_delta_n	dw	?		;PCM効果音のdelta_n値
_pcmpan		db	?		;PCM効果音のpan
_pcm_volume	db	?		;PCM効果音のvolume
rshot_dat	db	?		;リズム音源 shot flag
rdat		db	6 dup (?)	;リズム音源 音量/パンデータ
rhyvol		db	00111100b	;リズムトータルレベル
kshot_dat	dw	?		;ＳＳＧリズム shot flag
ssgefcdat	dw	efftbl		;PSG Effecdataのaddress
ssgefclen	dw	efftblend-efftbl;PSG Effecdataの長さ
play_flag	db	?		;play flag
pause_flag	db	?		;pause flag
fade_stop_flag	db	0		;Fadeout後 MSTOPするかどうかのフラグ
kp_rhythm_flag	db	?		;K/RpartでRhythm音源を鳴らすかflag
TimerBflag	db	0		;TimerB割り込み中？フラグ
TimerAflag	db	0		;TimerA割り込み中？フラグ
int60flag	db	0		;INT60H割り込み中？フラグ
int60_result	db	0		;INT60Hの実行ErrorFlag
pcm_gs_flag	db	?		;ADPCM使用 許可フラグ (0で許可)
esc_sp_key	db	?		;ESC +?? Key Code
grph_sp_key	db	?		;GRPH+?? Key Code
rescut_cant	db	?		;常駐解除禁止フラグ
slot_detune1	dw	?		;FM3 Slot Detune値 slot1
slot_detune2	dw	?		;FM3 Slot Detune値 slot2
slot_detune3	dw	?		;FM3 Slot Detune値 slot3
slot_detune4	dw	?		;FM3 Slot Detune値 slot4
wait_clock	dw	?		;FM ADDRESS-DATA間 Loop $の回数
wait1_clock	dw	?		;loop $ １個の速度
ff_tempo	db	?		;早送り時のTimerB値
pcm_access	db	0		;PCMセット中は 1
TimerB_speed	db	?		;TimerBの現在値(=ff_tempoならff中)
fadeout_flag	db	?		;内部からfoutを呼び出した時1
adpcm_wait	db	?		;ADPCM定義の速度
revpan		db	?		;PCM86逆走flag
pcm86_vol	db	?		;PCM86の音量をSPBに合わせるか?
syousetu	dw	?		;小節カウンタ
int5_flag	db	0		;FM音源割り込み中？フラグ
port22h		db	0		;OPN-PORT 22H に最後に出力した値(hlfo)
tempo_48	db	?		;現在のテンポ(clock=48 tの値)
tempo_48_push	db	?		;現在のテンポ(同上/保存用)
rew_sp_key	db	?		;GRPH+?? (rew) Key Code
intfook_flag	db	?		;int_fookのflag B0:TB B1:TA
skip_flag	db	?		;normal:0 前方SKIP中:1 後方SKIP中:2
_fm_voldown	db	?		;FM voldown 数値 (保存用)
_ssg_voldown	db	?		;PSG voldown 数値 (保存用)
_pcm_voldown	db	?		;PCM voldown 数値 (保存用)
_rhythm_voldown	db	?		;RHYTHM voldown 数値 (保存用)
_pcm86_vol	db	?		;PCM86の音量をSPBに合わせるか? (保存用)
mstart_flag	db	0		;mstartする時に１にするだけのflag
mus_filename	db	13 dup(0)	;曲のFILE名バッファ
mmldat_lng	db	?		;曲データバッファサイズ(KB)
voicedat_lng	db	?		;音色データバッファサイズ(KB)
effecdat_lng	db	?		;効果音データバッファサイズ(KB)
rshot_bd	db	?		;リズム音源 shot inc flag (BD)
rshot_sd	db	?		;リズム音源 shot inc flag (SD)
rshot_sym	db	?		;リズム音源 shot inc flag (CYM)
rshot_hh	db	?		;リズム音源 shot inc flag (HH)
rshot_tom	db	?		;リズム音源 shot inc flag (TOM)
rshot_rim	db	?		;リズム音源 shot inc flag (RIM)
rdump_bd	db	?		;リズム音源 dump inc flag (BD)
rdump_sd	db	?		;リズム音源 dump inc flag (SD)
rdump_sym	db	?		;リズム音源 dump inc flag (CYM)
rdump_hh	db	?		;リズム音源 dump inc flag (HH)
rdump_tom	db	?		;リズム音源 dump inc flag (TOM)
rdump_rim	db	?		;リズム音源 dump inc flag (RIM)
ch3mode		db	?		;ch3 Mode
ch3mode_push	db	?		;ch3 Mode(効果音発音時用push領域)
ppz_voldown	db	?		;PPZ8 voldown 数値
_ppz_voldown	db	?		;PPZ8 voldown 数値 (保存用)
ppz_call_ofs	dw	?		;PPZ8call用 far call address
ppz_call_seg	dw	?		;seg値はPPZ8常駐checkを兼ねる,0で非常駐
p86_freq	db	8		;PMD86のPCM再生周波数
if	pcm*board2
p86_freqtable	dw	offset pcm_tune_data
else
p86_freqtable	dw	0		;PMD86のPCM再生周波数table位置
endif
adpcm_emulate	db	0		;PMDPPZEでADPCMエミュレート中か

;	演奏中のデータエリア

qq	struc
address		dw	?	; 2 ｴﾝｿｳﾁｭｳ ﾉ ｱﾄﾞﾚｽ
partloop	dw	?       ; 2 ｴﾝｿｳ ｶﾞ ｵﾜｯﾀﾄｷ ﾉ ﾓﾄﾞﾘｻｷ
leng		db	?       ; 1 ﾉｺﾘ LENGTH
qdat		db	?       ; 1 gatetime (q/Q値を計算した値)
fnum		dw	?       ; 2 ｴﾝｿｳﾁｭｳ ﾉ BLOCK/FNUM
detune		dw	?       ; 2 ﾃﾞﾁｭｰﾝ
lfodat		dw	?       ; 2 LFO DATA
porta_num	dw	?	; 2 ポルタメントの加減値（全体）
porta_num2	dw	?	; 2 ポルタメントの加減値（一回）
porta_num3	dw	?	; 2 ポルタメントの加減値（余り）
volume		db	?       ; 1 VOLUME
shift		db	?       ; 1 ｵﾝｶｲ ｼﾌﾄ ﾉ ｱﾀｲ
delay		db	?       ; 1 LFO	[DELAY] 
speed		db	?       ; 1	[SPEED]
step		db	?       ; 1	[STEP]
time		db	?       ; 1	[TIME]
delay2		db	?       ; 1	[DELAY_2]
speed2		db	?       ; 1	[SPEED_2]
step2		db	?       ; 1	[STEP_2]
time2		db	?       ; 1	[TIME_2]
lfoswi		db	?       ; 1 LFOSW. B0/tone B1/vol B2/同期 B3/porta
				;          B4/tone B5/vol B6/同期
volpush		db	? 	; 1 Volume PUSHarea
mdepth		db	?	; 1 M depth
mdspd		db	?	; 1 M speed
mdspd2		db	?	; 1 M speed_2
envf		db	?       ; 1 PSG ENV. [START_FLAG] / -1でextend
eenv_count	db	?	; 1 ExtendPSGenv/No=0 AR=1 DR=2 SR=3 RR=4
eenv_ar		db	?	; 1 		/AR		/旧pat
eenv_dr		db	?	; 1		/DR		/旧pv2
eenv_sr		db	?	; 1		/SR		/旧pr1
eenv_rr		db	?	; 1		/RR		/旧pr2
eenv_sl		db	?	; 1		/SL
eenv_al		db	?	; 1		/AL
eenv_arc	db	?	; 1		/ARのカウンタ	/旧patb
eenv_drc	db	?	; 1		/DRのカウンタ
eenv_src	db	?	; 1		/SRのカウンタ	/旧pr1b
eenv_rrc	db	?	; 1		/RRのカウンタ	/旧pr2b
eenv_volume	db	?	; 1		/Volume値(0～15)/旧penv
extendmode	db	?	; 1 B1/Detune B2/LFO B3/Env Normal/Extend
fmpan		db	? 	; 1 FM Panning + AMD + PMD
psgpat		db	?       ; 1 PSG PATTERN [TONE/NOISE/MIX]
voicenum	db	?	; 1 音色番号
loopcheck	db	?	; 1 ループしたら１ 終了したら３
carrier		db	?	; 1 FM Carrier
slot1		db	?       ; 1 SLOT 1 ﾉ TL
slot3		db	?       ; 1 SLOT 3 ﾉ TL
slot2		db	?       ; 1 SLOT 2 ﾉ TL
slot4		db	?       ; 1 SLOT 4 ﾉ TL
slotmask	db	?	; 1 FM slotmask
neiromask	db	?	; 1 FM 音色定義用maskdata
lfo_wave	db	?	; 1 LFOの波形
partmask	db	?	; 1 PartMask b0:通常 b1:効果音 b2:NECPCM用
				;   b3:none b4:PPZ/ADE用 b5:s0時 b6:m b7:一時
keyoff_flag	db	?	; 1 KeyoffしたかどうかのFlag
volmask		db	?	; 1 音量LFOのマスク
qdata		db	?	; 1 qの値
qdatb		db	?	; 1 Qの値
hldelay		db	?	; 1 HardLFO delay
hldelay_c	db	?	; 1 HardLFO delay Counter
_lfodat		dw	?       ; 2 LFO DATA
_delay		db	?       ; 1 LFO	[DELAY] 
_speed		db	?       ; 1	[SPEED]
_step		db	?       ; 1	[STEP]
_time		db	?       ; 1	[TIME]
_delay2		db	?       ; 1	[DELAY_2]
_speed2		db	?       ; 1	[SPEED_2]
_step2		db	?       ; 1	[STEP_2]
_time2		db	?       ; 1	[TIME_2]
_mdepth		db	?	; 1 M depth
_mdspd		db	?	; 1 M speed
_mdspd2		db	?	; 1 M speed_2
_lfo_wave	db	?	; 1 LFOの波形
_volmask	db	?	; 1 音量LFOのマスク
mdc		db	?	; 1 M depth Counter (変動値)
mdc2		db	?	; 1 M depth Counter
_mdc		db	?	; 1 M depth Counter (変動値)
_mdc2		db	?	; 1 M depth Counter
onkai		db	?	; 1 演奏中の音階データ (0ffh:rest)
sdelay		db	?	; 1 Slot delay
sdelay_c	db	?	; 1 Slot delay counter
sdelay_m	db	?	; 1 Slot delay Mask
alg_fb		db	?	; 1 音色のalg/fb
keyon_flag	db	?	; 1 新音階/休符データを処理したらinc
qdat2		db	?	; 1 q 最低保証値
fnum2		dw	?	; 2 ppz8/pmd86用fnum値上位
onkai_def	db	?	; 1 演奏中の音階データ (転調処理前 / ?fh:rest)
shift_def	db	?	; 1 マスター転調値
qdat3		db	?	; 1 q Random
		db	?	; dummy
qq	ends

qqq	struc
		db	offset eenv_ar dup(?)
pat		db	?	; 1 旧SSGENV	/Normal pat
pv2		db	?	; 1		/Normal pv2
pr1		db	?	; 1		/Normal pr1
pr2		db	?	; 1		/Normal pr2
		db	?
		db	?
patb		db	?	; 1		/Normal patb
		db	?
pr1b		db	?	; 1		/Normal pr1b
pr2b		db	?	; 1		/Normal pr2b
penv		db	?	; 1		/Normal penv
qqq	ends

if	board2
 if	ppz
max_part1	equ	14+8	;０クリアすべきパート数
max_part2	equ	11	;初期化すべきパート数
 else
max_part1	equ	14	;０クリアすべきパート数
max_part2	equ	11	;初期化すべきパート数
 endif
else
max_part1	equ	11
max_part2	equ	11
endif
fm		equ	0
fm2		equ	1
psg		equ	2
rhythm		equ	3

	even

	dw	open_work
part_data_table:
	dw	part1
	dw	part2
	dw	part3
if	board2
	dw	part4
	dw	part5
	dw	part6
else
	dw	part3b
	dw	part3c
	dw	part3d
endif
	dw	part7
	dw	part8
	dw	part9
	dw	part10
	dw	part11
if	board2
	dw	part3b
	dw	part3c
	dw	part3d
endif
if	ppz
	dw	part10a
	dw	part10b
	dw	part10c
	dw	part10d
	dw	part10e
	dw	part10f
	dw	part10g
	dw	part10h
endif
	dw	part_e

part1	db	type qq dup( ? )
part2	db	type qq dup( ? )
part3	db	type qq dup( ? )
if	board2
part4	db	type qq dup( ? )
part5	db	type qq dup( ? )
part6	db	type qq dup( ? )
else
part3b	db	type qq dup( ? )
part3c	db	type qq dup( ? )
part3d	db	type qq dup( ? )
endif
part7	db	type qq dup( ? )
part8	db	type qq dup( ? )
part9	db	type qq dup( ? )
part10	db	type qq dup( ? )
part11	db	type qq dup( ? )
if	board2
part3b	db	type qq dup( ? )
part3c	db	type qq dup( ? )
part3d	db	type qq dup( ? )
endif
if	ppz
part10a	db	type qq dup( ? )
part10b	db	type qq dup( ? )
part10c	db	type qq dup( ? )
part10d	db	type qq dup( ? )
part10e	db	type qq dup( ? )
part10f	db	type qq dup( ? )
part10g	db	type qq dup( ? )
part10h	db	type qq dup( ? )
endif
part_e	db	type qq dup( ? )

	even
pcm_table	label	word
if	board2
 if	adpcm
  ife	ademu
pcmends		dw	26H	;最初のstartは26Hから
pcmadrs		dw	2*256 dup (0)
pcmfilename	db	128 dup(0)
  endif
 endif
 if	pcm
pcmst_ofs	dw	0
pcmst_seg	dw	0
pcmadrs		db	6*256 dup (0)
 endif
endif
		db	"This is the STACK area. "
		db  "Thank you very much for those who always use PMD (^^). "
		db  "If you find something that looks like a bug, "
		db	"it's okay if it's trivial, so please let me know and give it a shot (^^)."
		db  " → PMDBBS [03(3395)9600] @PMD board by KAJA."
_stack:
dataarea	label	word
		db	0		;
		dw	12 dup (18h)	; 初期データ
		db	80h		;

;==============================================================================
;	常駐終了シーケンス(非常駐部先頭位置に移動)
;==============================================================================
resident_exit_end:
	push	dx

	mov	ax,cs
	mov	es,ax
;	音色エリアの初期化
	cmp	[voicedat_lng],0
	jz	not_vinit
	mov	di,[tondat]
	xor	cl,cl
	mov	ch,[voicedat_lng]
	shl	cx,1
	xor	ax,ax
rep	stosw
not_vinit:

;	Init Effect Data
	cmp	[effecdat_lng],0
	jz	not_einit
	mov	di,[efcdat]
	mov	ax,0100h
	mov	cx,128
rep	stosw
	mov	byte ptr [di],80h
not_einit:

	pop	dx
	resident_exit

;==============================================================================
;	ＰＭＤコマンドスタート
;==============================================================================
comstart:
ife	va
	include	virus.inc		;ウイルスcheck
	jmp	coms_main
myname	db	_myname
coms_main:
endif
	cld
	push	ds

	mov	ax,cs
	mov	ds,ax
	print_mes	mes_title	;タイトル表示

	pop	ds

	mov	cs:[opt_sp_push],0

;==============================================================================
;	ＰＭＤ常駐CHECK
;==============================================================================
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]	;ES = PMD seg

	cmp	word ptr es:_p[bx],"MP"
	jnz	resident_main
	cmp	byte ptr es:_d[bx],"D"
	jnz	resident_main

	push	ds
	mov	ah,10h
	int	60h
	mov	si,dx
	mov	si,-2[si]
	cmp	byte ptr es:[si+(board-open_work)],0
	pop	ds
	jz	change_main

;	常駐していた/音源有りの時は FMint vectorがopnint:と同一かどうかcheck
	mov	si,es:_vector[bx]
	push	ds
	xor	ax,ax
	mov	ds,ax
	mov	ax,ds:[si]
	pop	ds
	cmp	ax,offset opnint
	jz	change_main	;(ES=PMD seg)

	jmp	pmderr_1	;常駐時とFM割り込みベクトルが違う

;==============================================================================
;	常駐処理
;==============================================================================
resident_main:
;==============================================================================
;	オプション初期設定
;==============================================================================
	push	ds
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	xor	ax,ax

	mov	[mmldat_lng],mdata_def		;Default 16K
	mov	[voicedat_lng],voice_def	;Default 8K
	mov	[effecdat_lng],effect_def	;Default 4K
	mov	[key_check],key_def		;Keycheck ON
	mov	[fm_voldown],fmvd_init	;FM_VOLDOWN
	mov	[_fm_voldown],fmvd_init	;FM_VOLDOWN
	mov	[ssg_voldown],al	;SSG_VOLDOWN
	mov	[_ssg_voldown],al	;SSG_VOLDOWN
	mov	[pcm_voldown],al	;PCM_VOLDOWN
	mov	[_pcm_voldown],al	;PCM_VOLDOWN
	mov	[ppz_voldown],al	;PPZ_VOLDOWN
	mov	[_ppz_voldown],al	;PPZ_VOLDOWN
	mov	[rhythm_voldown],al	;RHYTHM_VOLDOWN
	mov	[_rhythm_voldown],al	;RHYTHM_VOLDOWN
	mov	[kp_rhythm_flag],-1	;SSGDRUMでRHYTHM音源を鳴らすか FLAG

	mov	di,offset rshot_bd
	mov	cx,6
rep	stosw

	mov	di,offset part1
	mov	cx,max_part1 * type qq
rep	stosb

	mov	[disint],al		;INT Disable FLAG
	mov	[rescut_cant],al	;常駐解除禁止 FLAG
	mov	[adpcm_wait],al		;ADPCM定義速度
	mov	[pcm86_vol],al		;PCM音量合わせ
	mov	[_pcm86_vol],al		;PCM音量合わせ
	mov	[fade_stop_flag],1	;FADEOUT後MSTOPするか FLAG
	mov	[ppsdrv_flag],-1	;PPSDRV FLAG
if	va
	mov	[grph_sp_key],80h	;GRPH+CTRL key code
	mov	[rew_sp_key],40h	;GPPH+SHIFTkey code
	mov	[esc_sp_key],80h	;ESC +CTRL key code
else
	mov	[grph_sp_key],10h	;GRPH+CTRL key code
	mov	[rew_sp_key],1		;GPPH+SHIFTkey code
	mov	[esc_sp_key],10h	;ESC +CTRL key code
	mov	[port_sel],-1		;ポート選択 = 自動
endif
	mov	[ff_tempo],250
	mov	[music_flag],al
	mov	[message_flag],1

;==============================================================================
;	ＦＭ音源のcheck (INT/PORT選択)
;==============================================================================
	cli
	call	fm_check
	sti

	pop	ds	; DS = PSP segment

;==============================================================================
;	オプションを取り込む
;==============================================================================
	push	ds

	mov	es,ds:[2ch]
	mov	si,offset pmdopt_txt
	call	search_env		;"PMDOPT=" 検索
	jc	no_user

	mov	si,di
	mov	ax,es
	mov	ds,ax		;ds:si=環境変数位置
	mov	ax,cs
	mov	es,ax

	mov	bx,offset resident_option
	call	_set_option
	jmp	no_user

_set_option:
	mov	cs:[opt_sp_push],sp
	call	set_option
	mov	cs:[opt_sp_push],0
	ret

no_user:
	mov	ax,cs
	mov	es,ax	; ES = Code segment
	pop	ds
	mov	si,offset 80h

	cmp	byte ptr [si],0
	jz	resmes_set		;オプション無し
	inc	si			;ds:si = command line

	mov	bx,offset resident_option
	call	set_option

	mov	al,es:[mmldat_lng]
	cmp	al,1
	jc	pmderr_2
	add	al,es:[voicedat_lng]
	jc	pmderr_3
	add	al,es:[effecdat_lng]
	jc	pmderr_3
	cmp	al,40+1
	jnc	pmderr_3

;==============================================================================
;	vmapエリアに"PMD"文字列書込み
;==============================================================================
resmes_set:
	mov	ax,ds
	mov	es,ax	;ES = PSP  segment
	mov	ax,cs
	mov	ds,ax	;DS = Code segment
	mov	si,offset resident_mes
	mov	di,offset 80h
	mov	al,offset rmes_end-resident_mes
	stosb
resmesset_loop:
	movsb
	cmp	byte ptr -1[di],0
	jnz	resmesset_loop

;==============================================================================
;	Memory Check & Init
;==============================================================================
memchk_init:
	mov	ax,es
	dec	ax
	mov	es,ax		;ES = MCB segment
	mov	di,es:[3]	;di = max size
	mov	ax,cs
	mov	es,ax

	mov	dx,offset dataarea+16
	shr	dx,1
	shr	dx,1
	shr	dx,1
	shr	dx,1	;/16

	xor	al,al
	mov	ah,[mmldat_lng]
	shr	ax,1
	shr	ax,1	;*64	(64 P.G.Size = 1 K.Byte)
	xor	bl,bl
	mov	bh,[voicedat_lng]
	shr	bx,1
	shr	bx,1	;*64
	xor	cl,cl
	mov	ch,[effecdat_lng]
	shr	cx,1
	shr	cx,1	;*64
	add	dx,ax
	add	dx,bx
	add	dx,cx

	mov	[resident_size],dx

	cmp	di,dx
	jc	pmderr_7

;==============================================================================
;	曲データ，音色データ格納番地を設定
;==============================================================================
	mov	ax,offset dataarea+1
	mov	[mmlbuf],ax
	dec	ax

	mov	bh,[mmldat_lng]
	xor	bl,bl
	shl	bx,1
	shl	bx,1
	add	ax,bx
	mov	[tondat],ax

	mov	bh,[voicedat_lng]
	xor	bl,bl
	shl	bx,1
	shl	bx,1
	add	ax,bx
	mov	[efcdat],ax

;==============================================================================
;	効果音/FMINT/EFCINTを初期化
;==============================================================================
	xor	ax,ax
	mov	[fmint_seg],ax
	mov	[fmint_ofs],ax
	mov	[efcint_seg],ax
	mov	[efcint_ofs],ax
	mov	[intfook_flag],al
	mov	[skip_flag],al
	mov	[effon],al
	mov	[fm_effec_flag],al
	mov	[pcmflag],al
	dec	al
	mov	[psgefcnum],al
	mov	[fm_effec_num],al
	mov	[pcm_effec_num],al

;==============================================================================
;	割り込み設定
;==============================================================================
	cmp	[board],0
	jz	not_set_opnvec

;==============================================================================
;	OPN 初期化
;==============================================================================
	call	int_init

;------------------------------------------------------------------------------
;	088/188/288/388 (同INT番号のみ) を初期設定
;------------------------------------------------------------------------------
if	va
	mov	ax,2900h
	call	opnset44
	mov	ax,2400h
	call	opnset44
	mov	ax,2500h
	call	opnset44
	mov	ax,2600h
	call	opnset44
	mov	ax,273fh
	call	opnset44
else
	mov	cx,4
	mov	dx,088h

opninit_loop:
	push	cx

	mov	ah,-1
	mov	cx,256
opninit_loop2:
	in	al,dx
	and	ah,al
	test	ah,ah
	jns	opninit_exec
	loop	opninit_loop2
	jmp	opninit_next	;音源無し

opninit_exec:
	pushf
	cli
	rdychk
	mov	al,0eh
	out	dx,al
	mov	cx,256
	loop	$
	add	dx,2
	in	al,dx
	popf
	sub	dx,2
	and	al,0c0h
	cmp	al,[opn_0eh]	;int番号を比較
	jnz	opninit_next	;非一致なら初期化しない

	mov	ax,2900h
	call	opnset_fmc
	mov	ax,2400h
	call	opnset_fmc
	mov	ax,2500h
	call	opnset_fmc
	mov	ax,2600h
	call	opnset_fmc
	mov	ax,273fh
	call	opnset_fmc

opninit_next:
	pop	cx
	inc	dh
	loop	opninit_loop
endif

;==============================================================================
;	ＯＰＮ　割り込みベクトル　退避
;==============================================================================
	cli
	xor	ax,ax
	mov	es,ax
	mov	bx,[vector]
	les	bx,es:[bx]
	mov	[int5ofs],bx
	mov	[int5seg],es

;==============================================================================
;	ＯＰＮ　割り込みベクトル　設定
;==============================================================================
	mov	es,ax
	mov	bx,[vector]
	mov	es:[bx],offset opnint
	mov	es:[bx+2],cs
not_set_opnvec:

;==============================================================================
;	INT60 割り込みベクトル　退避
;==============================================================================
	cli
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]
	mov	[int60ofs],bx
	mov	[int60seg],es

;==============================================================================
;	INT60 割り込みベクトル　設定
;==============================================================================
	mov	es,ax
	mov	es:[pmdvector*4],offset int60_head
	mov	es:[pmdvector*4+2],cs

;==============================================================================
;	ＯＰＮ割り込み開始
;==============================================================================
	call	opnint_start
	sti

;==============================================================================
;	Wait回数表示
;==============================================================================
	cmp	[message_flag],0
	jz	not_key_mes

	print_mes	mes_wait1
	mov	ax,[wait_clock]
	call	print_16
	print_mes	mes_wait2
	mov	ax,[wait_clock]
	mul	[wait1_clock]
	call	print_16
	print_mes	mes_wait3

;==============================================================================
;	終了処理
;==============================================================================
	print_mes	mes_exit

	cmp	[key_check],0
	jz	not_key_mes
	print_mes	mes_key
not_key_mes:

;==============================================================================
;	環境を解放
;==============================================================================
if	va
	mov	ax,cs:[002ch]
	dec	ax
	mov	es,ax
	mov	ax,cs
	cmp	ax,es:[1]	;環境のownerがpmdでなければ
	jnz	not_cut_env	;解放しない
endif
	mov	es,cs:[002ch]	;ES=環境のsegment
	resident_cut		;環境を解放
not_cut_env:

;==============================================================================
;	データエリアを確保
;==============================================================================
	mov	dx,[resident_size]
	jmp	resident_exit_end	;常駐終了

;==============================================================================
;	ＦＭ音源ボード装着/PORT/INTチェック
;==============================================================================
fm_check:
;------------------------------------------------------------------------------
;	ポートを設定
;------------------------------------------------------------------------------
	push	es
	call	port_check
	pop	es
	jc	not_fmboard

	mov	ax,[fm1_port1]
	mov	[fm_port1],ax
	mov	ax,[fm1_port2]
	mov	[fm_port2],ax
ife	va
	add	ah,"0"
	mov	[port_num],ah
endif

;------------------------------------------------------------------------------
;	Wait設定
;------------------------------------------------------------------------------
	call	wait_check
	mov	[wait1_clock],ax
	mov	[wait_clock],cx

;------------------------------------------------------------------------------
;	ADPCMのRAM check
;------------------------------------------------------------------------------
if	board2*adpcm
	mov	dx,2983h
	call	opnset44		;2608 on
 if	ademu
	mov	[pcm_gs_flag],1		;ADPCMは使用しない
 else
	call	adpcm_ram_check		;in ADRAMCHK.ASM
 endif
else
	mov	[pcm_gs_flag],1		;ADPCMは使用しない
endif
	mov	[board],1
	ret

not_fmboard:
	mov	[board],0
	cmp	[message_flag],0
	jz	nfm_ret
	print_mes	mes_warning
	print_mes	mes_not_board
nfm_ret:
	ret

;==============================================================================
;	INT init
;==============================================================================
int_init:
;------------------------------------------------------------------------------
;	INT番号を読み出して設定
;------------------------------------------------------------------------------
	mov	dx,[fm1_port1]
	pushf
	cli
	rdychk
	mov	al,7
	out	dx,al
	_wait			;PSG Write Wait
	mov	dx,[fm1_port2]
	mov	al,3fh
	out	dx,al
	popf

	mov	dx,[fm1_port1]	;2
	pushf
	cli
	rdychk
	mov	al,0eh
	out	dx,al
	_wait			;PSG Read Wait
	mov	dx,[fm1_port2]
	in	al,dx
	popf
	and	al,0c0h
ife	va
	mov	[opn_0eh],al
endif
	rol	al,1
	rol	al,1
	add	al,al
	add	al,al
	xor	ah,ah
	mov	bx,offset vector_table
	add	bx,ax
	mov	al,[bx]
	mov	[int_num],al
	mov	al,[bx+1]
	mov	[int_level],al
	mov	ax,[bx+2]
	mov	[vector],ax

	cmp	[message_flag],0
	jz	pps_chk

	print_mes	mes_int

	xor	bh,bh
	mov	bl,[ongen]
	add	bx,bx
	add	bx,offset ongen_sel
	mov	dx,[bx]
	print_dx

ife	ademu
 if	board2*pcm
	print_mes	mes_pcm
 endif
 if	board2*adpcm
	xor	bh,bh
	mov	bl,[pcm_gs_flag]
	add	bx,bx
	add	bx,offset pcm_sel
	mov	dx,[bx]
	print_dx
 endif
endif
	print_mes	mes_int2

;------------------------------------------------------------------------------
;	ppsdrv/ppz8常駐CHECK
;------------------------------------------------------------------------------
pps_chk:
	cmp	[ppsdrv_flag],-1
	jz	pps_check
	cmp	[kp_rhythm_flag],-1
	jnz	ppschk_exit
	mov	al,[ppsdrv_flag]
	xor	al,1
	mov	[kp_rhythm_flag],al
	jmp	ppschk_exit

pps_check:
	call	ppsdrv_check
	jc	ppschk_01
	mov	[ppsdrv_flag],1
	cmp	[kp_rhythm_flag],-1
	jnz	ppschk_exit
	mov	[kp_rhythm_flag],0
	jmp	ppschk_exit
ppschk_01:
	mov	[ppsdrv_flag],0
	cmp	[kp_rhythm_flag],-1
	jnz	ppschk_exit
	mov	[kp_rhythm_flag],1
	jmp	ppschk_exit

ppschk_exit:
	cmp	[message_flag],0
	jz	ppschk_end
	cmp	[ppsdrv_flag],1
	jnz	ppschk_end
	print_mes	mes_ppsdrv
ppschk_end:
if	ppz
	call	ppz8_check
	jc	ppzchk_end
	mov	es:[ppz_call_seg],1
	mov	ax,0410h
	int	ppz_vec
	mov	ah,es:[int_level]
	add	ah,8
	cmp	al,ah
	jnz	ppzchk_next
	push	es
	mov	ax,0409h
	int	ppz_vec
	mov	ax,es
	pop	es
	mov	es:[ppz_call_ofs],bx
	mov	es:[ppz_call_seg],ax
ppzchk_next:
	mov	ax,1901h
	int	ppz_vec		;常駐解除禁止
	cmp	[message_flag],0
	jz	mask_eoi_set
	print_mes	mes_ppz8
ppzchk_end:
endif
;------------------------------------------------------------------------------
;	MASK/EOIの出力先の設定
;------------------------------------------------------------------------------
mask_eoi_set:
	mov	al,[int_level]
	test	al,8		;Slave?
	jnz	i6s_slave

;	Masterの場合
	mov	dx,ms_msk
	mov	[mask_adr],dx	;MaskはMasterを
	mov	cl,al
	inc	cl
	xor	ah,ah
	stc
	rcl	ah,cl
	mov	[mask_data],ah	;Maskするデータ
	not	ah
	mov	[mask_data2],ah	;Mask解除するデータ
	mov	dx,ms_cmd
	mov	[eoi_adr],dx	;EOIはMasterにSendする
	and	al,7
	or	al,60h
	mov	[eoi_data],al	;特殊EOI + 割り込みベクトル が入る

	jmp	i6s_intexit

;	Slaveの場合
i6s_slave:
	and	al,7		;AL=INTLevel
	mov	dx,sl_msk
	mov	[mask_adr],dx	;MaskはSlaveを
	mov	cl,al
	inc	cl
	xor	ah,ah
	stc
	rcl	ah,cl
	mov	[mask_data],ah	;Maskするデータ
	not	ah
	mov	[mask_data2],ah	;Mask解除するデータ
	mov	dx,sl_cmd
	mov	[eoi_adr],dx	;EOIはSlaveにSendする
	or	al,60h
	mov	[eoi_data],al	;特殊EOI + 割り込みベクトル が入る

i6s_intexit:
	mov	ax,cs
	mov	es,ax
	ret

;==============================================================================
;	ppsdrv常駐CHECK
;==============================================================================
ppsdrv_check:
	push	es
	push	ax
	push	bx

	xor	ax,ax
	mov	es,ax
	les	bx,es:[ppsdrv*4]
	cmp	word ptr es:2[bx],"MP"
	jnz	non_ppsdrv
	cmp	byte ptr es:4[bx],"P"
	jnz	non_ppsdrv

	clc
ppsdrvchk_exit:
	pop	bx
	pop	ax
	pop	es
	ret
non_ppsdrv:
	stc
	jmp	ppsdrvchk_exit

if	ppz
;==============================================================================
;	ppz8常駐CHECK
;==============================================================================
ppz8_check:
	push	es
	push	ax
	push	bx

	xor	ax,ax
	mov	es,ax
	les	bx,es:[ppz_vec*4]
	cmp	word ptr es:2[bx],"PP"
	jnz	non_ppz8
	cmp	word ptr es:4[bx],"8Z"
	jnz	non_ppz8
	clc
ppz8_chk_ret:
	pop	bx
	pop	ax
	pop	es
	ret
non_ppz8:
	stc
	jmp	ppz8_chk_ret
endif

;==============================================================================
;	ＯＰＮ割り込み許可処理
;==============================================================================
opnint_start:
	cmp	[board],0
	jz	not_opnint_start	;ボードがない
	mov	ax,cs
	mov	es,ax
	mov	di,offset part1
	mov	cx,max_part1*type qq
	xor	al,al
rep	stosb				;Partwork All Reset
	dec	al
	mov	[rhythmmask],255	;Rhythm Mask解除
	mov	[rhydmy],al		;R part Dummy用
	call	data_init
	call	opn_init
	mov	dx,07bfh		;07hPort Init
	call	opnset44
	call	mstop
	call	setint
	mov	al,[int_level]
	call	intset
if	va
	in	al,32h
	jmp	$+2
	and	al,7fh
	out	32h,al
endif
	mov	dx,2983h
	call	opnset44
not_opnint_start:
	ret

ife	va
;==============================================================================
;	OPN out for 088/188/288/388 INIT用
;		input	ah	reg
;			al	data
;			dx	port
;==============================================================================
opnset_fmc:
	pushf
	cli
	mov	cx,256
	loop	$
	xchg	ah,al
	out	dx,al
	mov	cx,256
	loop	$
	add	dx,2
	xchg	ah,al
	out	dx,al
	sub	dx,2
	popf
	ret
endif
;==============================================================================
;	FM音源ポートを調べる
;		output	fm1_port1/fm1_port2/fm2_port1/fm2_port2
;			ongen/epson_flag
;			cy=1でボード無し
;==============================================================================
port_check:
if	va
	mov	[fm1_port1],44h
	mov	[fm1_port2],45h
	mov	[fm2_port1],46h
	mov	[fm2_port2],47h
	mov	[epson_flag],0
;------------------------------------------------------------------------------
;	VA+NORM の check	(PMDVA1)
;------------------------------------------------------------------------------
	mov	[ongen],0
	cli
	mov	cx,100
	loop	$
	mov	dx,44h
	mov	al,0bh
	out	dx,al
	mov	cx,100
	loop	$
	inc	dx
	mov	al,0aah
	out	dx,al
	mov	cx,100
	loop	$
	in	al,dx
	sti
	cmp	al,0aah
	jnz	pc_error
;------------------------------------------------------------------------------
;	VA+BOARD2 の check	(PMDVA)
;------------------------------------------------------------------------------
	cli
	mov	cx,100
	loop	$
	mov	dx,44h
	mov	al,-1
	out	dx,al
	inc	dx
	mov	cx,100
	loop	$
	in	al,dx
	sti
	dec	al
 if	board2
	jnz	pc_error
 else
	jnz	va_norm_ret
 endif
	mov	[ongen],1
va_norm_ret:
	clc
	ret
else
 if	board2
  if	pcm+ppz
;------------------------------------------------------------------------------
;	98+86B の check		(PMD86/PMDPPZ)	86ボード専用
;------------------------------------------------------------------------------
	jmp	check_86b
  else
;------------------------------------------------------------------------------
;	98+SPB の check		(PMDB2)
;------------------------------------------------------------------------------
	call	check_spb
	jc	check_86b
	ret
  endif
 else
;------------------------------------------------------------------------------
;	98+NORM の check	(PMD)
;------------------------------------------------------------------------------
	call	check_spb
	jnc	norm_ret
	call	check_86b
	jnc	norm_ret

	mov	[ongen],0

	mov	ah,4		;088->188->288->388の順にcheck
	mov	dx,088h

	cmp	[port_sel],-1
	jz	checkloop_norm
	mov	dh,[port_sel]
	mov	ah,1

checkloop_norm:
	cli
	mov	cx,100
	loop	$
	mov	al,0bh
	out	dx,al
	mov	cx,100
	loop	$
	add	dx,2
	mov	al,0aah
	out	dx,al
	mov	cx,100
	loop	$
	in	al,dx
	sti
	sub	dx,2
	cmp	al,0aah
	jz	set_port

	dec	ah
	jz	pc_error
	add	dx,100h
	jmp	checkloop_norm

norm_ret:
	clc
	ret
 endif

;------------------------------------------------------------------------------
;	86Bの存在check
;------------------------------------------------------------------------------
check_86b:
	mov	[ongen],1
	mov	[epson_flag],0
;	86B 装着check & MASK
	mov	ax,0fd80h
	mov	es,ax
	cmp	word ptr es:[2],02a27h	;EPSON機？
	jnz	not_epson0
	mov	[epson_flag],1
	cmp	byte ptr es:[4],6	;PC-286VE以前？
	jc	pc_error		;なら86ボード無し
not_epson0:
	mov	dx,0a460h	;NEC OPNA ID port
	in	al,dx
	cmp	al,-1
	jz	pc_error
	out	5fh,al
	and	al,0fch
	out	dx,al		;NEC OPNA off

	mov	ah,2
	mov	dx,188h		;188->288の順にcheck

	cmp	[port_sel],-1
	jz	checkloop_86b
	mov	dh,[port_sel]
	mov	ah,1

checkloop_86b:
	cli
	mov	al,-1
	mov	cx,100
	loop	$
	out	dx,al
	add	dx,2
	mov	cx,100
	loop	$
	in	al,dx
	sti
	sub	dx,2
	dec	al		;YM2608かどうかのcheck
	jnz	checkexit_86b
	add	dx,4
	in	al,dx
	mov	bl,al
	add	dx,2
	in	al,dx
	sub	dx,6
	and	al,bl
	inc	al		;x8C/x8Eがmaskされているかどうかcheck
	jz	init_86b

checkexit_86b:
	dec	ah
	jz	pc_error
	inc	dh
	jmp	checkloop_86b

;------------------------------------------------------------------------------
;	86B 初期設定
;------------------------------------------------------------------------------
init_86b:
	push	dx
	mov	dx,0a460h	;NEC OPNA ID port
	cli
	in	al,dx
	out	5fh,al
	and	al,0fch
	or	al,1
	out	dx,al		;NEC OPNA on

	mov	dx,0a66eh
	in	al,dx
	out	5fh,al
	and	al,0feh			; a66e b0 : mute 1:する 0:しない
	out	dx,al
	cmp	[epson_flag],0
	jz	not_init_gdc
	mov	al,1
	out	6eh,al			;(T_T)EPSON機の display 24KHz Mode
not_init_gdc:
if	pcm
	call	stop_86pcm
endif
	sti
	pop	dx
	jmp	set_port

ife	pcm
;------------------------------------------------------------------------------
;	SPBのcheck
;------------------------------------------------------------------------------
check_spb:
	mov	[ongen],1
	mov	[epson_flag],0
;	86B 装着check & MASK
	mov	ax,0fd80h
	mov	es,ax
	cmp	word ptr es:[2],02a27h	;EPSON機？
	jnz	not_epson1
	mov	[epson_flag],1
	cmp	byte ptr es:[4],6	;PC-286VE以前？
	jc	not_86b1		;なら86ボード無し
not_epson1:
	mov	dx,0a460h	;NEC OPNA ID port
	in	al,dx
	cmp	al,-1
	jz	not_86b1
	out	5fh,al
	and	al,0fch
	out	dx,al		;NEC OPNA off
not_86b1:
	mov	ah,4		;088->188->288->388の順にcheck
	mov	dx,088h

	cmp	[port_sel],-1
	jz	checkloop_spb
	mov	dh,[port_sel]
	mov	ah,1

checkloop_spb:
	cli
	mov	al,-1
	mov	cx,100
	loop	$
	out	dx,al
	add	dx,2
	mov	cx,100
	loop	$
	in	al,dx
	sti
	sub	dx,2
	dec	al		;YM2608かどうかのcheck
	jnz	checkexit_spb
	add	dx,4
	in	al,dx
	mov	bl,al
	add	dx,2
	in	al,dx
	sub	dx,6
	and	al,bl
	inc	al		;x8C/x8Eがmaskされていないかどうかcheck
	jnz	set_port

checkexit_spb:
	dec	ah
	jz	pc_error
	add	dx,100h
	jmp	checkloop_spb
endif

;------------------------------------------------------------------------------
;	ポート設定
;------------------------------------------------------------------------------
set_port:
	mov	[fm1_port1],dx
	add	dx,2
	mov	[fm1_port2],dx
	add	dx,2
	mov	[fm2_port1],dx
	add	dx,2
	mov	[fm2_port2],dx
	clc
	ret
endif
;------------------------------------------------------------------------------
;	音源が見つからなかった
;------------------------------------------------------------------------------
pc_error:
	stc
	ret

;==============================================================================
;	常駐していた時のステータス表示／変更処理
;		input	DS:PSP_seg / ES:PMD_seg
;==============================================================================
change_main:
;==============================================================================
;	オプションを取り込む
;==============================================================================
	mov	si,offset 80h

	cmp	byte ptr [si],0
	jz	put_status		;オプション無し
	inc	si			;ds:si = command line

	mov	bx,offset status_option
	call	set_option

	mov	ax,cs
	mov	ds,ax	;DS = Code_seg
	print_mes	changemes_0

;==============================================================================
;	Statusの表示
;		in.	ES	PMD_seg
;==============================================================================
put_status:
	mov	ax,cs
	mov	ds,ax	;DS = Code_seg

;	曲データバッファサイズ
	print_mes	changemes_01
	mov	al,es:[mmldat_lng]
	call	put8

;	音色データバッファサイズ
	print_mes	changemes_02
	mov	al,es:[voicedat_lng]
	call	put8

;	効果音データバッファサイズ
	print_mes	changemes_03
	mov	al,es:[effecdat_lng]
	call	put8

;	FM音源    音量調整値
	print_mes	changemes_1
	mov	al,es:[_fm_voldown]
	call	put8
	print_mes	crlf

;	SSG音源   音量調整値
	print_mes	changemes_2
	mov	al,es:[_ssg_voldown]
	call	put8
	print_mes	crlf

if	board2
;	PCM音源   音量調整値
	print_mes	changemes_3
	mov	al,es:[_pcm_voldown]
	call	put8
	print_mes	crlf
if	ppz
	print_mes	changemes_3z
	mov	al,es:[_ppz_voldown]
	call	put8
	print_mes	crlf
endif
;	RHYTHM音源音量調整値
	print_mes	changemes_4
	mov	al,es:[_rhythm_voldown]
	call	put8
	print_mes	crlf

;	SSGドラム発音時に同時にRHYTHM音源を鳴らすか
	print_mes	changemes_5
	mov	dx,offset changemes_5a
	cmp	es:[kp_rhythm_flag],0
	jnz	change5_put
	mov	dx,offset changemes_5b
change5_put:
	print_dx
endif

;	GRPH/ESCキーで早送り/曲の停止の制御
	print_mes	changemes_6
	mov	dx,offset changemes_6a
	cmp	es:[key_check],0
	jnz	change6_put
	mov	dx,offset changemes_6b
change6_put:
	print_dx

;	ESC と同時に使用するキー設定値
	print_mes	changemes_7
	mov	al,es:[esc_sp_key]
if	va
	rol	al,1
	rol	al,1
	rol	al,1
	and	al,00000111b
endif
	call	put8
	print_mes	crlf

;	GRPHと同時に使用するキー設定値
	print_mes	changemes_8
	mov	al,es:[grph_sp_key]
if	va
	rol	al,1
	rol	al,1
	rol	al,1
	and	al,00000111b
endif
	call	put8
	print_mes	crlf

;	GRPHと同時に使用するキー設定値
	print_mes	changemes_8b
	mov	al,es:[rew_sp_key]
if	va
	rol	al,1
	rol	al,1
	rol	al,1
	and	al,00000111b
endif
	call	put8
	print_mes	crlf

;	フェードアウト後に曲の演奏を停止するか
	print_mes	changemes_9
	mov	dx,offset changemes_6a
	cmp	es:[fade_stop_flag],0
	jnz	change9_put
	mov	dx,offset changemes_6b
change9_put:
	print_dx

;	FM/INT60割り込み中に割り込みを禁止するか
	print_mes	changemes_10
	mov	dx,offset changemes_6a
	cmp	es:[disint],0
	jnz	change10_put
	mov	dx,offset changemes_6b
change10_put:
	print_dx

;	PPSDRVを使用するか
	print_mes	changemes_11
	mov	dx,offset changemes_6a
	cmp	es:[ppsdrv_flag],0
	jnz	change11_put
	mov	dx,offset changemes_6b
change11_put:
	print_dx

if	ppz
;	PPZ8を使用するか
	print_mes	changemes_11_
	mov	dx,offset changemes_6a
	cmp	es:[ppz_call_seg],0
	jnz	change11__put
	mov	dx,offset changemes_6b
change11__put:
	print_dx
endif

;	FM音源出力時のウエイト
	print_mes	changemes_12
	mov	ax,es:[wait_clock]
	call	print_16
	print_mes	changemes_12a
	mov	ax,es:[wait_clock]
	mul	es:[wait1_clock]
	call	print_16
	print_mes	changemes_12b

;	早送り時のTimerB値
	print_mes	changemes_13
	xor	ah,ah
	mov	al,es:[ff_tempo]
	call	print_16
	print_mes	crlf

if	board2*adpcm
 ife	ademu
;	ADPCM定義速度
	print_mes	changemes_14
	mov	dx,offset changemes_14a
	cmp	es:[adpcm_wait],0
	jz	change14_put
	mov	dx,offset changemes_14b
	cmp	es:[adpcm_wait],1
	jz	change14_put
	mov	dx,offset changemes_14c
change14_put:
	print_dx
 endif
endif
if	board2*pcm
;	ADPCMに合わせるか設定
	print_mes	changemes_15
	mov	dx,offset changemes_15a
	cmp	es:[_pcm86_vol],0
	jz	change15_put
	mov	dx,offset changemes_15b
change15_put:
	print_dx

;	PCM再生周波数
	print_mes	changemes_16
	xor	dx,dx
	mov	dl,es:[p86_freq]
	add	dx,dx
	add	dx,dx
	add	dx,dx
	add	dx,offset changemes_16a
	print_dx
	cmp	es:[p86_freq],8
	jz	change16_exit
	print_mes	changemes_16b
change16_exit:
endif
	msdos_exit	;終了

;==============================================================================
;	数値の表示 8bit
;		input	AL
;==============================================================================
put8:
	xor	ah,ah
	mov	dl,100
	call	p8_oneset
	mov	dl,10
	call	p8_oneset
	add	al,"0"
	mov	dl,al
	mov	ah,2
	int	21h	;１文字表示
	ret
p8_oneset:
	mov	dh,"0"
p8_ons0:sub	al,dl
	jc	p8_ons1
	inc	dh
	jmp	p8_ons0
p8_ons1:add	al,dl
	test	ah,ah
	jnz	p8_ons2
	cmp	dh,"0"
	jz	p8_ons3
p8_ons2:push	dx
	push	ax
	mov	dl,dh
	mov	ah,2
	int	21h	;１文字表示
	pop	ax
	pop	dx
	mov	ah,1
	inc	di
p8_ons3:
	ret

;==============================================================================
;	解放処理
;	解放禁止フラグをcheck
;==============================================================================
resident_cut_main:
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]	; ES:BX=PMD seg/offset
	cmp	es:[rescut_cant],0	;SET_FM_(EFC_)INT使用中か？
	jz	rescut_main
cantcut_res:
	mov	ax,cs
	mov	ds,ax
	print_mes	cantcut_mes	;常駐解除出来ない
	error_exit	1

;==============================================================================
;	解放して終了
;==============================================================================
rescut_main:
	cli			;割り込み禁止
	
	call	ppsdrv_check
	jnc	rs_fmefc_cut
	mov	ax,1800h
	int	pmdvector	;PPSDRVが常駐してなかったら対応フラグreset
rs_fmefc_cut:
	mov	ah,11h
	int	pmdvector
	inc	al
	jz	rs_non_fmefc
	mov	ah,0dh
	int	pmdvector	;ＦＭ効果音の停止
rs_non_fmefc:

	mov	ah,15h
	int	pmdvector
	test	al,al
	jz	rs_non_ssgefc
	mov	ah,04h
	int	pmdvector	;ＰＳＧ効果音の停止
rs_non_ssgefc:

	mov	ah,1
	int	pmdvector	;演奏の停止

	call	vector_ret
	sti			;割り込み許可
	jc	pmderr_4	;解放できない

if	ppz
	call	ppz8_check
	jc	rs_no_ppz
	mov	ax,1900h
	int	ppz_vec		;常駐解除許可
rs_no_ppz:
endif
	print_mes	mes_cut
	msdos_exit

;==============================================================================
;　	OPN他割り込み切り放し
;==============================================================================
vector_ret:
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]	; ES:BX=PMD seg/offset

	cmp	es:[board],0
	jz	not_cut_opnvec

	mov	al,es:_int_level[bx]
	call	intpop			; OPN割り込みマスクを元に戻す

	mov	ax,es:[fm1_port1]	; FM1_port1
	mov	[fm1_port1],ax
	mov	ax,es:[fm1_port2]	; FM1_port2
	mov	[fm1_port2],ax
	mov	dx,2730h		; FM int RESET
	call	opnset44

	;ＩＮＴ５割り込みベクトルを元に戻す
	xor	ax,ax
	mov	ds,ax
	mov	cx,es:_int5ofs[bx]
	mov	dx,es:_int5seg[bx]
	push	bx
	mov	bx,es:_vector[bx]
	mov	ds:[bx],cx
	mov	ds:[bx+2],dx
	pop	bx

not_cut_opnvec:
	;ＩＮＴ６０割り込みベクトルを元に戻す
	xor	ax,ax
	mov	ds,ax
	mov	cx,es:_int60ofs[bx]
	mov	dx,es:_int60seg[bx]
	mov	ds:[pmdvector*4],cx
	mov	ds:[pmdvector*4+2],dx

	mov	ax,cs
	mov	ds,ax
	resident_cut	;メモリを解放

	ret

;==============================================================================
;	Interrupt set&push	(master/slave 共用)
;		input	al	:Interrupt Level
;==============================================================================
intset:
	mov	cl,al
	mov	dx,ms_msk
	cmp	cl,8	;master?
	jc	intset2
	sub	cl,8
	in	al,dx
if	va
	jmp	$+2
else
	out	5fh,al
endif
	and	al,7fh	;Slaveの場合 = MasterのIR7(Slave)のMaskを解除
	out	dx,al
	mov	dx,sl_msk
intset2:
	inc	cl
	xor	al,al
	stc
	rcl	al,cl

	not	al
	mov	bl,al

	in	al,dx
	mov	ah,al	;AH=前のmaskregister
	and	al,bl
	out	dx,al	;該当IRのマスクを解除

	not	bl	;BL=対象bitのみ１になる
	and	ah,bl	;対象bitのみ 0か1 他は0になる
	mov	cs:[maskpush],ah	;0なら使用中 0以外なら使用してなかった

	ret

;==============================================================================
;	Interrupt pop	(master/slave 共用)
;		input	al	:Interrupt Level
;==============================================================================
intpop:
	mov	dx,ms_msk
	cmp	al,8	;master?
	jc	intpop2
	sub	al,8
	mov	dx,sl_msk
intpop2:
	in	al,dx
	push	es
	push	ax
	push	bx
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]
	mov	cl,es:_maskpush[bx]
	pop	bx
	pop	ax
	pop	es
	or	al,cl	;元に戻す
	out	dx,al
	ret

;==============================================================================
;	オプション処理
;		input	cs:bx	option_data
;			ds:si	command_line
;			es	pmd_segment
;==============================================================================
set_option:
	lodsb
	cmp	al,"/"
	jz	option_main
	cmp	al,"-"
	jz	option_main
	cmp	al," "
	jc	so_ret
	jz	set_option
	jmp	usage
so_ret:	ret

option_main:
	lodsb
	and	al,11011111b	;小文字＞大文字
	push	bx
	sub	bx,3
oc_loop:
	add	bx,3
	cmp	byte ptr cs:[bx],0
	jz	usage
	cmp	al,byte ptr cs:[bx]
	jnz	oc_loop
	mov	ax,cs:1[bx]
	call	ax
	pop	bx
	jmp	set_option

;==============================================================================
;	/M option
;==============================================================================
muslng_get:
	call	get_comline_number
	jc	usage
	mov	es:[mmldat_lng],al
	ret

;==============================================================================
;	/V option
;==============================================================================
voilng_get:
	call	get_comline_number
	jc	usage
	mov	es:[voicedat_lng],al
	ret

;==============================================================================
;	/E option
;==============================================================================
efclng_get:
	call	get_comline_number
	jc	usage
	mov	es:[effecdat_lng],al
	ret

;==============================================================================
;	/D? option
;==============================================================================
fmvd_set:
	lodsb
	mov	dl,al
	push	dx
	call	get_comline_number
	pop	dx
	jc	usage
	and	dl,11011111b
	cmp	dl,"S"
	jz	psgvd_set
	cmp	dl,"P"
	jz	pcmvd_set
	cmp	dl,"R"
	jz	rhythmvd_set
	cmp	dl,"Z"
	jz	ppzvd_set
	cmp	dl,"F"
	jnz	usage

;==============================================================================
;	/DF option
;==============================================================================
	mov	es:[fm_voldown],al
	mov	es:[_fm_voldown],al
	ret

;==============================================================================
;	/DS option
;==============================================================================
psgvd_set:
	mov	es:[ssg_voldown],al
	mov	es:[_ssg_voldown],al
	ret

;==============================================================================
;	/DP option
;==============================================================================
pcmvd_set:
	mov	es:[pcm_voldown],al
	mov	es:[_pcm_voldown],al
	ret

;==============================================================================
;	/DZ option
;==============================================================================
ppzvd_set:
	mov	es:[ppz_voldown],al
	mov	es:[_ppz_voldown],al
	ret

;==============================================================================
;	/DR option
;==============================================================================
rhythmvd_set:
	mov	es:[rhythm_voldown],al
	mov	es:[_rhythm_voldown],al
	ret

;==============================================================================
;	/K option
;==============================================================================
keycheck:
	lodsb
	cmp	al,"-"
	jz	kck_minus
	and	al,11011111b
	cmp	al,"G"
	jz	grph_special_set
	cmp	al,"R"
	jz	rew_special_set
	cmp	al,"E"
	jz	esc_special_set
	dec	si
	mov	es:[key_check],0
	ret
kck_minus:
	mov	es:[key_check],1
	ret

;==============================================================================
;	/KG option
;==============================================================================
grph_special_set:
	call	get_comline_number
if	va
	ror	al,1
	ror	al,1
	ror	al,1
	and	al,11100000b
endif
	mov	es:[grph_sp_key],al
	ret

;==============================================================================
;	/KR option
;==============================================================================
rew_special_set:
	call	get_comline_number
if	va
	ror	al,1
	ror	al,1
	ror	al,1
	and	al,11100000b
endif
	mov	es:[rew_sp_key],al
	ret

;==============================================================================
;	/KE option
;==============================================================================
esc_special_set:
	call	get_comline_number
if	va
	ror	al,1
	ror	al,1
	ror	al,1
	and	al,11100000b
endif
	mov	es:[esc_sp_key],al
	ret

;==============================================================================
;	/I option
;==============================================================================
disint_set:
	cmp	byte ptr ds:[si],"-"
	jz	dins_minus
	mov	es:[disint],1
	ret
dins_minus:
	inc	si
	mov	es:[disint],0
	ret

;==============================================================================
;	/N option
;==============================================================================
notshot_set:
	cmp	byte ptr ds:[si],"-"
	jz	nshs_minus
	mov	es:[kp_rhythm_flag],0
	ret
nshs_minus:
	inc	si
	mov	es:[kp_rhythm_flag],1
	ret

;==============================================================================
;	/F option
;==============================================================================
notstop_set:
	cmp	byte ptr ds:[si],"-"
	jz	nsts_minus
	mov	es:[fade_stop_flag],0
	ret
nsts_minus:
	inc	si
	mov	es:[fade_stop_flag],1
	ret

;==============================================================================
;	/P option
;==============================================================================
ppsdrv_reset:
	cmp	byte ptr ds:[si],"-"
	jz	pdrrs_minus
pdrrs_none:
	mov	es:[ppsdrv_flag],0
	ret
pdrrs_minus:
	inc	si
	call	ppsdrv_check
	jc	pdrrs_none
	mov	es:[ppsdrv_flag],1
	ret

;==============================================================================
;	/Z option
;==============================================================================
ppz_reset:
if	ppz
	pushf
	cli
endif

	cmp	byte ptr ds:[si],"-"
	jz	ppz_minus

if	ppz
	call	ppz8_check
	jc	ppz_none

	mov	ah,12h
	int	ppz_vec		;FIFO割り込み停止

	mov	ax,0200h
z_ppz_off_loop:
	push	ax
	int	ppz_vec		;ppz keyoff
	pop	ax
	inc	al
	cmp	al,8
	jc	z_ppz_off_loop

	mov	ax,1900h
	int	ppz_vec		;常駐解除許可

ppz_none:
	mov	es:[ppz_call_ofs],0
	mov	es:[ppz_call_seg],0
	popf
endif
	ret

ppz_minus:
	inc	si
if	ppz
	call	ppz8_check
	jc	ppz_none
	mov	es:[ppz_call_seg],1
	mov	ax,0410h
	int	ppz_vec
	mov	ah,es:[int_level]
	add	ah,8
	cmp	al,ah
	jnz	ppzm_next
	push	es
	mov	ax,0409h
	int	ppz_vec
	mov	ax,es
	pop	es
	mov	es:[ppz_call_ofs],bx
	mov	es:[ppz_call_seg],ax
ppzm_next:
	mov	ax,1901h
	int	ppz_vec		;常駐解除禁止
	popf
endif
	ret

;==============================================================================
;	/W option
;==============================================================================
waitclk_set:
	call	get_comline_number
	jc	wait_newset
	test	al,al
	jz	usage
	xor	ah,ah
	mov	es:[wait_clock],ax
	ret
wait_newset:
	call	wait_check
	mov	es:[wait1_clock],ax
	mov	es:[wait_clock],cx
	ret

;==============================================================================
;	/G option
;==============================================================================
fftempo_set:
	call	get_comline_number
	jc	fft_newset
	test	al,al
	jz	usage
	mov	es:[ff_tempo],al
	ret
fft_newset:
	mov	es:[ff_tempo],250
	ret

;==============================================================================
;	/A option
;==============================================================================
adpcmwait_set:
	call	get_comline_number
	cmp	al,3
	jnc	usage
	mov	es:[adpcm_wait],al
	ret

;==============================================================================
;	/S option
;==============================================================================
pcm86vol_set:
	cmp	byte ptr ds:[si],"-"
	jz	p8v_minus
	mov	es:[pcm86_vol],1
	mov	es:[_pcm86_vol],1
	ret
p8v_minus:
	inc	si
	mov	es:[pcm86_vol],0
	mov	es:[_pcm86_vol],0
	ret

;==============================================================================
;	/O option
;==============================================================================
portsel_set:
	call	get_comline_number
	jc	usage
ife	va
	cmp	al,4
	jnc	usage
	mov	es:[port_sel],al
	push	ds
	push	si
	mov	ax,cs
	mov	ds,ax
	call	fm_check
	pop	si
	pop	ds
endif
	ret

;==============================================================================
;	/C option
;==============================================================================
message_clear_set:
	mov	[message_flag],0
	ret

;==============================================================================
;	コマンドラインから数値を読み込む(0-255)
;	IN. DS:SI to COMMAND_LINE
;	OUT.AL	  to NUMBER
;	    CY	  to Error_Flag
;==============================================================================
get_comline_number:
	xor	bx,bx

	lodsb
	sub	al,"0"
	cmp	al,10
	jnc	not_num
	mov	bl,al

num_loop:
	lodsb
	sub	al,"0"
	cmp	al,10
	jnc	numret
	add	bl,bl
	mov	ah,bl
	shl	bl,1
	shl	bl,1
	add	bl,ah
	add	bl,al
	jmp	num_loop
numret:
	dec	si
	mov	al,bl
	clc
	ret
not_num:
	dec	si
	xor	al,al
	stc
	ret

;==============================================================================
;	数値の表示 16bit
;		input	AX
;==============================================================================
print_16:
	xor	dh,dh
	mov	bx,10000
	call	p16_oneset
	mov	bx,1000
	call	p16_oneset
	mov	bx,100
	call	p16_oneset
	mov	bx,10
	call	p16_oneset
	add	al,"0"
	mov	dl,al
	mov	ah,2
	int	21h	;１文字表示
	ret

p16_oneset:
	mov	dl,"0"
onp0:	sub	ax,bx
	jc	onp1
	inc	dl
	jmp	onp0
onp1:	add	ax,bx

	test	dh,dh
	jnz	onp2
	cmp	dl,"0"
	jz	onp3
onp2:
	push	ax
	push	dx
	mov	ah,2
	int	21h	;１文字表示
	pop	dx
	pop	ax
	inc	di
	mov	dh,1
onp3:
	ret

;==============================================================================
;	環境の検索
;			input	si	環境変数名+"="+0
;				es	環境segment
;			output	es:di	環境のaddress
;				cy	1なら無し
;==============================================================================
search_env:
	xor	di,di
	mov	cx,si
se_loop1:
	mov	dx,di
se_loop2:
	cmpsb
	jnz	se_next
	cmp	byte ptr -1[si],"="
	jnz	se_loop2
	clc		;es:di = "="の次を差す
	ret
se_next:
	mov	si,cx
	mov	di,dx
se_loop3:
	inc	di
	cmp	byte ptr es:-1[di],0
	jnz	se_loop3
	cmp	byte ptr es:[di],0
	jnz	se_loop1
	stc
	ret

;==============================================================================
;	Error処理
;==============================================================================
pmderr_1:
	mov	dx,offset pmderror_mes1
	jmp	pmderr_main

pmderr_2:
	mov	dx,offset pmderror_mes2
	jmp	pmderr_main

pmderr_3:
	mov	dx,offset pmderror_mes3
	jmp	pmderr_main

pmderr_4:
	mov	dx,offset pmderror_mes4
	jmp	pmderr_main

pmderr_5:
	mov	dx,offset pmderror_mes5
	jmp	pmderr_main

pmderr_6:
	mov	dx,offset pmderror_mes6
	jmp	pmderr_main

pmderr_7:
	mov	dx,offset pmderror_mes7
	jmp	pmderr_main

pmderr_main:
	mov	ax,cs
	mov	ds,ax
	mov	ah,9
	int	21h
	error_exit	1

;==============================================================================
;	HZ or USAGE
;==============================================================================
hz_usage:
	lodsb
	and	al,11011111b
	cmp	al,"Z"
	jz	hz_set
usage:
	mov	ax,cs
	mov	ds,ax
	cmp	[opt_sp_push],0
	jz	no_kankyo
	print_mes	mes_warning
	print_mes	mes_kankyo
	mov	sp,[opt_sp_push]
	mov	cs:[opt_sp_push],0
	ret

no_kankyo:
	print_mes	mes_usage
	error_exit	255

;==============================================================================
;	/HZ PCM周波数固定設定
;==============================================================================
hz_set:
	call	get_comline_number
	jc	usage
	cmp	al,9
	jnc	usage
if	board2*pcm
	mov	es:[p86_freq],al
	mov	bl,al
	cmp	al,8
	mov	ax,offset pcm_tune_data
	jz	hzset_00
	xor	bh,bh
	mov	ax,288
	mul	bx
	add	ax,offset hzdata
hzset_00:
	push	si
	mov	si,ax			;ds:si=現在のpmd86のpcm_tune_data
	mov	di,offset pcm_tune_data	;es:di=常駐しているpmd86のpcm_tune_data
	mov	cx,288/2
rep	movsw
	pop	si
endif
	ret

;==============================================================================
;	Waitのcheck
;==============================================================================
wait_check:
ife	va
	include	wait.inc
else
	mov	ax,1580		;V30 8MHz (9801VX/RAの値)
	mov	cx,2		;回数
	mov	bx,1580*2	;総clock
	cmp	es:[ongen],0
	jz	va_not_ym2608
	ret
va_not_ym2608:
	mov	cx,3		;回数
	mov	bx,1580*3	;総clock
	ret
endif

;==============================================================================
;	ADPCM Check PRG.include
;==============================================================================
if	board2*adpcm
 ife	ademu
	include	adramchk.asm
 endif
endif

;==============================================================================
;	DATAAREA(非常駐域)
;==============================================================================
if	va
eof	equ	0
else
eof	equ	"$"
endif

mes_warning	db	07,"WARNING: $"
if	board2
 if	pcm+ppz
mes_not_board	db	"YM2608 + PCM not found.",13,10,eof
 else
mes_not_board	db	"YM2608 + ADPCM not found.",13,10,eof
 endif
else
mes_not_board	db	"FM sound board is not installed.",13,10,eof
endif

mes_cut		db	"Resident released.",13,10,eof

mes_title	db	"Professional Music Driver (P.M.D.) for PC9801/88VA Version ",ver
ifdef	_optnam
		db	_optnam
endif
		db	13,10
		db	"Copyright (C)1989,",date," by M.Kajihara(KAJA).",13,10,13,10,eof

mes_int		db	"Int "
int_num		db	", port "
if	va
		db	"44h"
else
port_num	db	" 88h"
endif
		db	" (",eof
mes_int2	db	") used.",13,10,eof
ongen_sel	dw	mes_ongen0,mes_ongen1
mes_ongen0	db	"YM2203",eof
mes_ongen1	db	"YM2608",eof

if	board2*adpcm
pcm_sel		dw	mes_adpcm,mes_only
mes_adpcm	db	" + ADPCM",eof
mes_only	db	" only",eof
endif

if	board2*pcm
mes_pcm		db	" + PCM",eof
endif

mes_ppsdrv	db	"For PPSDRV (INT 64H).",13,10,eof
if	ppz
mes_ppz8	db	"For PPZ8 (INT 7FH).",13,10,eof
endif
mes_wait1	db	"Wait-loop frequency between FM sound source LSI and REG-DATA: ",eof
mes_wait2	db	" times (~= ",eof
mes_wait3	db	" ns)",13,10,eof

cantcut_mes	db	"Resident releasing is currently prohibited. Please release PMD related TSR first.",13,10,eof
pmderror_mes1	db	"The resident and the FM interrupt vector are different.",13,10,eof
pmderror_mes2	db	"The song data buffer must be 1KB or more.",13,10,eof
pmderror_mes3	db	"The total of song + tone + sound effect data must be within 40KB.",13,10,eof
pmderror_mes4	db	"Releasing failed.",13,10,eof
pmderror_mes5	db	"PMD is not residenting.",13,10,eof
pmderror_mes6	db	"An option that cannot be changed is specified.",13,10,eof
pmderror_mes7	db	"Memory cannot be secured.",13,10,eof

mes_exit	db	"Successfully residented in memory.",13,10
		db	"Control PMD using INT 60H.",13,10
		db	eof

mes_key		db	"The song can be stopped and fast-forwarded with the ESC / GRPH key.",13,10,eof

mes_kankyo	db	"The setting of environment variable PMDOPT is incorrect.",13,10,eof

mes_usage	db	"Usage: ",9,"PMD"
if	va
		db	"VA"
 ife	board2
		db	"1"
 endif
else
 if	board2
  if pcm
		db	"86"
  else
   if ppz
		db	"PPZ"
   else
		db	"B2"
   endif
   if ademu
		db	"E"
   endif
  endif
 endif
endif
		db	" [/option[value]][/option[value]]..",13,10
		db	"Options:"
		db	9,"  /Mn  Song data buffer size specification (KB as the unit) Def. = 16",13,10
		db	9,"  /Vn  Tone data buffer size specification (KB as the unit) Def. = 8",13,10
		db	9,"  /En  FM sound effect data buffer size specification (KB as the unit) Def. = 4",13,10
ife	va
		db	9,"  /On  FM sound source port specification 0 = 088H 1 = 188H 2 = 288H 3 = 388H Def. = Auto",13,10
endif
		db	9,"* /DFn FM sound volume adjustment value setting (maximum 0 to minimum 255) Def. = "
if	 board2
		db	"0",13,10
else
		db	"16",13,10
endif
		db	9,"* /DSn SSG sound volume adjustment value setting (maximum 0 to minimum 255) Def. = 0",13,10
if	board2
		db	9,"* /DPn PCM sound volume adjustment value setting (maximum 0 to minimum 255) Def. = 0",13,10
if	ppz
		db	9,"* /DZn PPZ8 volume adjustment value setting (maximum 0 to minimum 255) Def. = 0",13,10
endif
		db	9,"* /DRn RHYTHM sound volume adjustment value setting (maximum 0 to minimum 255) Def. = 0",13,10
		db	9,"* /N(-) Do not play the rhythm sound source simultaneously with the SSG drum (sound)",13,10
endif
		db	9,"* /K(-) Do not stop / fast-forward the song with the ESC / GRPH key",13,10
if	va
		db	9,"* /KEn Setting of keys to be used simultaneously with MSTOP / ESC Def. = 4",13,10
		db	9,"* /KGn FF   Setting of key used at the same time as /GRPH Def. = 4",13,10
		db	9,"* /KRn REW  Setting of key used at the same time as /GRPH Def. = 2",13,10
		db	9,9,"Values: 1=ｶﾅ 2=SHIFT 4=CTRL (Multiple can be specified by adding)",13,10
else
		db	9,"* /KEn Setting of keys to be used simultaneously with MSTOP / ESC Def.=16",13,10
		db	9,"* /KGn FF   Setting of key used at the same time as /GRPH Def. = 6",13,10
		db	9,"* /KRn REW  Setting of key used at the same time as /GRPH Def.=1",13,10
		db	9,9,"Values: 1=SHIFT 2=CAPS 4=ｶﾅ 16=CTRL (Multiple can be specified by adding)",13,10
endif
		db	9,"* /F(-) Don't stop songs after fading out",13,10
		db	9,"* /I(-) Disable interrupt during FM / INT60 interrupt",13,10
		db	9,"* /P(-) Do not support PPSDRV (supports if resident)",13,10
if	ppz
		db	9,"* /Z(-) Do not support PPZ8 (supports if resident)",13,10
endif
		db	9,"* /Wn  Wait-loop frequency between FM sound source LSI and REG-DATA (1 to 255, automatic detection when omitted)",13,10
		db	9,"* /Gn  TimerB value of fast forward by GRPH key Def.=250",13,10
if	board2*adpcm
 ife	ademu
		db	9,"* /An  ADPCM defining speed 0 = High speed 1 = Medium speed 2 = Low speed Def.=Auto",13,10
 endif
endif
if	board2*pcm
		db	9,"* /S(-) Match PCM part specifications to PMDB2 (do not match if /S-)",13,10
		db	9,"* /HZn PCM frequency(0～8,4.13/5.52/8.27/11.03/16.54/22.05/33.08/44.10/自動)",13,10
endif
		db	9,"  /R   release residentment",9,9,"/H   displays help message (this)",13,10
		db	9,"(Options marked with * can be reset after residency - is set in parentheses)",eof

changemes_0	db	"The settings have been changed.",13,10
crlf		db	13,10,eof
changemes_01	db	"　----- Current Settings -----",13,10
		db	"・ Song data buffer size:",eof
changemes_02	db	"KB",13,10,"・ Tone / data buffer size:",eof
changemes_03	db	"KB",13,10,"・ Sound effect data buffer size:",eof
changemes_1	db	"KB",13,10,"・ FM sound volume adjustment value:",eof
changemes_2	db	"・ SSG sound source volume adjustment value:",eof
if	board2
changemes_3	db	"・ PCM sound volume adjustment value:",eof
if	ppz
changemes_3z	db	"・ PPZ8 volume adjustment value:",eof
endif
changemes_4	db	"・ RHYTHM sound source volume adjustment value:",eof
changemes_5	db	"・ Rhythm sound source sounds simultaneously when SSG drum is sounded ",eof
changemes_5a	db	"yes",13,10,eof
changemes_5b	db	"no",13,10,eof
endif
changemes_6	db	"・ Control fast-forward / stop music with GRPH / ESC key ",eof
changemes_6a	db	"yes",13,10,eof
changemes_6b	db	"no",13,10,eof
changemes_7	db	"・ Key settings used simultaneously with MSTOP / ESC:",eof
changemes_8	db	"・ Key settings used simultaneously with FF / GRPH:",eof
changemes_8b	db	"・ Key settings used simultaneously with REW / GRPH:",eof
changemes_9	db	"・ Stop playing music after fade out",eof
changemes_10	db	"・ Disable interrupt during FM / INT60 interrupt",eof
changemes_11	db	"・ Use PPSDRV",eof
changemes_11_	db	"・ Use PPZ8",eof
changemes_12	db	"・Wait-loop frequency between FM sound source LSI and REG-DATA: ",eof
changemes_12a	db	" times(~= ",eof
changemes_12b	db	" ns)",13,10,eof
changemes_13	db	"・TimerB value of fast forward by GRPH key: ",eof
if	board2*adpcm
 ife	ademu
changemes_14	db	"・ADPCM defining speed: ",eof
changemes_14a	db	"High",13,10,eof
changemes_14b	db	"Med.",13,10,eof
changemes_14c	db	"Low",13,10,eof
 endif
endif
if	board2*pcm
changemes_15	db	"・Match PCM part specifications to PMDB2 ",eof
changemes_15a	db	"yes",13,10,eof
changemes_15b	db	"no",13,10,eof
changemes_16	db	"・PCM playback rate: ",eof
changemes_16a	db	"4.13438",eof
		db	"5.51250",eof
		db	"8.26875",eof
		db	"11.0250",eof
		db	"16.5375",eof
		db	"22.0500",eof
		db	"33.0750",eof
		db	"44.1000",eof
		db	"Decide Automaticlly",13,10,eof
changemes_16b	db	"fixed KHz",13,10,eof
endif

vector_table	db	"0",03
		dw	0bh*4		;int0
		db	"6",13
		dw	15h*4		;int6
		db	"4",10
		dw	12h*4		;int4
		db	"5",12
		dw	14h*4		;int5

;	常駐する時のオプション
resident_option	db	"H"
		dw	hz_usage
		db	"M"
		dw	muslng_get
		db	"V"
		dw	voilng_get
		db	"E"
		dw	efclng_get
		db	"K"
		dw	keycheck
		db	"D"
		dw	fmvd_set
		db	"I"
		dw	disint_set
		db	"N"
		dw	notshot_set
		db	"F"
		dw	notstop_set
		db	"P"
		dw	ppsdrv_reset
		db	"Z"
		dw	ppz_reset
		db	"W"
		dw	waitclk_set
		db	"G"
		dw	fftempo_set
		db	"A"
		dw	adpcmwait_set
		db	"S"
		dw	pcm86vol_set
		db	"O"
		dw	portsel_set
		db	"R"
		dw	pmderr_5
		db	"C"
		dw	message_clear_set
		db	0

;	既に常駐済みの時のオプション
status_option	db	"H"
		dw	hz_usage
		db	"R"
		dw	resident_cut_main
		db	"K"
		dw	keycheck
		db	"D"
		dw	fmvd_set
		db	"I"
		dw	disint_set
		db	"N"
		dw	notshot_set
		db	"F"
		dw	notstop_set
		db	"P"
		dw	ppsdrv_reset
		db	"Z"
		dw	ppz_reset
		db	"W"
		dw	waitclk_set
		db	"G"
		dw	fftempo_set
		db	"A"
		dw	adpcmwait_set
		db	"S"
		dw	pcm86vol_set
		db	"M"
		dw	pmderr_6
		db	"V"
		dw	pmderr_6
		db	"E"
		dw	pmderr_6
		db	"Y"
		dw	pmderr_6
		db	"O"
		dw	pmderr_6
		db	"C"
		dw	message_clear_set
		db	0

resident_mes	db	resmes,0
rmes_end	label	byte

pmdopt_txt	db	"PMDOPT=",0

if	board2*pcm
hzdata:	include	hzdata.inc
endif

ife	va
	include	viruschk.inc
endif

epson_flag	db	?		;EPSON機なら1
ife	va
port_sel	db	?		;選択ポート
opn_0eh		db	?
endif

message_flag	db	?
opt_sp_push	dw	?
resident_size	dw	?

pmd	endp

@code	ends
end	pmd

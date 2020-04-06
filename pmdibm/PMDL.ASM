;==============================================================================
;	Professional Music Driver [P.M.D.] for OPL version 4.5
;					FOR PC98  + Sound Orchestra
;					    IBMPC + Sound Blaster
;			By M.Kajihara
;==============================================================================

ifndef	ibm
ibm		=	0	;１の時IBM sound blaster用
endif

ver	equ	"4.6at"
vers	equ	46H
verc	equ	"a"
date	equ	"2020/04/06"

resmes	equ	"PMDL ver.",ver

pmdvector	=	60h		;PMD用の割り込みベクトル

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
		mov	dx,offset qq
		mov	ah,09h
		int	21h
		endm

print_dx	macro
		mov	ah,09h
		int	21h
		endm

_wait1		macro
		mov	cx,[wait_clock]
		loop	$
		endm

_wait2		macro
		mov	cx,[wait_clock2]
		loop	$
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

;==============================================================================
;	定数
;==============================================================================
if	ibm

ms_cmd		equ	20h		; ８２５９マスタポート
ms_msk		equ	21h		; ８２５９マスタ／マスク
sl_cmd		equ	0a0h		; ８２５９スレーブポート
sl_msk		equ	0a1h		; ８２５９スレーブ／マスク
timer_comm	equ	43h		; ８２５３コマンド
timer_data	equ	40h		; ８２５３データ

fnum_c		equ	345
wait1		equ	3353/3*4	; 12 master clock (ns)
wait2		equ	23467/3*4	; 84 master clock (ns)

else

ms_cmd		equ	000h		; ８２５９マスタポート
ms_msk		equ	002h		; ８２５９マスタ／マスク
sl_cmd		equ	008h		; ８２５９スレーブポート
sl_msk		equ	00ah		; ８２５９スレーブ／マスク
timer_comm	equ	77h		; ８２５３コマンド
timer_data	equ	71h		; ８２５３データ
fnum_c		equ	309
wait1		equ	3000/3*4	; 12 master clock (ns)
wait2		equ	21000/3*4	; 84 master clock (ns)

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
	cli
	dec	cs:[int60flag]
	mov	cs:[int60_result],-1
	iret

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
	mov	al,[partb]
	push	ax
	mov	[partb],9
	call	fmmain
	pop	ax
	mov	[partb],al

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
	cmp	[Timer_flag],0
	jz	mstart
	or	[music_flag],1	;TA/TB処理中は 実行しない
	mov	[ah_push],-1
	ret
mstart:	
;------------------------------------------------------------------------------
;	効果音の初期化 & 演奏停止
;------------------------------------------------------------------------------
	pushf
	cli
	and	[music_flag],0feh
	mov	[fm_effec_flag],al
	dec	al
	mov	[fm_effec_num],al
	call	mstop
	popf

;------------------------------------------------------------------------------
;	演奏準備
;------------------------------------------------------------------------------
	call	data_init
	mov	[fadeout_volume],0

	mov	si,[mmlbuf]

	mov	al,-1[si]
	mov	[ongen],al

	cmp	word ptr [si],18h
	jz	not_prg

	mov	bx,18h[si]

	add	bx,si
	mov	[prgdat_adr],bx

	mov	[prg_flg],1
	jmp	prg

not_prg:
	mov	[prg_flg],0

prg:

;------------------------------------------------------------------------------
;	各パートのスタートアドレス及び初期値をセット
;------------------------------------------------------------------------------

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
	mov	keyoff_flag[di],-1	; 現在keyoff中

	mov	volume[di],44		; FM  VOLUME DEFAULT= 44
	inc	dl
	loop	din0

;------------------------------------------------------------------------------
;	Rhythm のアドレス skip
;------------------------------------------------------------------------------
	lodsw

;------------------------------------------------------------------------------
;	OPL初期化
;------------------------------------------------------------------------------
	call	opl_init

;------------------------------------------------------------------------------
;	音楽の演奏を開始
;------------------------------------------------------------------------------
	call	setint
	mov	[play_flag],1
	ret

;==============================================================================
;	DATA AREA の イニシャライズ
;==============================================================================
data_init:
	mov	di,offset part1
	mov	cx,max_part1*type qq
	xor	ax,ax
rep	stosb

	mov	[fadeout_volume],al
	mov	[fadeout_speed],al
	mov	[fadeout_flag],al
	mov	[tieflag],al
	mov	[status],al
	mov	[status2],al
	mov	[syousetu],ax
	mov	[oplcount],al
	mov	[fm_effec_flag],al

	dec	al	;al=255
	mov	[fm_effec_num],al

	mov	[syousetu_lng],96

	ret

;==============================================================================
;	opl INIT
;==============================================================================
opl_init:
	mov	dx,0480h
	call	oplset
	mov	dx,0800h
	call	oplset
	mov	dx,0bd00h
	call	oplset

	mov	si,offset part_data_table
	mov	cx,9
	mov	dl,1
initvoice_loop:
	lodsw
	mov	di,ax
	mov	[partb],dl
	mov	bx,offset PSG_voice
	push	cx
	push	dx
	call	neiroset2
	pop	dx
	pop	cx
	inc	dl
	loop	initvoice_loop

	ret

;==============================================================================
;	ＭＵＳＩＣ　ＳＴＯＰ
;==============================================================================
mstop_f:
	mov	[fadeout_flag],0
	cmp	[Timer_flag],0
	jz	mstop
	or	[music_flag],2	;TA/TB処理中は 実行しない
	mov	[ah_push],-1
	ret
mstop:	
	pushf
	cli
	and	[music_flag],0fdh
	xor	al,al
	mov	[play_flag],al
	mov	[pause_flag],al
	mov	[fadeout_speed],al
	dec	al
	mov	[status2],al
	mov	[fadeout_volume],al
	popf
	call	silence
	ret

;==============================================================================
;	MUSIC PLAYER MAIN [FROM TIMER-B]
;==============================================================================
mmain:
	mov	[loop_work],3

	mov	di,offset part1
	mov	[partb],1
	call	fmmain		;FM1

	mov	di,offset part2
	mov	[partb],2
	call	fmmain		;FM2

	mov	di,offset part3
	mov	[partb],3
	call	fmmain		;FM3

	mov	di,offset part4
	mov	[partb],4
	call	fmmain		;FM4

	mov	di,offset part5
	mov	[partb],5
	call	fmmain		;FM5

	mov	di,offset part6
	mov	[partb],6
	call	fmmain		;FM6

	mov	di,offset part7
	mov	[partb],7
	call	fmmain		;FM7

	mov	di,offset part8
	mov	[partb],8
	call	fmmain		;FM8

	mov	di,offset part9
	mov	[partb],9
	call	fmmain		;FM9

	cmp	[loop_work],0
	jnz	mmain_loop
	ret

mmain_loop:
	mov	cx,max_part2
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

;==============================================================================
;	ＦＭ音源演奏メイン
;==============================================================================
fmmain:
	mov	si,[di]	; si = PART DATA ADDRESS
	or	si,si
	jnz	fmmain_main
	ret
fmmain_main:
	cmp	partmask[di],0
	jnz	fmmain_nonplay

	; 音長 -1
	dec	leng[di]
	mov	al,leng[di]

	; KEYOFF CHECK & Keyoff
	test	keyoff_flag[di],1	; 既にkeyoffしたか？
	jnz	mp0
	cmp	al,qdat[di]		; Q値 => 残りLength値時 keyoff
	jc	mp00
	jnz	mp0
mp00:	cmp	byte ptr [si],0fbh	; '&'が直後にあったらkeyoffしない
	jz	mp0
	call	keyoff			; ALは壊さない
	mov	keyoff_flag[di],-1

mp0:	; LENGTH CHECK
	or	al,al
	jnz	mpexit
mp10:	and	lfoswi[di],0f7h		; Porta off

mp1:	; DATA READ
	lodsb
	cmp	al,80h
	jc	mp2
	jnz	mp15

	; END OF MUSIC [ "L"があった時はそこに戻る ]
	dec	si
	mov	loopcheck[di],3
	mov	bx,partloop[di]
	or	bx,bx
	jz	mpexit

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	mp1

mp15:	; ELSE COMMANDS
	call	commands
	jmp	mp1

mp2:	; F-NUMBER SET
	call	lfoinit
	call	oshift
	call	fnumset

	lodsb
	mov	leng[di],al
	call	calc_q

porta_return:
	call	volset
	mov	keyoff_flag[di],0
	call	otodasi
	cmp	fnum[di],0
	jz	mpext3
	cmp	volpush[di],0	;volpushが設定されていて
	jz	mpext3
	dec	[volpush_flag]	;flagが０の時は
	jz	mpext3
	inc	[volpush_flag]
	mov	volpush[di],0	;volpush解除
	call	volset
	jmp	mpext3

mpexit:	; LFO & Portament & Fadeout 処理 をして終了
	mov	cl,lfoswi[di]
	test	cl,3
	jz	not_lfo
	call	lfo
not_lfo:
	test	cl,9
	jz	vols

	test	cl,8
	jz	not_porta
	call	porta_calc
not_porta:
	call	otodasi

vols:
	cmp	[fadeout_speed],0
	jnz	vol_set
	test	lfoswi[di],2
	jz	mpext3
vol_set:
	call	volset
	;
mpext3:
	mov	[di],si

	mov	al,[loop_work]
	and	al,loopcheck[di]
	mov	[loop_work],al
	mov	[volpush_flag],0
mpext5:
	ret

;==============================================================================
;	Q値の計算
;==============================================================================
calc_q:
	push	ax
	cmp	qdatb[di],0
	jz	cq_a
	mov	al,leng[di]
	mul	qdatb[di]
	add	ah,qdata[di]
	mov	qdat[di],ah
	pop	ax
	ret
cq_a:
	mov	al,qdata[di]
	mov	qdat[di],al
	pop	ax
	ret

;==============================================================================
;	ＦＭ音源演奏メイン：パートマスクされている時
;==============================================================================
fmmain_nonplay:
	dec	leng[di]
	jnz	mnp_ret2

	test	partmask[di],2		;bit1(FM効果音中？)をcheck
	jz	fmmnp_1
	cmp	[fm_effec_flag],0	;効果音終了したか？
	jnz	fmmnp_1
	and	partmask[di],0fdh	;bit1をclear
	jz	mp10			;partmaskが0なら復活させる

fmmnp_1:
	lodsb
	cmp	al,80h
	jnz	fmmnp_2

	; END OF MUSIC [ "L"があった時はそこに戻る ]
	dec	si
	mov	loopcheck[di],3
	mov	bx,partloop[di]
	or	bx,bx
	jz	mnp_ret

	; "L"があった時
	mov	si,bx
	mov	loopcheck[di],1
	jmp	fmmnp_1

fmmnp_2:
	jc	fmmnp_3
	call	commands
	jmp	fmmnp_1

fmmnp_3:
	mov	fnum[di],0	;休符に設定
	lodsb
	mov	leng[di],al	;音長設定

mnp_ret:
	mov	[di],si
	mov	al,[loop_work]
	and	al,loopcheck[di]
	mov	[loop_work],al
	mov	[tieflag],0
	mov	[volpush_flag],0
	ret

mnp_ret2:
	mov	al,[loop_work]
	and	al,loopcheck[di]
	mov	[loop_work],al
	ret

;==============================================================================
;	各種特殊コマンド処理
;==============================================================================
commands:
	mov	bx,offset cmdtbl
	not	al
	add	al,al
	xor	ah,ah
	add	bx,ax
	mov	ax,cs:[bx]
	call	ax
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
	dw	lfoswitch
	dw	jump4		;0F0H
	dw	comy		;0EFH
	dw	jump1
	dw	jump1
	; FOR SB2
	dw	jump1		;panset
	dw	jump1		;rhykey
	dw	jump1		;rhyvs
	dw	jump1		;rpnset
	dw	jump1		;rmsvs		;0E8H
	;追加 for V2.0
	dw	comshift2	;0E7H
	dw	jump1		;rmsvs_sft	;0E6H
	dw	jump2		;rhyvs_sft	;0E5H
	;
	dw	jump1		;0E4H
	;追加 for V2.3
	dw	comvolup2	;0E3H
	dw	comvoldown2	;0E2H
	;追加 for V2.4
	dw	jump1		;hlfo_set	;0E1H
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
	dw	jump1		;ssg_efct_set	;0d4h
	dw	fm_efct_set	;0d3h
	dw	fade_set	;0d2h
	;
	dw	jump1
	dw	jump1		;0d0h
	;
	dw	jump1		;slotmask_set		;0cfh
	dw	jump6		;0ceh
	dw	jump5		;0cdh
	dw	jump1		;0cch
	dw	lfowave_set	;0cbh
	dw	lfo_extend	;0cah
	dw	jump1		;0c9h
	dw	jump3		;slotdetune_set		;0c8h
	dw	jump3		;slotdetune_set2	;0c7h
	dw	jump6		;fm3_extpartset		;0c6h
	dw	volmask_set	;0c5h
	dw	comq2		;0c4h
	dw	jump2		;panset_ex	;0c3h
	dw	jump1
	dw	jump0		;0c1h,sular
	dw	c0_sp		;0c0h
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

c0_sp:
	lodsb
	cmp	al,2
	jnc	jump1
	ret

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
;	音量マスクslotの設定
;==============================================================================
volmask_set:
	lodsb
	and	al,03h
	jz	vms_zero
	ror	al,1		;最上位2BITに移動
	ror	al,1
	or	al,0fh		;０以外を指定した=下位4BITを１にする
	mov	volmask[di],al
	ret
vms_zero:
	mov	al,carrier[di]
	mov	volmask[di],al	;キャリア位置を設定
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
;	LFOのWave選択
;==============================================================================
lfowave_set:
	lodsb
	mov	lfo_wave[di],al
	ret

;==============================================================================
;	fm effect
;==============================================================================
fm_efct_set:
	lodsb
	or	al,al
	jz	fes_off
	mov	bl,[partb]
	push	bx
	push	si
	push	di
	call	fm_effect_on
	pop	di
	pop	si
	pop	ax
	mov	[partb],al
	ret
fes_off:
	mov	bl,[partb]
	push	bx
	push	si
	push	di
	call	fm_effect_off
	pop	di
	pop	si
	pop	ax
	mov	[partb],al
	ret

;==============================================================================
;	fadeout
;==============================================================================
fade_set:
	mov	[fadeout_flag],1
	lodsb
	call	fout
	ret

;==============================================================================
;	LFO depth +- set
;==============================================================================
mdepth_set:
	lodsb
	mov	mdspd[di],al
	mov	mdspd2[di],al
	lodsb
	cmp	[ongen],0
	jnz	mdepthset_00
	cmp	[partb],7
	jc	mdepthset_00
	sar	al,1
	sar	al,1	;PSG>FM (1/4)
mdepthset_00:
	mov	mdepth[di],al
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

	lodsb
	call	oshift
	call	fnumset
	mov	bx,fnum[di]	;bx=ポルタメント先のfnum値

	pop	cx
	mov	fnum[di],cx	;cx=ポルタメント元のfnum値

	xor	ax,ax
	push	cx
	push	bx
	and	ch,1ch
	and	bh,1ch
	sub	bh,ch		;先のoctarb - 元のoctarb
	jz	not_octarb
	sar	bh,1
	sar	bh,1
	mov	al,bh
	cbw			;ax=octarb差
	mov	bx,fnum_c
	imul	bx		;(dx)ax = 157h * octarb差
not_octarb:
	pop	bx
	pop	cx

	and	cx,3ffh
	and	bx,3ffh
	sub	bx,cx
	add	ax,bx		;ax=157h*octarb差 + 音程差

	mov	bl,[si]
	inc	si
	mov	leng[di],bl
	call	calc_q

	xor	bh,bh
	cwd
	idiv	bx		;ax=(127h*ovtarb差 + 音程差) / 音長

	mov	porta_num2[di],ax	;商
	mov	porta_num3[di],dx	;余り
	or	lfoswi[di],8		;Porta ON

	pop	ax	;porta
	pop	ax	;commands
	jmp	porta_return

porta_notset:
	lodsb	;最初の音程を読み飛ばす	(Mask時)
	ret

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
	cmp	[ongen],0
	jnz	vouf_00
	cmp	[partb],7
	jc	vouf_00
	add	al,al
	add	al,al	;PSG>FM (4倍)
vouf_00:
	add	al,volume[di]
	cmp	al,64
	jc	vo_vset	
	mov	al,63
vo_vset:inc	al
	mov	volpush[di],al
	mov	[volpush_flag],1
	ret

vol_one_down:
	lodsb
	cmp	[ongen],0
	jnz	vod_00
	cmp	[partb],7
	jc	vod_00
	add	al,al
	add	al,al	;PSG>FM (4倍)
vod_00:
	mov	ah,al
	mov	al,volume[di]
	sub	al,ah
	jnc	vo_vset
	xor	al,al
	jmp	vo_vset

;==============================================================================
;	ＦＭ音源ハードＬＦＯのスイッチ（Ｖ２．４拡張分）
;==============================================================================
hlfo_onoff:
	lodsb
	and	al,3
	ror	al,1
	ror	al,1
	mov	dl,al
	mov	dh,0bdh
	jmp	oplset

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
	jz	neiroset
	ret

;==============================================================================
;	COMMAND 'q' [STEP-GATE CHANGE]
;==============================================================================
comq:
	lodsb
	mov	qdata[di],al
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
	cmp	[ongen],0	;OPN用data?
	jnz	comv_exec2
	cmp	[partb],7	;PSGパート?
	jc	comv_exec2
	xor	bh,bh
	mov	bl,al
	add	bx,offset psg_vol_table
	mov	al,[bx]
comv_exec2:
	sub	al,64
	jnc	comv_exec
	xor	al,al
comv_exec:
	mov	volume[di],al
	ret

;==============================================================================
;	COMMAND 'T' [TEMPO CHANGE]
;==============================================================================
comt:	lodsb
	cmp	al,251
	jnc	comt_sp
	mov	bl,al
timset:	mov	ax,[tempo_mul]
	neg	bl
	xor	bh,bh
	mul	bx
	jnc	timset_exec
	mov	ax,-1
timset_exec:
	mov	[tempo_d],ax
	ret
comt_sp:
	lodsb
	ret

;==============================================================================
;	COMMAND '&' [ﾀｲ,ｽﾗｰ]
;==============================================================================
comtie:
	mov	[tieflag],1
	ret

;==============================================================================
;	COMMAND 'D' [ﾃﾞﾁｭｰﾝ]
;==============================================================================
comd:	lodsw
	cmp	[ongen],0
	jnz	comd_exec
	cmp	[partb],7
	jc	comd_exec
	sar	ax,1	;1/4 (PSG->FM)
comd_exec:
	cmp	[ongen],2
	jz	comd_exec2
	sar	ax,1	;1/2 (OPN,OPM->OPL)
comd_exec2:
	mov	detune[di],ax
	ret

;==============================================================================
;	COMMAND 'DD' [相対ﾃﾞﾁｭｰﾝ]
;==============================================================================
comdd:	lodsw
	cmp	[ongen],0
	jnz	comdd_exec
	cmp	[partb],7
	jc	comdd_exec
	sar	ax,1	;1/4 (PSG->FM)
comdd_exec:
	cmp	[ongen],2
	jz	comdd_exec2
	sar	ax,1	;1/2 (OPN,OPM->OPL)
comdd_exec2:
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
	or	al,al
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
;	COMMAND ')' [VOLUME UP]
;==============================================================================
	;	ＦＯＲ　ＦＭ
comvolup:
	mov	al,volume[di]
	add	al,4
volupck:
	cmp	al,64
	jc	vset
	mov	al,63
vset:	mov	volume[di],al
	ret

	;数字付き
comvolup2:
	lodsb
	cmp	[ongen],0
	jnz	comvolup2_exec
	cmp	[partb],7
	jc	comvolup2_exec
	add	al,al
	add	al,al	;PSG>FM (4倍)
comvolup2_exec:
	add	al,volume[di]
	jmp	volupck

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
	cmp	[ongen],0
	jnz	comvoldown2_exec
	cmp	[partb],7
	jc	comvoldown2_exec
	add	ah,ah
	add	ah,ah	;PSG>FM (4倍)
comvoldown2_exec:
	sub	al,ah
	jnc	vset
	xor	al,al
	jmp	vset

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
	cmp	[ongen],0
	jnz	lfoset_exec
	cmp	[partb],7
	jc	lfoset_exec
	sar	al,1	;1/4 (PSG->FM)
lfoset_exec:
	cmp	[ongen],2
	jz	lfoset_exec2
	sar	al,1	;1/2 (OPN,OPM->OPL)
lfoset_exec2:
	mov	step[di],al
	mov	step2[di],al
	lodsb
	mov	time[di],al
	mov	time2[di],al
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

;==============================================================================
;	'y' COMMAND [ｺｲﾂｶﾞ ｲﾁﾊﾞﾝ ｶﾝﾀﾝ]
;==============================================================================
comy:
	lodsw
	mov	dh,al
	mov	dl,ah
	call	oplset
	ret

;==============================================================================
;	SHIFT[di] 分移調する
;==============================================================================
oshift:
oshiftp:
	cmp	al,0fh	;休符
	jnz	os_00
osret:
	ret
os_00:
	mov	dl,shift[di]
	or	dl,dl
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
	ret

;==============================================================================
;	ＦＭ　BLOCK,F-NUMBER SET
;		INPUTS	-- AL [KEY#,0-7F]
;==============================================================================
fnumset:
	mov	ah,al
	and	ah,0fh
	cmp	ah,0fh
	jz	fnrest	; ｷｭｳﾌ ﾅﾗ FNUM ﾆ 0 ｦ ｾｯﾄ

	;
	; BLOCK/FNUM CALICULATE
	;
	mov	ch,al
	ror	ch,1
	ror	ch,1
	and	ch,1ch	; ch=BLOCK

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
	mov	word ptr fnum[di],0
	ret

;==============================================================================
;	Set [ FNUM/BLOCK + DETUNE + LFO + KEYON_f ]
;==============================================================================
otodasi:
	mov	ax,fnum[di]
	or	ax,ax
	jnz	od_00
	ret
od_00:
	mov	cx,ax
	and	cx,1c00h	; cx=BLOCK
	and	ah,3		; ax=FNUM

	;
	; Portament/LFO/Detune SET
	;
	add	ax,porta_num[di]
	test	lfoswi[di],1
	jz	od_not_lfo
	add	ax,lfodat[di]
od_not_lfo:
	add	ax,detune[di]
	call	fm_block_calc

	;
	; SET BLOCK/FNUM TO opl
	;	input CX:AX
	mov	dh,[partb]
	or	ax,cx	;AX=block/Fnum
	cmp	keyoff_flag[di],0
	jnz	od_not_keyon
	or	ah,20h
od_not_keyon:
	add	dh,0a0h-1
	mov	dl,al
	pushf
	cli
	call	oplset
	add	dh,16
	mov	dl,ah
	mov	keyondat[di],dl
	call	oplset
	popf
od_exit:
	ret

;==============================================================================
;	FM音源のdetuneでオクターブが変わる時の修正
;		input	CX:block / AX:fnum+detune
;		output	CX:block / AX:fnum
;==============================================================================
fm_block_calc:
od0:	or	ax,ax
	js	od1
	cmp	ax,fnum_c
	jc	od1
	;
	cmp	ax,fnum_c*2
	jc	od2
	;
	add	cx,0400h	;oct.up
	cmp	cx,2000h
	jz	od05
	sub	ax,fnum_c
	jmp	od0
od05:	; ﾓｳ ｺﾚｲｼﾞｮｳ ｱｶﾞﾝﾅｲﾖﾝ
	mov	cx,1c00h
	mov	ax,fnum_c*2
	ret
	;
od1:	
	sub	cx,0400h	;oct.down
	jc	od15
	add	ax,fnum_c
	jmp	od0
od15:	; ﾓｳ ｺﾚｲｼﾞｮｳ ｻｶﾞﾝﾅｲﾖﾝ
	xor	cx,cx
	mov	ax,fnum_c
	;
od2:	ret

;==============================================================================
;	ＦＭ　ＶＯＬＵＭＥ　ＳＥＴ
;==============================================================================
volset:	
	mov	al,volpush[di]
	or	al,al
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
	or	al,al
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
	neg	al
	mul	cl
	mov	cl,ah

;------------------------------------------------------------------------------
;	音量をcarrierに設定 & 音量LFO処理
;		input cl to Volume[0-127]
;------------------------------------------------------------------------------
fmvs:
	xor	bh,bh
	mov	bl,-1
	xor	ax,ax
	or	cl,cl	;音量0?
	jz	fmvs_not_vollfo

	test	lfoswi[di],2
	jz	fmvs_not_vollfo
	mov	bh,volmask[di]
	and	bh,bl			;bh=音量LFOを設定するSLOT xx000000b
	mov	ax,lfodat[di]		;ax=音量LFO変動値(sub)

fmvs_not_vollfo:
	not	cl
	and	cl,3fh			;cl=carrierに設定する音量(add)
	and	bl,carrier[di]		;bl=音量   を設定するSLOT xx000000b

	push	bx
	xor	bx,bx
	mov	bl,[partb]
	add	bx,offset port_map-1
	mov	dh,[bx]			;DH=reg
	add	dh,40h
	pop	bx

	mov	dl,slot1[di]
	call	volset_slot

	add	dh,3
	mov	dl,slot2[di]
	call	volset_slot

	ret

;------------------------------------------------------------------------------
;	スロット毎の計算 & 出力
;			in.	dl	元のTL値
;				dh	Outするレジスタ
;				bl	音量   を設定するslotmask(bit7)
;				bh	音量LFOを設定するslotmask(bit7)
;				cl	音量   値(add)
;				ax	音量LFO値
;------------------------------------------------------------------------------
volset_slot:
	mov	ch,dl
	and	ch,0c0h
	and	dl,03fh

	rol	bh,1
	jc	vsl_AB
	rol	bl,1
	jc	vsl_A
	ret
vsl_A:
;	音量のみ設定
	add	dl,cl
	cmp	dl,64
	jc	vsl_Aset
	mov	dl,63
vsl_Aset:
	or	dl,ch
	jmp	oplset

vsl_AB:
	rol	bl,1
	jnc	vsl_B	;音量設定はしない
;	音量設定
	add	dl,cl
	cmp	dl,64
	jc	vsl_B
	mov	dl,63
	or	dl,ch
	jmp	oplset	;音量0の時は音量LFO変更はしない
vsl_B:
;	音量LFO設定
	mov	ch,dh	;push dh
	xor	dh,dh
	sub	dx,ax
	jns	vsl_Bp
	mov	dh,ch
	xor	dl,dl	;-1～-32768になった
	or	dl,ch
	jmp	oplset
vsl_Bp:	cmp	dx,64
	mov	dh,ch
	jc	vsl_Bset
	mov	dl,63	;+128～+32767になった
vsl_Bset:
	or	dl,ch
	jmp	oplset

;==============================================================================
;	KEY OFF
;		don't Break AL
;==============================================================================
keyoff:
	cmp	fnum[di],0
	jnz	kof1
	ret			; ｷｭｳﾌ ﾉ ﾄｷ
kof1:
	mov	dh,0b0h-1
	add	dh,[partb]
	mov	dl,keyondat[di]
	and	dl,01fh
	jmp	oplset

;==============================================================================
;	音色の設定
;		INPUTS	-- [PARTB]			
;			-- dl [TONE_NUMBER]
;			-- di [PART_DATA_ADDRESS]
;==============================================================================
neiroset:
	call	silence_fmpart
	call	toneadr_calc

;==============================================================================
;	音色設定メイン
;==============================================================================
neiroset2:
;------------------------------------------------------------------------------
;	AL/FBを設定
;------------------------------------------------------------------------------
	mov	dh,0c0h-1
	add	dh,[partb]
	mov	dl,8[bx]
	call	oplset
	and	dl,1	;dl=algo

;------------------------------------------------------------------------------
;	Carrierの位置を調べる (VolMaskにも設定)
;------------------------------------------------------------------------------
check_carrier:
	mov	al,dl
	add	al,al
	inc	al		; ALG0 = 01 ALG1 = 11
	ror	al,1
	ror	al,1		; 最上位2BITに移動
	test	volmask[di],0fh
	jnz	not_set_volmask	; Volmask値が設定されていた場合は設定しない
	mov	volmask[di],al
not_set_volmask:
	mov	carrier[di],al
	mov	ah,al
	not	ah		;AH=TL用のmask

;------------------------------------------------------------------------------
;	各音色パラメータを設定 (TLはモジュレータのみ)
;------------------------------------------------------------------------------
	push	bx
	xor	bh,bh
	mov	bl,[partb]
	add	bx,offset port_map-1
	mov	dh,[bx]
	add	dh,20h
	pop	bx

;	AM/VIB/EGT/KSR/ML
	mov	dl,[bx]
	inc	bx
	call	oplset
	add	dh,3
	mov	dl,[bx]
	inc	bx
	call	oplset
	add	dh,29

;	TL
	mov	dl,[bx]
	inc	bx
	rol	ah,1
	jnc	ns_nsa
	call	oplset
ns_nsa:	add	dh,3
	mov	dl,[bx]
	inc	bx
	rol	ah,1
	jnc	ns_nsb
	call	oplset
ns_nsb:	add	dh,29

;	AR/DR
	mov	dl,[bx]
	inc	bx
	call	oplset
	add	dh,3
	mov	dl,[bx]
	inc	bx
	call	oplset
	add	dh,29

;	SL/RR
	mov	dl,[bx]
	inc	bx
	call	oplset
	add	dh,3
	mov	dl,[bx]
	call	oplset

;------------------------------------------------------------------------------
;	SLOT毎のTLをワークに保存
;------------------------------------------------------------------------------
	mov	ax,-5[bx]
	mov	word ptr slot1[di],ax
	ret

;==============================================================================
;	TONE DATA START ADDRESS を計算
;		input	dl	tone_number
;		output	bx	address
;==============================================================================
toneadr_calc:
	cmp	di,offset part_e
	jz	prgdat_get2
	cmp	[ongen],2		;OPL用DATA?
	jz	tc_00
	mov	bx,offset PSG_voice	;じゃなければPSG音色をset
	ret
tc_00:
	cmp	[prg_flg],0
	jnz	prgdat_get
	mov	bx,[tondat]
	mov	al,dl
	xor	ah,ah
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	bx,ax
	ret

prgdat_get2:
	mov	bx,[prgdat_adr2]	;FM効果音の場合
	jmp	gpd_loop
prgdat_get:
	mov	bx,[prgdat_adr]
gpd_loop:
	cmp	[bx],dl
	jz	gpd_exit
	add	bx,10
	jmp	gpd_loop
gpd_exit:
	inc	bx
	ret

;==============================================================================
;	[PartB]のパートの音を完璧に消す (TL=63 and RR=15 and KEY-OFF)
;==============================================================================
silence_fmpart:
	push	dx

	push	bx
	xor	bh,bh
	mov	bl,[partb]
	add	bx,offset port_map-1
	mov	dh,[bx]
	add	dh,40h
	pop	bx

	mov	dl,63
	call	oplset	; TL = 63
	add	dh,3
	call	oplset	; TL = 63
	add	dh,29

	mov	dl,15
	call	oplset	; SR = 15
	add	dh,3
	call	oplset	; SR = 15
	add	dh,29

	call	oplset	; RR = 15
	add	dh,3
	call	oplset	; RR = 15

	call	kof1	; KEY OFF
	pop	dx
	ret

;==============================================================================
;	ＬＦＯ処理
;		Don't Break cl
;==============================================================================
lfo:	
lfop:
	cmp	delay[di],0
	jz	lfo1
	dec	delay[di]
lfo_ret:
	ret
lfo1:
	test	extendmode[di],2	;TimerAと合わせるか？
	jz	lfo_main		;そうじゃないなら無条件にlfo処理
	mov	ch,[TimerAtime]
	sub	ch,[lastTimerAtime]
	jz	lfo_ret			;前回の値と同じなら何もしない
lfo_loop:
	call	lfo_main
	dec	ch
	jnz	lfo_loop
	ret

lfo_main:
	cmp	lfo_wave[di],2
	jz	lfo_kukei

	cmp	speed[di],1
	jz	lfo2
	dec	speed[di]
	ret
lfo2:
	mov	al,speed2[di]
	mov	speed[di],al
	
	cmp	lfo_wave[di],0
	jnz	not_sankaku

;	三角波
	mov	al,step[di]
	cbw
	add	lfodat[di],ax
	jnz	lfo21
	call	md_inc
lfo21:
	mov	al,time[di]
	cmp	al,255
	jz	lfo3
	dec	al
	jnz	lfo3
	mov	al,time2[di]
	add	al,al
	mov	time[di],al
	mov	al,step[di]
	neg	al
	mov	step[di],al
	ret
lfo3:
	mov	time[di],al
	ret

not_sankaku:
	cmp	lfo_wave[di],1
	jnz	not_nokogiri
;	ノコギリ波
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

lfo_kukei:
;	矩形波
	mov	al,step[di]
	imul	time[di]
	mov	lfodat[di],ax
	cmp	speed[di],1
	jz	kk_lfo2
	dec	speed[di]
	ret
kk_lfo2:
	mov	al,speed2[di]
	mov	speed[di],al
	call	md_inc
	neg	step[di]
	ret

not_nokogiri:
;	ランダム波
	mov	al,step[di]
	or	al,al
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
	mov	al,step[di]
	or	al,al
	jns	mdi22
	sub	al,mdepth[di]
	jmp	mdi23
mdi22:
	add	al,mdepth[di]
mdi23:
	jo	md_exit
	cmp	al,80h
	jz	md_exit
	mov	step[di],al
md_exit:
	ret

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
	mov	bx,32767
	div	bx
	ret
seed	dw	?

;==============================================================================
;	ＬＦＯの初期化
;==============================================================================
lfoinit:
	mov	ah,al	; ｷｭｰﾌ ﾉ ﾄｷ ﾊ INIT ｼﾅｲﾖ
	and	ah,0fh
	cmp	ah,0fh
	jnz	lfin0
	mov	[tieflag],0
	ret
lfin0:
	mov	porta_num[di],0	;ポルタメントは初期化

	cmp	[tieflag],1	; ﾏｴ ｶﾞ & ﾉ ﾄｷ ﾓ INIT ｼﾅｲ｡
	jnz	lfin1
	mov	[tieflag],0
	ret

;==============================================================================
;	ＬＦＯ初期化
;==============================================================================
lfin1:
	test	lfoswi[di],3
	jz	li_ret

	test	lfoswi[di],4
	jnz	li_ret

lfoinit_main:
	mov	lfodat[di],0
	push	di
	push	si
	mov	si,offset delay2
	add	si,di
	add	di,offset delay
	movsw
	movsw
	pop	si
	pop	di
	cmp	lfo_wave[di],2
	jnz	li_ret
	cmp	delay[di],0
	jnz	li_ret
	push	ax
	call	lfo	;矩形波でdelay=0の場合はすぐにlfo変更
	pop	ax
li_ret:
	ret

;==============================================================================
;	FADE IN / OUT ROUTINE
;==============================================================================
fadeout:
	cmp	[pause_flag],1	;pause中はfadeoutしない
	jz	fade_exit
	mov	al,[fadeout_speed]
	or	al,al
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
	mov	bl,200
	call	timset		; TIMER speed SET
	call	settempo_b

	popf

	;
	;　小節カウンタリセット
	;
	xor	ax,ax
	mov	[oplcount],al
	mov	[syousetu],ax
	mov	[syousetu_lng],96

	ret

;==============================================================================
;	ALL SILENCE
;==============================================================================
silence:
	mov	dx,600fh
	mov	cx,16h
	cmp	[fm_effec_flag],1
	jnz	sil_rel_loop
	mov	cx,12h
sil_rel_loop:
	call	oplset		;SR = 15
	add	dh,20h
	call	oplset		;RR = 15
	sub	dh,1fh
	loop	sil_rel_loop

	cmp	[fm_effec_flag],1
	jnz	sil_kof
	mov	dx,730fh
	call	oplset
	mov	dx,740fh
	call	oplset
	mov	dx,930fh
	call	oplset
	mov	dx,940fh
	call	oplset

sil_kof:
	mov	dx,0b000h
	mov	cx,9
	cmp	[fm_effec_flag],1
	jnz	sil_kof_loop
	dec	cx
sil_kof_loop:
	call	oplset		;Keyoff
	inc	dh
	loop	sil_kof_loop

	ret

;==============================================================================
;	SET DATA TO opl
;		INPUTS ---- DH,DL
;==============================================================================
oplset:
	push	ax
	push	bx
	push	cx
	push	dx
	mov	bx,dx

	mov	dx,[fm_port1]
	pushf
	cli
	_wait2
	mov	al,bh
	out	dx,al
	_wait1
	mov	dx,[fm_port2]
	mov	al,bl
	out	dx,al
	popf

	pop	dx
	pop	cx
	pop	bx
	pop	ax
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
	jnc	non_chk_Timer
	cmp	[Timer_flag],0
	jnz	reint_error
non_chk_Timer:
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

;	再入check用code / bit0=Timer_int 1=INT60
reint_chk	db	2,2,0,3,3,0,0,0,0,0,0,0,3,3,0,3
		db	0,0,0,0,0,0,0,0,3,0,3,3,3,0,3,0
		db	0

int60_jumptable	label	word
	dw	mstart_f	;0
	dw	mstop_f		;1
	dw	fout		;2
	dw	nothing		;3
	dw	nothing		;4
	dw	get_ss		;5
	dw	get_musdat_adr	;6
	dw	get_tondat_adr	;7
	dw	get_fv		;8
	dw	drv_chk		;9
	dw	get_status	;A
	dw	get_efcdat_adr	;B
	dw	fm_effect_on	;C
	dw	fm_effect_off	;D
	dw	nothing		;E
	dw	nothing		;F
	dw	get_workadr	;10
	dw	get_fmefc_num	;11
	dw	get_255		;12
	dw	set_fm_int	;13
	dw	set_efc_int	;14
	dw	get_255		;15
	dw	get_65535	;16
	dw	get_255		;17
	dw	nothing		;18
	dw	set_fv		;19
	dw	pause_on	;1A
	dw	pause_off	;1B
	dw	ff_music	;1C
	dw	get_memo	;1D
	dw	part_mask	;1E
	dw	get_fm_int	;1F
	dw	get_efc_int	;20
int60_max	equ	20h

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
	mov	al,cs:[fadeout_volume]
	mov	[al_push],al
	ret

set_fv:			;19
	mov	cs:[fadeout_volume],al
	ret

drv_chk:
	mov	[al_push],3
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

get_workadr:
	mov	ax,cs
	mov	[ds_push],ax
	mov	[dx_push],offset part_data_table
	ret

get_fmefc_num:
	mov	al,[fm_effec_num]
	mov	[al_push],al
	ret

set_fm_int:
	mov	ax,[ds_push]
	mov	[fmint_seg],ax
	mov	bx,[dx_push]
	mov	[fmint_ofs],bx
	or	[rescut_cant],80h	;常駐解除禁止フラグをセット
	or	ax,bx
	jnz	sfi_ret
	and	[rescut_cant],7fh
sfi_ret:
	ret

set_efc_int:
	mov	ax,[ds_push]
	mov	[efcint_seg],ax
	mov	bx,[dx_push]
	mov	[efcint_ofs],bx
	or	[rescut_cant],40h	;常駐解除禁止フラグをセット
	or	ax,bx
	jnz	sei_ret
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

;==============================================================================
;	Pause on
;==============================================================================
pause_on:
	cmp	[play_flag],1
	jnz	pauon_exit
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

	mov	cx,9
	mov	bx,offset part_data_table+16
po_neiroset_loop:
	push	cx
	push	bx

	mov	di,[bx]
	mov	dl,voicenum[di]
	mov	[partb],cl
	call	neiroset

	pop	bx
	pop	cx
	sub	bx,2
	loop	po_neiroset_loop

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
	jnz	getmemo_errret	;音色がないfile=メモのアドレス所得不能
	add	si,18h
	mov	si,[si]
	add	si,[mmlbuf]
	sub	si,4
	cmp	word ptr 2[si],40h	;Ver4.0 & 00Hの場合
	jz	getmemo_exec
	cmp	byte ptr 3[si],0feh
	jnz	getmemo_errret	;Ver.4.1以降は 0feh
	cmp	byte ptr 2[si],41h
	jc	getmemo_errret	;MC version 4.1以前だったらError
getmemo_exec:
	cmp	byte ptr 2[si],42h	;Ver.4.2以降か？
	jc	getmemo_oldver41
	inc	al			;ならalを +1 (0FFHで#PPSFile)
getmemo_oldver41:

	mov	si,[si]
	add	si,[mmlbuf]
	inc	al

getmemo_loop:
	mov	dx,[si]
	or	dx,dx
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
;						1:既にその小節は過ぎてる
;						2:曲が終わっちゃった
;==============================================================================
ff_music:
	cmp	[status2],255
	jz	ffm_exit2
	cmp	dx,[syousetu]
	jbe	ffm_exit1

	mov	ah,[fadeout_volume]
	mov	[fadeout_volume],255

ffm_loop:
	push	ax
	push	dx
	pushf
	cli
	call	mmain
	call	syousetu_count
	popf
	pop	dx
	pop	ax
	cmp	[status2],255
	jz	ffm_exit2
	cmp	dx,[syousetu]
	jnbe	ffm_loop

	mov	[fadeout_volume],ah
	xor	al,al
	jmp	ffm_exit
ffm_exit1:
	mov	al,1
	jmp	ffm_exit
ffm_exit2:
	mov	al,2
ffm_exit:
	mov	[al_push],al
	ret

;==============================================================================
;	パートのマスク & Keyoff
;==============================================================================
part_mask:
	mov	ah,al
	and	ah,7fh
	cmp	ah,10
	jnc	pm_ret
	or	al,al
	js	part_on

	xor	bh,bh
	mov	bl,al
	add	bx,bx
	add	bx,offset part_data_table
	mov	di,[bx]
	mov	dl,partmask[di]
	or	partmask[di],1
	or	dl,dl
	jnz	pm_ret		;既にマスクされていた
	cmp	[play_flag],0
	jz	pm_ret		;曲が止まっている

	inc	al
	cmp	al,10
	jnz	pm_exec
	dec	al		;FM効果音CH

pm_exec:
	pushf
	cli
	mov	[partb],al
	call	silence_fmpart	;音を完璧に消す
	popf
pm_ret:
	ret

;==============================================================================
;	パートのマスク解除 & FM音源音色設定	in.AH=part番号
;==============================================================================
part_on:
	mov	al,ah
	xor	bh,bh
	mov	bl,al
	add	bx,bx
	add	bx,offset part_data_table
	mov	di,[bx]
	cmp	partmask[di],0
	jz	po_ret		;マスクされてない
	and	partmask[di],0feh
	jnz	po_ret		;効果音でまだマスクされている
	cmp	[play_flag],0
	jz	po_ret		;曲が止まっている

	inc	al
	cmp	al,10
	jnz	po_exec
	dec	al		;FM効果音CH

po_exec:
	mov	dl,voicenum[di]
	pushf
	cli
	mov	[partb],al
	call	neiroset
	popf
po_ret:
	ret

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
	dw	nothing		;E
	dw	nothing		;F
	dw	get_workadr	;10
	dw	get_255		;11
	dw	get_255		;12
	dw	nothing		;13
	dw	nothing		;14
	dw	get_65535	;15
	dw	get_255		;16
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

	mov	di,offset part9
	mov	[partb],9
	or	partmask[di],2		; Part Mask

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
	mov	volume[di],44		; FM  VOLUME DEFAULT= 44

	popf
	ret

;==============================================================================
;	消音
;==============================================================================
fm_effect_off:
	pushf
	cli

	mov	[fm_effec_num],-1
	mov	[fm_effec_flag],0	; 効果音止めてね

	mov	di,offset part9
	mov	dl,voicenum[di]		; 音色を
	mov	[partb],9		; 効果音パートに
	call	neiroset		; 定義する
	xor	dl,dl
	call	fmvs

	popf
	ret

;==============================================================================
;	opl Interrupt Routine
;==============================================================================
oplint:	
	cli
	cld
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
;	8259/Timerをmask
;------------------------------------------------------------------------------
	mov	dx,[mask_adr]
	in	al,dx
	jmp	$+2
	or	al,[mask_data]
	out	dx,al

;------------------------------------------------------------------------------
;	EOIを送る
;------------------------------------------------------------------------------
	mov	dx,[eoi_adr]
	mov	al,[eoi_data]
	out	dx,al		;(特殊EOI)TimerのINTのみEOI

;------------------------------------------------------------------------------
;	OPL処理
;------------------------------------------------------------------------------
	call	FM_Timer_main

;------------------------------------------------------------------------------
;	opl割り込み終了
;------------------------------------------------------------------------------
;------------------------------------------------------------------------------
;	8259/Timer Mask解除
;------------------------------------------------------------------------------
	mov	dx,[mask_adr]
	in	al,dx
	jmp	$+2
	and	al,[mask_data2]
	out	dx,al

;------------------------------------------------------------------------------
;	おしまい
;------------------------------------------------------------------------------
	pop	ds
	pop	dx
	mov	ss,cs:[ss_push]
	mov	sp,cs:[sp_push]
	pop	ax

	cmp	cs:[maskpush],0
	jz	int5_fook
	iret

;------------------------------------------------------------------------------
;	常駐前に使用していたint5ルーチンを処理
;------------------------------------------------------------------------------
int5_fook:
	push	ax
	mov	ax,cs:[TimerB_speed]
	add	cs:[timer_clock],ax
	pop	ax
	jc	dword ptr cs:[int5ofs]
	iret

;==============================================================================
;	FM TimerA/B 処理 Main
;		 pushしてあるレジスタは ax/dx/ds のみ。
;==============================================================================
FM_Timer_main:
;------------------------------------------------------------------------------
;	割り込み許可
;------------------------------------------------------------------------------
	cmp	[disint],1
	jz	not_sti
	sti
not_sti:

	push	cx
	push	bx
	push	si
	push	di
	push	es

	mov	bx,cs
	mov	es,bx

	call	TimerB_main

	mov	ax,[TimerB_speed]
	add	ax,[vrtc_clock]
	mov	[vrtc_clock],ax
	jc	exec_timerA
exec_timerA_loop:
	cmp	ax,[vrtc_num]
	jc	not_exec_timerA
exec_timerA:
	mov	ax,[vrtc_num]
	sub	[vrtc_clock],ax
	call	TimerA_main
	mov	ax,[vrtc_clock]
	jmp	exec_timerA_loop
not_exec_timerA:

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
	mov	[Timer_flag],1

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

	cmp	[play_flag],1
	jnz	not_play

	call	mmain
	call	settempo_b
	call	syousetu_count
	mov	al,[TimerAtime]
	mov	[lastTimerAtime],al
not_play:
	mov	ax,[fmint_seg]
	or	ax,[fmint_ofs]
	jz	TimerB_nojump
	call	dword ptr [fmint_ofs]
TimerB_nojump:

	mov	[Timer_flag],0

	ret

;==============================================================================
;	TimerAの処理[メイン]
;==============================================================================
TimerA_main:
	mov	[Timer_flag],1

	inc	[TimerAtime]

	mov	al,[TimerAtime]
	and	al,7
	jnz	not_fade
	call	fadeout		;Fadeout処理

not_fade:
	cmp	[fm_effec_flag],0
	jz	not_fmeffec
	call	fm_efcplay	;FM効果音処理
not_fmeffec:

	cmp	[key_check],0
	jz	vtc000
	cmp	[play_flag],0
	jz	vtc000

if	ibm
	mov	ax,40h
else
	xor	ax,ax
endif
	mov	es,ax
ife	ibm
	mov	bx,052ah
endif
	mov	al,[esc_sp_key]
if	ibm
	and	al,byte ptr es:[17h]
else
	and	al,byte ptr es:0eh[bx]
endif
	cmp	al,[esc_sp_key]
	jnz	vtc000
if	ibm
	call	search_esc
	jnc	vtc000
else
	test	byte ptr es:[bx],00000001b	;esc
	jz	vtc000
endif

	mov	ax,cs
	mov	es,ax
	or	[music_flag],2		;次のTimerBでMSTOP

vtc000:
	mov	ax,[efcint_seg]
	or	ax,[efcint_ofs]
	jz	TimerA_nojump
	call	dword ptr [efcint_ofs]
TimerA_nojump:

	mov	[Timer_flag],0

	ret

if	ibm
;==============================================================================
;	IBM用 ESCキーがキーバッファにあるかどうかcheck
;		return:	CY
;==============================================================================
search_esc:
	mov	ax,40h
	mov	es,ax
	mov	bx,es:[1ah]	;開始ポインタ
	mov	ax,es:[1ch]	;終了ポインタ
	mov	cx,es:[80h]	;バッファ先頭ポインタ
	mov	dx,es:[82h]	;バッファ終端ポインタ

	cmp	bx,cx
	jz	se_00
	mov	bx,dx 
se_00:
	dec	bx		;１文字分戻す
	dec	bx		;

esc_check_loop:
	cmp	bx,dx		;終端までいったか？
	jnz	se_01
	mov	bx,cx		;先頭に戻す
se_01:
	cmp	bx,ax		;終了までいったか？
	jz	se_clc_ret	;押されていない
	cmp	byte ptr es:1[bx],01h	;ESC code
	jz	se_stc_ret
	inc	bx
	inc	bx
	jmp	esc_check_loop

se_clc_ret:
	clc
	ret
se_stc_ret:
	stc
	ret
endif
;==============================================================================
;	小節のカウント
;==============================================================================
syousetu_count:
	mov	bx,offset oplcount
	inc	byte ptr [bx]
	mov	al,[syousetu_lng]
	cmp	al,[bx]
	jnz	sc_ret
	xor	al,al
	mov	[bx],al
	inc	[syousetu]
sc_ret:	ret

;==============================================================================
;	テンポ設定
;==============================================================================
settempo_b:
	cmp	[key_check],0
	jz	stb00

	mov	cx,es
if	ibm
	mov	ax,040h
else
	xor	ax,ax
endif
	mov	es,ax
ife	ibm
	mov	bx,052ah
endif
	mov	al,[grph_sp_key]
if	ibm
	and	al,byte ptr es:[17h]
else
	and	al,byte ptr es:0eh[bx]
endif
	cmp	al,[grph_sp_key]
	jnz	stb00
if	ibm
	test	byte ptr es:[17h],00001000b	;alt
else
	test	byte ptr es:0eh[bx],00001000b	;grph
endif
	mov	es,cx
	jz	stb00

	mov	bx,[ff_tempo]
	jmp	stb01
stb00:

	mov	bx,[tempo_d]
stb01:	mov	[TimerB_speed],bx

	mov	dx,timer_comm
	mov	al,36h
	pushf
	cli
	out	dx,al

if	ibm
	jmp	$+2
	jmp	$+2
else
	out	5fh,al
endif
	mov	dx,timer_data
	mov	al,bl
	out	dx,al
if	ibm
	jmp	$+2
	jmp	$+2
else
	out	5fh,al
endif
	mov	al,bh
	out	dx,al
	popf
	ret

;==============================================================================
;	音階 DATA
;==============================================================================
fnum_data	label	word
if	ibm
	dw	345	; C
	dw	365	; D-
	dw	387	; D
	dw	410	; E-
	dw	434	; E
	dw	460	; F
	dw	488	; G-
	dw	517	; G
	dw	547	; A-
	dw	580	; A
	dw	615	; B-
	dw	651	; B
else
	dw	309	; C
	dw	327	; D-
	dw	346	; D
	dw	367	; E-
	dw	389	; E
	dw	412	; F
	dw	436	; G-
	dw	462	; G
	dw	490	; A-
	dw	519	; A
	dw	550	; B-
	dw	583	; B
endif

;==============================================================================
;	OPL音色出力用ポートmap
;==============================================================================

port_map	db	0,1,2,8,9,10,16,17,18	;Part-Port 変換table

;==============================================================================
;	PSGパート > FMパート 音量変換用table
;==============================================================================

psg_vol_table	db	0
		db	127-2ah	;VOLUME	00
		db	127-28h	;VOLUME	01
		db	127-25h	;VOLUME	02
		db	127-22h	;VOLUME	03
		db	127-20h	;VOLUME	04
		db	127-1dh	;VOLUME	05
		db	127-1ah	;VOLUME	06
		db	127-18h	;VOLUME	07
		db	127-15h	;VOLUME	08
		db	127-12h	;VOLUME	09
		db	127-10h	;VOLUME	10
		db	127-0dh	;VOLUME	11
		db	127-0ah	;VOLUME	12
		db	127-08h	;VOLUME	13
		db	127-05h	;VOLUME	14
		db	127-02h	;VOLUME	15
;;;		db	127-00h	;VOLUME	16

;==============================================================================
;	ＰＳＧ音色
;==============================================================================
PSG_voice	db	022h,021h,01Bh,000h,0F0h,0F0h,00Fh,00Fh,00Eh

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
loop_work	db	?		;Loop Work
prgdat_adr2	dw	?		;曲データ中音色データ先頭番地(効果音用)
lastTimerAtime	db	?		;一個前の割り込み時のTimerATime値
music_flag	db	?		;B0:次でMSTART 1:次でMSTOP のFlag
eoi_adr		dw	?		;EOIをsendするI/Oアドレス
eoi_data	db	?		;EOI用のデータ
mask_adr	dw	?		;MaskをするI/Oアドレス
mask_data	db	?		;Mask用のデータ(OrでMask)
mask_data2	db	?		;Mask用のデータ(AndでMask解除)
ss_push		dw	?		;FMint中 SSのpush
sp_push		dw	?		;FMint中 SPのpush
tempo_mul	dw	?		;機種別 TimerB>汎用Timer数値
timer_clock	dw	?		;Timer clock over check
vrtc_num	dw	?		;機種別 VSync相当のTimer値
vrtc_clock	dw	?		;Vrtc clock over check
ongen		db	?		;演奏中の曲の対象音源

	even
;	
open_work	label	byte
mmlbuf		dw	?		;Musicdataのaddress+1
tondat		dw	?		;Voicedataのaddress
efcdat		dw	?		;FM  Effecdataのaddress
tempo_d		dw	?		;tempo (TIMER)
TimerB_speed	dw	?		;TimerBの現在値(=ff_tempoならff中)
ff_tempo	dw	?		;早送り時のTimerB値
		dw	0
fmint_ofs	dw	?		;FM割り込みフックアドレス offset
fmint_seg	dw	?		;FM割り込みフックアドレス address
efcint_ofs	dw	?		;効果音割り込みフックアドレス offset
efcint_seg	dw	?		;効果音割り込みフックアドレス address
prgdat_adr	dw	?		;曲データ中音色データ先頭番地
		dw	0
		dw	0
		db	0
board		db	?		;FM音源ボードあり／なしflag
key_check	db	?		;ESC/GRPH key Check flag
fm_voldown	db	?		;FM voldown 数値
		db	0
		db	0
		db	0
prg_flg		db	?		;曲データに音色が含まれているかflag
		db	0
status		db	?		;status1
status2		db	?		;status2
		db	0
fadeout_speed	db	?		;Fadeout速度
fadeout_volume	db	?		;Fadeout音量
		db	?
syousetu_lng	db	?		;小節の長さ
oplcount	db	?		;最短音符カウンタ
TimerAtime	db	?		;TimerAカウンタ
		db	0
		db	0
		db	0
fm_effec_num	db	?		;発声中のFM効果音番号
fm_effec_flag	db	?		;FM効果音発声中flag (1)
disint		db	?		;FM割り込み中に割り込みを禁止するかflag
		db	0
		dw	0
		dw	0
		db	0
		dw	0
		dw	0
		dw	0
		db	0
		db	0
		db	0
		db	6 dup (0)
		db	0
		dw	0
		dw	0
		dw	0
play_flag	db	?		;play flag
pause_flag	db	?		;pause flag
fade_stop_flag	db	0		;Fadeout後 MSTOPするかどうかのフラグ
		db	0
		db	0
Timer_flag	db	0		;TimerA割り込み中？フラグ
int60flag	db	0		;INT60H割り込み中？フラグ
int60_result	db	0		;INT60Hの実行ErrorFlag
		db	0
esc_sp_key	db	?		;ESC +?? Key Code
grph_sp_key	db	?		;GRPH+?? Key Code
rescut_cant	db	?		;常駐解除禁止フラグ
		dw	0
		dw	0
		dw	0
wait_clock	dw	?		;FM ADDRESS-DATA間 Loop $の回数
wait1_clock	dw	?		;loop $ １個の速度
wait_clock2	dw	?		;FM DATA-ADDRESS間 Loop $の回数
		db	0
		db	0
		db	0
fadeout_flag	db	?		;内部からfoutを呼び出した時1
		db	0
		db	0
		db	0
syousetu	dw	?		;小節カウンタ
		db	0		;FM音源割り込み中？フラグ
		db	0		;OPN-PORT 22H に最後に出力した値(hlfo)
		db	0		;現在のテンポ(clock=48 tの値)
		db	0		;現在のテンポ(同上/保存用)
		db	0		;GRPH+?? (rew) Key Code
		db	0		;int_fookのflag B0:TB B1:TA
		db	0		;normal:0 前方SKIP中:1 後方SKIP中:2
		db	0		;FM voldown 数値 (保存用)
		db	0		;PSG voldown 数値 (保存用)
		db	0		;PCM voldown 数値 (保存用)
		db	0		;RHYTHM voldown 数値 (保存用)
		db	0		;PCM86の音量をSPBに合わせるか? (保存用)
		db	0		;mstartする時に１にするだけのflag
		db	13 dup(0)	;曲のFILE名バッファ
		db	0		;曲データバッファサイズ(KB)
		db	0		;音色データバッファサイズ(KB)
		db	0		;効果音データバッファサイズ(KB)
		db	0		;リズム音源 shot inc flag (BD)
		db	0		;リズム音源 shot inc flag (SD)
		db	0		;リズム音源 shot inc flag (CYM)
		db	0		;リズム音源 shot inc flag (HH)
		db	0		;リズム音源 shot inc flag (TOM)
		db	0		;リズム音源 shot inc flag (RIM)
		db	0		;リズム音源 dump inc flag (BD)
		db	0		;リズム音源 dump inc flag (SD)
		db	0		;リズム音源 dump inc flag (CYM)
		db	0		;リズム音源 dump inc flag (HH)
		db	0		;リズム音源 dump inc flag (TOM)
		db	0		;リズム音源 dump inc flag (RIM)

;	演奏中のデータエリア

_not	equ	0

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
lfoswi		db	?       ; 1 LFOSW. D0/tone D1/vol D2/同期 D3/porta
volpush		db	? 	; 1 Volume PUSHarea
mdepth		db	?	; 1 M depth
mdspd		db	?	; 1 M speed
mdspd2		db	?	; 1 M speed_2
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
		db	?
extendmode	db	?	; 1 B1/Detune B2/LFO B3/Env Normal/Extend Flag
		db	? 	; 1 FM Panning + AMD + PMD
		db	?       ; 1 PSG PATTERN [TONE/NOISE/MIX]
voicenum	db	?	; 1 音色番号
loopcheck	db	?	; 1 ループしたら１ 終了したら３
carrier		db	?	; 1 FM Carrier
slot1		db	?       ; 1 SLOT 1 ﾉ TL
slot2		db	?       ; 1 SLOT 2 ﾉ TL
		db	?
		db	?
		db	?
keyondat	db	?	; 1 Keyon_portの内容
lfo_wave	db	?	; 1 LFOの波形
partmask	db	?	; 1 PartMask bit0:通常/1:効果音/2:NECPCM用
keyoff_flag	db	?	; 1 KeyoffしたかどうかのFlag
volmask		db	?	; 1 音量LFOのマスク
qdata		db	?	; 1 qの値
qdatb		db	?	; 1 Qの値
		db	?	; 1 HardLFO delay
		db	?	; 1 HardLFO delay Counter
		dw	?       		; 2 LFO DATA
		db	?       ; 1 LFO	[DELAY] 
		db	?       ; 1	[SPEED]
		db	?       ; 1	[STEP]
		db	?       ; 1	[TIME]
		db	?       ; 1	[DELAY_2]
		db	?       ; 1	[SPEED_2]
		db	?       ; 1	[STEP_2]
		db	?       ; 1	[TIME_2]
		db	?	; 1 M depth
		db	?	; 1 M speed
		db	?	; 1 M speed_2
		db	?	; 1 LFOの波形
		db	?	; 1 音量LFOのマスク
		db	?	; 1 M depth Counter (変動値)
		db	?	; 1 M depth Counter
		db	?	; 1 M depth Counter (変動値)
		db	?	; 1 M depth Counter
		db	?	; 1 演奏中の音階データ (0ffh:rest)
		db	?	; 1 Slot delay
		db	?	; 1 Slot delay counter
		db	?	; 1 Slot delay Mask
		db	?	; 1 音色のalg/fb
		db	?	; 1 新音階/休符データを処理したらinc
		db	?	;dummy
qq	ends

max_part1	equ	10	;０クリアすべきパート数
max_part2	equ	10	;初期化すべきパート数

	even

	dw	open_work
part_data_table:
	dw	part1
	dw	part2
	dw	part3
	dw	part4
	dw	part5
	dw	part6
	dw	part7
	dw	part8
	dw	part9
	dw	part_e

part1	db	type qq dup( ? )
part2	db	type qq dup( ? )
part3	db	type qq dup( ? )
part4	db	type qq dup( ? )
part5	db	type qq dup( ? )
part6	db	type qq dup( ? )
part7	db	type qq dup( ? )
part8	db	type qq dup( ? )
part9	db	type qq dup( ? )
part_e	db	type qq dup( ? )

	even
	db	512 dup (?)
_stack:
dataarea	label	word

;==============================================================================
;	ＰＭＤコマンドスタート
;==============================================================================
comstart:
	cld
	push	ds

	mov	es,ds:[002ch]	;ES=環境のsegment
	resident_cut		;環境を解放

	mov	ax,cs
	mov	ds,ax
	print_mes	mes_title	;タイトル表示
	pop	ds

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

	cmp	es:[board],0
	jz	change_main

;	常駐していた/音源有りの時は FMint vectorがoplint:と同一かどうかcheck
	mov	si,es:_vector[bx]
	push	ds
	xor	ax,ax
	mov	ds,ax
	mov	ax,ds:[si]
	pop	ds
	cmp	ax,offset oplint
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

	mov	[mmldat_lng],16		;Default 16K
	mov	[voicedat_lng],4	;Default 4K
	mov	[effecdat_lng],4	;Default 4K
	mov	[key_check],1		;Keycheck ON
	mov	[fm_voldown],0		;FM_VOLDOWN

	mov	[disint],0		;INT Disable FLAG
	mov	[rescut_cant],0		;常駐解除禁止 FLAG
	mov	[fade_stop_flag],1	;FADEOUT後MSTOPするか FLAG
if	ibm
	mov	[grph_sp_key],4		;ALT +CTRL key code
	mov	[esc_sp_key],4		;ESC +CTRL key code
else
	mov	[grph_sp_key],10h	;GRPH+CTRL key code
	mov	[esc_sp_key],10h	;ESC +CTRL key code
endif
	mov	[ff_tempo],14*256
	mov	[music_flag],0

if	ibm
	mov	[tempo_mul],344
	mov	[vrtc_num],21307
else
	push	es
	xor	ax,ax
	mov	es,ax
	test	byte ptr es:[501h],80h
	pop	es
	mov	ax,708		;5MHz系
	mov	bx,43886	;
	jz	tm_set
	mov	ax,575		;8MHz系
	mov	bx,35657	;
tm_set:	mov	[tempo_mul],ax
	mov	[vrtc_num],bx
endif
	call	wait_set

	pop	ds	; DS = PSP segment
	mov	ax,cs
	mov	es,ax	; ES = Code segment

;==============================================================================
;	オプションを取り込む
;==============================================================================
	mov	si,offset 80h

	cmp	byte ptr [si],0
	jz	resmes_set		;オプション無し
	inc	si			;ds:si = command line

	mov	bx,offset resident_option
	call	set_option

	mov	al,es:[mmldat_lng]
	cmp	al,6
	jc	pmderr_2
	add	al,es:[voicedat_lng]
	jc	pmderr_3
	add	al,es:[effecdat_lng]
	jc	pmderr_3
	cmp	al,50+1
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

	mov	ax,cs
	mov	es,ax	;ES = Code segment

;==============================================================================
;	効果音/FMINT/EFCINTを初期化
;==============================================================================
	xor	ax,ax
	mov	[fmint_seg],ax
	mov	[fmint_ofs],ax
	mov	[efcint_seg],ax
	mov	[efcint_ofs],ax
	mov	[fm_effec_flag],al
	dec	al
	mov	[fm_effec_num],al

;==============================================================================
;	曲データ，音色データ格納番地を設定
;==============================================================================

	mov	ax,offset dataarea+1
	mov	[mmlbuf],ax
	dec	ax
	mov	bx,ax

	mov	ah,[mmldat_lng]
	xor	al,al
	shl	ax,1
	shl	ax,1
	add	ax,bx
	mov	[tondat],ax
	mov	bx,ax

	cmp	[voicedat_lng],0
	jz	not_vinit

	mov	di,ax		;es:di=voice buffer
	xor	cl,cl
	mov	ch,[voicedat_lng]
	shl	cx,1
	xor	ax,ax
rep	stosw			;音色エリアの初期化

not_vinit:
	mov	ah,[voicedat_lng]
	xor	al,al
	shl	ax,1
	shl	ax,1
	add	ax,bx
	mov	[efcdat],ax

	cmp	[effecdat_lng],0
	jz	not_einit
	; Init Effect Data

	mov	di,ax		;es:di=effect buffer
	mov	ax,0100h
	mov	cx,128
rep	stosw
	mov	byte ptr [di],80h
not_einit:

;==============================================================================
;	ＦＭ音源のcheck (INT/PORT選択)
;==============================================================================
	cli
	call	fm_check

	xor	ax,ax
	mov	es,ax
	cmp	[board],0
	jz	not_set_oplvec

;==============================================================================
;	ＯＰＮ　割り込みベクトル　退避
;==============================================================================
	mov	bx,[vector]
	les	bx,es:[bx]
	mov	[int5ofs],bx
	mov	[int5seg],es

;==============================================================================
;	ＯＰＮ　割り込みベクトル　設定
;==============================================================================
	mov	es,ax
	mov	bx,[vector]
	mov	es:[bx],offset oplint
	mov	es:[bx+2],cs
not_set_oplvec:

;==============================================================================
;	INT60 割り込みベクトル　退避
;==============================================================================
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
	call	oplint_start
	sti

;==============================================================================
;	Wait回数表示
;==============================================================================
	print_mes	mes_wait1
	mov	ax,[wait_clock]
	call	print_16
	print_mes	mes_wait2
	mov	ax,[wait_clock]
	mul	[wait1_clock]
	call	print_16
	print_mes	mes_wait3

;==============================================================================
;	常駐して終了
;==============================================================================
	print_mes	mes_exit

	cmp	[key_check],0
	jz	not_key_mes
	print_mes	mes_key
not_key_mes:

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

	resident_exit	;常駐終了

;==============================================================================
;	ＦＭ音源ボード装着/PORT/INTチェック
;==============================================================================
fm_check:
;------------------------------------------------------------------------------
;	ポートを設定
;------------------------------------------------------------------------------
	call	port_check
	jc	not_fmboard

	mov	ax,[fm_port1]
	add	ah,"0"
	mov	[port_num],ah

;------------------------------------------------------------------------------
;	INT番号を設定
;------------------------------------------------------------------------------
	mov	[int_num],30h
	mov	[int_level],0
	mov	[vector],8*4

	print_mes	mes_int

;------------------------------------------------------------------------------
;	MASK/EOIの出力先の設定
;------------------------------------------------------------------------------
mask_eoi_set:
	mov	[mask_adr],ms_msk
	mov	[mask_data],1		;Maskするデータ
	mov	[mask_data2],0feh	;Mask解除するデータ
	mov	[eoi_adr],ms_cmd	;EOIはMasterにSendする
	mov	[eoi_data],20h		;特殊EOI + 割り込みベクトル が入る

	mov	ax,cs
	mov	es,ax
	mov	[board],1
	ret

not_fmboard:
	mov	[board],0
	print_mes	mes_not_board
	ret

;==============================================================================
;	Timer割り込み許可処理
;==============================================================================
oplint_start:
	cmp	[board],0
	jz	not_oplint_start	;ボードがない
	mov	ax,cs
	mov	es,ax
	call	data_init
	call	opl_init
	call	mstop
	call	setint
	mov	al,[int_level]
	call	intset
not_oplint_start:
	ret

;==============================================================================
;	OPLのFM音源ポートを調べる
;		output	fm_port1/fm_port2
;			cy=1でボード無し
;==============================================================================
port_check:
;------------------------------------------------------------------------------
;	98の場合
;------------------------------------------------------------------------------
ife	ibm
	mov	dx,088h
	mov	cx,4
port_check_loop:
;	x88hに音源があるか？
	in	al,dx	;dx= x88h
	mov	ah,al
	add	dx,2
	in	al,dx
	sub	dx,2
	and	al,ah
	inc	al
	jz	port_chk_next

;	x8chに音源があるか？
	add	dx,4	;dx= x8ch
	in	al,dx
	mov	ah,al
	add	dx,2
	in	al,dx
	sub	dx,6
	and	al,ah
	inc	al
	jz	port_chk_next

;	OPNAか？
	mov	al,0ffh
	out	dx,al	;dx= x88h
	push	cx
	mov	cx,100
	loop	$
	pop	cx
	add	dx,2
	in	al,dx
	sub	dx,2
	dec	al
	jz	port_chk_next

;	opl発見
	add	dx,4
	mov	[fm_port1],dx
	add	dx,2
	mov	[fm_port2],dx
	mov	[board],1
	clc
	ret

port_chk_next:
	inc	dh	
	loop	port_check_loop
else
;------------------------------------------------------------------------------
;	IBMの場合
;------------------------------------------------------------------------------
	mov	dx,388h
	in	al,dx
	mov	ah,al
	inc	dx
	in	al,dx
	and	al,ah
	inc	al
	jz	pc_error
	mov	[fm_port1],388h
	mov	[fm_port2],389h
	mov	[board],1
	clc
	ret
endif
;------------------------------------------------------------------------------
;	音源が見つからなかった
;------------------------------------------------------------------------------
pc_error:
	mov	[board],0
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

;	FM音源    音量調整値
	print_mes	changemes_1
	mov	al,es:[fm_voldown]
	call	put8
	print_mes	crlf

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
	call	put8
	print_mes	crlf

;	GRPHと同時に使用するキー設定値
	print_mes	changemes_8
	mov	al,es:[grph_sp_key]
	call	put8
	print_mes	crlf

;	フェードアウト後に曲の演奏を停止するか
	print_mes	changemes_9
	mov	dx,offset changemes_9a
	cmp	es:[fade_stop_flag],0
	jnz	change9_put
	mov	dx,offset changemes_9b
change9_put:
	print_dx

;	FM/INT60割り込み中に割り込みを禁止するか
	print_mes	changemes_10
	mov	dx,offset changemes_10a
	cmp	es:[disint],0
	jnz	change10_put
	mov	dx,offset changemes_10b
change10_put:
	print_dx

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
	mov	ax,es:[ff_tempo]
	mov	al,ah
	xor	ah,ah
	call	print_16
	print_mes	crlf

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
	or	ah,ah
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
	mov	ah,11h
	int	pmdvector
	inc	al
	jz	rs_non_fmefc
	mov	ah,0dh
	int	pmdvector	;ＦＭ効果音の停止
rs_non_fmefc:

	mov	ah,1
	int	pmdvector	;演奏の停止

	call	vector_ret

	sti			;割り込み許可
	jc	pmderr_4	;解放できない

	print_mes	mes_cut
	msdos_exit

;==============================================================================
;　	opl他割り込み切り放し
;==============================================================================
vector_ret:
	mov	dx,timer_comm
	mov	al,36h
	out	dx,al

	mov	dx,timer_data
	xor	al,al
	out	dx,al
if	ibm
	jmp	$+2
	jmp	$+2
else
	out	5fh,al
endif
	out	dx,al			; Timerの速度を 0000Hにする

	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]	; ES:BX=PMD seg/offset

	cmp	es:[board],0
	jz	not_cut_oplvec

	mov	al,es:_int_level[bx]
	call	intpop			; opl割り込みマスクを元に戻す

	;Timer割り込みベクトルを元に戻す
	xor	ax,ax
	mov	ds,ax
	mov	cx,es:_int5ofs[bx]
	mov	dx,es:_int5seg[bx]
	push	bx
	mov	bx,es:_vector[bx]
	mov	ds:[bx],cx
	mov	ds:[bx+2],dx
	pop	bx

not_cut_oplvec:
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
	jmp	$+2
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
	jz	option
	cmp	al,"-"
	jz	option
	cmp	al," "
	jc	so_ret
	jz	set_option
	jmp	usage
so_ret:	ret

option:
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
	cmp	dl,"F"
	jnz	usage

;==============================================================================
;	/DF option
;==============================================================================
	mov	es:[fm_voldown],al
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
	mov	es:[grph_sp_key],al
	ret

;==============================================================================
;	/KE option
;==============================================================================
esc_special_set:
	call	get_comline_number
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
;	/W option
;==============================================================================
waitclk_set:
	call	get_comline_number
	jc	wait_newset
	or	al,al
	jz	usage
	xor	ah,ah
	mov	es:[wait_clock],ax
	mov	bx,ax
	add	ax,ax	;x2
	add	ax,bx	;x3
	add	ax,ax	;x6
	add	ax,bx	;ax=ax*7
	mov	es:[wait_clock2],ax
	ret
wait_newset:
	call	wait_set
	ret

;==============================================================================
;	/G option
;==============================================================================
fftempo_set:
	call	get_comline_number
	jc	fft_newset
	or	al,al
	jz	usage
	mov	ah,al
	xor	al,al
	mov	es:[ff_tempo],ax
	ret
fft_newset:
	mov	es:[ff_tempo],14*256
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

	or	dh,dh
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
;	Wait clock 設定処理
;==============================================================================
wait_set:
	call	waittest
	push	ds
	mov	bx,cs
	mov	ds,bx
	mov	[wait1_clock],ax

	xor	cx,cx
	xor	dx,dx

	mov	bx,wait1
ws_loop:
	inc	cx
	add	dx,ax
	cmp	dx,bx
	jc	ws_loop
	mov	[wait_clock],cx

	mov	bx,wait2
ws_loop2:
	inc	cx
	add	dx,ax
	cmp	dx,bx
	jc	ws_loop2

	mov	[wait_clock2],cx

	pop	ds
	ret

	include	wait.inc

;==============================================================================
;	Error処理
;==============================================================================
pmderr_1:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes1
	error_exit	1
pmderr_2:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes2
	error_exit	1
pmderr_3:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes3
	error_exit	1
pmderr_4:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes4
	error_exit	1
pmderr_5:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes5
	error_exit	1
pmderr_6:
	mov	ax,cs
	mov	ds,ax
	print_mes	pmderror_mes6
	error_exit	1

;==============================================================================
;	USAGE
;==============================================================================
usage:
	mov	ax,cs
	mov	ds,ax
	print_mes	mes_usage
	msdos_exit

;==============================================================================
;	DATAAREA(非常駐域)
;==============================================================================
eof	equ	"$"
if	ibm
grph	equ	"ALT"
else
grph	equ	"GRPH"
endif

mes_not_board	db	07,"WARNING:"
		db	"no OPL FM Sound Board is found.",13,10,eof

mes_cut		db	"Removed from memory.",13,10,eof

mes_title	db	"Music Driver P.M.D. for "
if	ibm
		db	"IBMPC"
else
		db	"PC9801"
endif
		db	"/OPL Version ",ver,13,10
		db	"Copyright (C)1989,",date," by M.Kajihara(KAJA).",13,10,13,10,eof

mes_int		db	"IRQ "
int_num		db	", port "
if	ibm
port_num	db	" 88H"
else
port_num	db	" 8CH"
endif
		db	" is used.",13,10,eof

mes_wait1	db	"FM LSI wait-loop times between REG-DATA: ",eof
mes_wait2	db	" (about ",eof
mes_wait3	db	"ns)",13,10,eof

cantcut_mes	db	"Now PMD is prohibitted to remove from memory.",13,10,eof
pmderror_mes1	db	"Timer vector address is changed by other TSRs after PMD staying.",13,10,eof
pmderror_mes2	db	"Music data buffer size must be over 6KBytes.",13,10,eof
pmderror_mes3	db	"Music+voice+effect data size must under 50KBytes.",13,10,eof
pmderror_mes4	db	"Failed to remove from memory.",13,10,eof
pmderror_mes5	db	"PMD is not staying now.",13,10,eof
pmderror_mes6	db	"Appointed options that cannot be changed.",13,10,eof
mes_exit	db	"Stayed.",13,10
		db	"PMD functions is now usable through INT 60H.",13,10
		db	eof

mes_key		db	"You can stop the music by pressing the ESC key, but for FF music, use ",GRPH," key.",13,10,eof

mes_usage	db	"Usage: PMD"
if	ibm
		db	"IBM"
else
		db	"L"
endif
		db	" [/option[number]][/option[number]]..",13,10,13,10
		db	"Option: /Mn  Music  data buffer size (KB) Def.=16",13,10
		db	"        /Vn  Voice  data buffer size (KB) Def.= 4",13,10
		db	"        /En  Effect data buffer size (KB) Def.= 4",13,10
		db	"      * /DFn FM music total volume (0-255, Def.= 0)",13,10
		db	"      * /K(-)don't use ESC/",GRPH," key function (or use)",13,10
		db	"      * /KEn Set special control key using with ESC  Def.="
if	ibm
		db	"4",13,10
else
		db	"16",13,10
endif
		db	"      * /KGn Set special control key using with ",grph," Def.="
if	ibm
		db	"4",13,10
else
		db	"16",13,10
endif
if	ibm
		db	"             Special controls: 1=ShiftR 2=ShiftL 4=CTRL 8=Alt (can be mixed)",13,10
else
		db	"             Special controls: 1=SHIFT 2=CAPS 4=ｶﾅ 16=CTRL (can be mixed)",13,10
endif
		db	"      * /F(-) don't stop music after fadeout (or do)",13,10
		db	"      * /I(-) disable interrupt while Timer/INT 60 interrupt (or enable)",13,10
		db	"      * /Wn  Set FM LSI Wait-loop times between REG-DATA (1-255, Def.=auto)",13,10
		db	"      * /Gn  Set speed of the FF music by ",grph," key Def.=14",13,10
		db	"        /R   Remove from memory",13,10
		db	"        /H   This help",13,10
		db	"     (* options can re-establish, - establish between parenthesiss.)",eof

changemes_0	db	"Parameter is changed.",13,10
crlf		db	13,10,eof
changemes_1	db	"  ----- Now Establishments -----",13,10
		db	"* FM Music total volume: ",eof
changemes_6	db	"* ",GRPH,"/ESC key Control : ",eof
changemes_6a	db	"Enable",13,10,eof
changemes_6b	db	"Disable",13,10,eof
changemes_7	db	"* Special CTRL key code uses with ESC:",eof
changemes_8	db	"* Special CTRL key code uses with ",grph,":",eof
changemes_9	db	"* Music After Fadeout: ",eof
changemes_9a	db	"Stop",13,10,eof
changemes_9b	db	"Continue",13,10,eof
changemes_10	db	"* Other interrupts while timer/INT 60 interrupt: ",eof
changemes_10a	db	"Disable",13,10,eof
changemes_10b	db	"Enable",13,10,eof
changemes_12	db	"* FM LSI Wait-loop times between REG-DATA: ",eof
changemes_12a	db	"(about ",eof
changemes_12b	db	"ns)",13,10,eof
changemes_13	db	"* speed of the FF music by ",grph," key: ",eof

;	常駐する時のオプション
resident_option	db	"H"
		dw	usage
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
		db	"F"
		dw	notstop_set
		db	"W"
		dw	waitclk_set
		db	"G"
		dw	fftempo_set
		db	"R"
		dw	pmderr_5
		db	0

;	既に常駐済みの時のオプション
status_option	db	"H"
		dw	usage
		db	"R"
		dw	resident_cut_main
		db	"K"
		dw	keycheck
		db	"D"
		dw	fmvd_set
		db	"I"
		dw	disint_set
		db	"F"
		dw	notstop_set
		db	"W"
		dw	waitclk_set
		db	"G"
		dw	fftempo_set
		db	"M"
		dw	pmderr_6
		db	"V"
		dw	pmderr_6
		db	"E"
		dw	pmderr_6
		db	"Y"
		dw	pmderr_6
		db	0

mmldat_lng	db	?
voicedat_lng	db	?
effecdat_lng	db	?
resident_mes	db	resmes,0
rmes_end	label	byte

pmd	endp

@code	ends
end	pmd

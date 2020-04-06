;==============================================================================
;
;	MML Compiler/Effect Compiler FOR PC-9801/88VA 
;							ver 4.5
;
;==============================================================================
	.186

ver		equ	"4.5dt(IBMPC)"	;version
vers		equ	45h
date		equ	"2020/04/06"	;date

ifndef	hyouka
hyouka		equ	0		;1で評価版(save機能cut)
endif
ifndef	efc
efc		equ	0		;ＦＭ効果音コンパイラかどうか
endif

;==============================================================================
;
;	ＭＭＬコンパイラです．
;	MC filename[.MML](CR)
;	で，コンパイルして，filename.Mというファイルを作成します．
;
;	また、
;	MC filename[.MML] voice_filename[.FF]
;	で，音色データ付きのfilename.Mを作成します．
;	このデータは，音色データを読まなくても，単体で演奏できます．
;	また、音色定義コマンド(行頭@)が使用可能になります．
;
;	下のefcの値を１にすると、ＦＭ効果音コンパイラになります。
;	EFC filename[.EML] voice_filename[.FF](CR)
;	で，コンパイルして，filename.EFCというファイルを作成します．
;
;==============================================================================

olddat		equ	0		;v2.92以前のデータ作成
split		equ	0		;音色データがＳＰＬＩＴ形式かどうか
pmdvector	equ	60h		;VRTC.割り込み
cr		equ	13
lf		equ	10
eof		equ	"$"

;==============================================================================
;	macros
;==============================================================================

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

print_chr	macro	qq
		mov	ah,2
		mov	dl,qq
		int	21h
		endm

print_line	macro
local		pl_loop,pl_exit
		push	ax
		push	dx
pl_loop:	mov	dl,[bx]
		inc	bx
		or	dl,dl
		jz	pl_exit
		mov	ah,2
		push	bx
		int	21h	;１文字表示
		pop	bx
		jmp	pl_loop
pl_exit:	pop	dx
		pop	ax
		endm

pmd		macro	qq
		mov	ah,qq
		int	pmdvector
		endm

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

;==============================================================================
;	main	program
;==============================================================================

code	segment	para	public	'code'
	assume	cs:code,ss:stack

mc	proc

;==============================================================================
; 	compile	start
;==============================================================================

	cld

	mov	bx,ds
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	print_mes	titmes
	mov	ds,bx
	assume	ds:nothing

	mov	ax,ds:[2ch]
	mov	cs:[kankyo_seg],ax

	mov	si,offset 80h
	cmp	byte ptr [si],0
	jz	usage

	inc	si
	call	space_cut

;==============================================================================
; 	コマンドラインから /optionの読みとり
;==============================================================================

	mov	ax,mml_seg
	mov	es,ax
	assume	es:mml_seg
	xor	ah,ah
	mov	[part],ah
	mov	[ff_flg],ah
	mov	[x68_flg],ah
	mov	[dt2_flg],ah
	mov	[save_flg],1
	mov	[memo_flg],1
	mov	[pcm_flg],1
if	hyouka
	mov	[play_flg],1
	mov	[prg_flg],2
else
	mov	[play_flg],ah
	mov	[prg_flg],ah
endif
option_loop:
	lodsb
	cmp	al," "
	jz	option_loop
	jc	option_exit
	cmp	al,"/"
	jz	option_get
	cmp	al,"-"
	jnz	option_exit

option_get:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
ife	hyouka
	cmp	al,"V"
	jz	prgflg_set
	cmp	al,"P"
	jz	playflg_set
	cmp	al,"S"
	jz	saveflg_reset
endif
	cmp	al,"M"
	jz	x68flg_set
	cmp	al,"N"
	jz	x68flg_reset
	cmp	al,"L"
	jz	oplflg_set
	cmp	al,"O"
	jz	memoflg_reset
	cmp	al,"A"
	jz	pcmflg_reset
	xor	dx,dx
	xor	si,si
	jmp	error

ife	hyouka
;==============================================================================
;	/v,/vw	option
;==============================================================================
prgflg_set:
	mov	al,[si]
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"W"
	jnz	v_only
	inc	si
	or	[prg_flg],2
	jmp	option_loop
v_only:
	or	[prg_flg],1
	jmp	option_loop

;==============================================================================
;	/p	 option
;==============================================================================
playflg_set:
	mov	[play_flg],1
	jmp	option_loop

;==============================================================================
;	/s	 option
;==============================================================================
saveflg_reset:
	mov	[save_flg],0
	mov	[play_flg],1
	jmp	option_loop

endif
;==============================================================================
;	/m	 option
;==============================================================================
x68flg_set:
	mov	[x68_flg],1
	mov	[dt2_flg],1
	jmp	option_loop

;==============================================================================
;	/n	 option
;==============================================================================
x68flg_reset:
	mov	[x68_flg],0
	mov	[opl_flg],0
	mov	[dt2_flg],0
	jmp	option_loop

;==============================================================================
;	/l	 option
;==============================================================================
oplflg_set:
	mov	[opl_flg],1
	jmp	option_loop

;==============================================================================
;	/o	 option
;==============================================================================
memoflg_reset:
	mov	[memo_flg],0
	jmp	option_loop

;==============================================================================
;	/a	 option
;==============================================================================
pcmflg_reset:
	mov	[pcm_flg],0
	jmp	option_loop

option_exit:
	dec	si

;==============================================================================
; 	コマンドラインから.mmlのファイル名の取り込み
;==============================================================================

	xor	ah,ah
	mov	di,offset mml_filename
g_mfn_loop:
	lodsb
	call	sjis_check	;in DISKPMD.INC
	jnc	g_mfn_notsjis
	stosb		;S-JIS漢字1byte目なら 無条件に書き込み
	movsb		;S-JIS漢字2byte目を転送
	lodsb
g_mfn_notsjis:
	cmp	al," "
	jz	g_mfn_next
	cmp	al,13
	jz	g_mfn_next
	cmp	al,"\"
	jnz	g_mfn_notyen
	xor	ah,ah
g_mfn_notyen:
	cmp	al,"."
	jnz	g_mfn_store
	mov	ah,1
g_mfn_store:
	stosb
	jmp	g_mfn_loop
g_mfn_next:
	dec	si
	or	ah,ah
	jnz	mfn_ofs_notset

if	efc
	mov	ax,"E."
else
	mov	ax,"M."
endif

	stosw
	mov	ax,"LM"
	stosw
mfn_ofs_notset:
	xor	al,al
	stosb

;==============================================================================
; 	.mmlファイルの読み込み
;==============================================================================
	push	ds
	push	si
	push	di

	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg

	mov	cs:[oh_filename],0		;in DISKPMD.inc
	push	es
	push	ds
	mov	es,cs:[kankyo_seg]
	mov	dx,offset mml_filename
	call	opnhnd
	pop	ds
	pop	es
	mov	dx,3
	mov	si,0
	jc	error
	mov	dx,offset mml_buf
	mov	cx,offset mmlbuf_end+1-mml_buf
	call	redhnd
	push	ax
	pushf
	call	clohnd
	mov	dx,3
	mov	si,0
	jc	error
	popf
	jc	error
	pop	cx	;CX=読み込んだbyte数

	mov	bx,offset mml_buf
	add	bx,cx
eof_chk_loop:
	cmp	byte ptr -1[bx],0
	jnz	eof_check
	dec	bx
	jmp	eof_chk_loop
eof_check:
	cmp	byte ptr -1[bx],01ah
	jz	crlf_set
	mov	byte ptr [bx],01ah	;EOF write
	inc	bx
crlf_set:
	cmp	byte ptr -3[bx],cr
	jnz	non_crlf
	cmp	byte ptr -2[bx],lf
	jz	crlf_ok
non_crlf:
	mov	byte ptr -1[bx],cr	;CRLF write
	mov	byte ptr +0[bx],lf
	mov	byte ptr +1[bx],1ah
	inc	bx
	inc	bx
crlf_ok:
	mov	[mml_endadr],bx

	cmp	bx,offset mmlbuf_end+1
	mov	dx,18
	mov	si,0
	jnc	error

	cmp	cs:[oh_filename],0
	jz	not_trans_filename
;	環境変数を参照して読み込んだ場合はファイル名変更(ERROR時に出力される)
	push	ds
	mov	ax,cs
	mov	ds,ax
	assume	ds:code
	mov	si,offset oh_filename
	mov	di,offset mml_filename
trfn_loop:
	movsb
	cmp	byte ptr -1[si],0
	jnz	trfn_loop
	pop	ds
	assume	ds:mml_seg
not_trans_filename:
	pop	di
	pop	si

;==============================================================================
; 	.mmlを.mに変更して設定
;==============================================================================
ife	hyouka
	push	es
	push	si

	mov	ax,m_seg
	mov	es,ax
	assume	es:m_seg

	mov	si,offset mml_filename
	mov	di,offset m_filename

cv_mml_m_loop:
	movsb
	cmp	byte ptr -1[si],"."
	jnz	cv_mml_m_loop

	mov	es:[file_ext_adr],di
if	efc
	mov	ax,"FE"
	stosw
	mov	ax,"C"
	stosw
else
	mov	ax,"M"
	stosw
endif
	pop	si
	pop	es
	assume	es:mml_seg
endif
	pop	ds
	assume	ds:nothing

;==============================================================================
;	音色データ領域を転送してくる（PMD常駐時）又はクリア
;==============================================================================
	push	es
	;
	; ＰＭＤの常駐しているセグメントを得る
	;
	xor	ax,ax
	mov	es,ax
	les	bx,es:[pmdvector*4]
	;
	; ＰＭＤが常駐しているかを観る
	;
	cmp	byte ptr es:2[bx],"P"
	jnz	not_pmd
	cmp	byte ptr es:3[bx],"M"
	jnz	not_pmd
	cmp	byte ptr es:4[bx],"D"
	jnz	not_pmd

	pop	es
	push	ds
	push	si

	mov	[pmd_flg],1

	mov	ah,7
	int	60h	; get_tonedata_address

	push	es
	mov	ax,voice_seg
	mov	es,ax
	assume	es:voice_seg
	mov	si,dx
	mov	di,offset voice_buf
	mov	cx,32*256/2
rep	movsw

	pop	es
	assume	es:mml_seg
	pop	si
	pop	ds
	jmp	get_ff

not_pmd:
	mov	[pmd_flg],0
	mov	ax,voice_seg
	mov	es,ax
	assume	es:voice_seg
	mov	di,offset voice_buf
	xor	ax,ax
	mov	cx,32*256/2
rep	stosw
	pop	es
	assume	es:mml_seg

;==============================================================================
; 	コマンドラインから.ffのファイル名を取り込む
;==============================================================================
get_ff:
	call	space_cut
	cmp	byte ptr [si],13
	jz	clear_voicetable

	mov	[ff_flg],1

	mov	ax,voice_seg
	mov	es,ax
	assume	es:voice_seg

	xor	ah,ah
	mov	di,offset v_filename

g_vfn_loop:
	lodsb
	call	sjis_check	;in DISKPMD.INC
	jnc	g_vfn_notsjis
	stosb		;S-JIS漢字1byte目なら 無条件に書き込み
	movsb		;S-JIS漢字2byte目を転送
	lodsb
g_vfn_notsjis:
	cmp	al," "
	jz	g_vfn_next
	cmp	al,13
	jz	g_vfn_next
	cmp	al,"\"
	jnz	g_vfn_notyen
	xor	ah,ah
g_vfn_notyen:
	cmp	al,"."
	jnz	g_vfn_store
	mov	ah,1
g_vfn_store:
	stosb
	jmp	g_vfn_loop
g_vfn_next:
	or	ah,ah
	jnz	vfn_ofs_notset
	mov	ax,"F."
	stosw
	mov	al,"F"
	stosb
	push	ds
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	cmp	[opl_flg],1
	pop	ds
	assume	ds:nothing
	jnz	vfn_ofs_notset
	mov	al,"L"
	stosb
vfn_ofs_notset:
	xor	al,al
	stosb

;==============================================================================
; 	.ffファイルの読み込み
;==============================================================================
	mov	ax,voice_seg
	mov	ds,ax
	assume	ds:voice_seg
	push	es
	push	ds
	mov	es,cs:[kankyo_seg]
	mov	dx,offset v_filename
	call	opnhnd
	pop	ds
	pop	es
	jc	not_set_voicefile
	mov	dx,offset voice_buf
	mov	cx,8*1024	;最大 8KB
	call	redhnd
	pushf
	call	clohnd
	jc	not_set_voicefile
	popf
	jc	not_set_voicefile
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
ife	hyouka
	or	[prg_flg],1
endif
	jmp	clear_voicetable

not_set_voicefile:
	mov	ax,mml_seg
	mov	ds,ax
	print_mes	warning_mes
	print_mes	ff_readerr_mes

;==============================================================================
; 	音色テーブルの初期化
;==============================================================================
clear_voicetable:
	mov	ax,mml_seg
	mov	ds,ax
	mov	es,ax
	assume	ds:mml_seg,es:mml_seg

	mov	di,offset prg_num
	mov	cx,128
	xor	ax,ax
rep	stosw

;==============================================================================
; 	compile main
;==============================================================================
if	efc
	test	[prg_flg],1
	mov	dx,28
	mov	si,0
	jz	error
endif

;==============================================================================
;	変数バッファ/文字列offsetバッファ初期化
;==============================================================================

	mov	di,offset hsbuf
	mov	cx,64
	xor	ax,ax
rep	stosw
	mov	di,offset hsbuf2
	mov	cx,256
	xor	ax,ax
rep	stosw
	mov	di,offset ppsfile_adr
	mov	cx,128+5
rep	stosw

;==============================================================================
;	Pass1
;==============================================================================
;==============================================================================
;	Workの初期化(pass1)
;==============================================================================
	mov	ax,m_seg
	mov	es,ax
	assume	es:m_seg

	mov	si,offset mml_buf
	xor	ax,ax
	mov	[part],al
	mov	[pass],al
	mov	es:[mbuf_end],07fh	;check code

;==============================================================================
;	Ｍain Ｌoop(pass1)
;==============================================================================

p1cloop:
	mov	[linehead],si
p1c_next:
	lodsb

	cmp	al,1ah
	jz	p1_end
	cmp	al," "+1
	jc	p1c_fin
	cmp	al,";"
	jz	p1c_fin

	cmp	al,"!"
	jz	hsset

	cmp	al,"#"
	jz	macro_set

	cmp	al,"@"
	jz	new_neiro_set

	jmp	p1c_next

p1c_fin:
	call	line_skip
	jmp	p1cloop

p1_end:
;==============================================================================
;	ループカウント初期化
;==============================================================================

	mov	[lopcnt],0

;==============================================================================
;	Pass2 Compile Start
;==============================================================================

ife	efc+olddat
	mov	al,[opl_flg]
	add	al,al
	or	al,[x68_flg]
	mov	[m_start],al	; 音源flag set
endif

	mov	di,2*[max_part+1]
	add	di,offset m_buf
	test	[prg_flg],1
	jz	cs_00
	inc	di
	inc	di
cs_00:
	xor	al,al
	mov	[hsflag],al
	mov	[prsok],al
	inc	al
	mov	[part],al

	mov	[pass],1

;==============================================================================
;	音源の選択
;==============================================================================
cmloop:
ife	efc

	mov	al,[opl_flg]
	or	al,[x68_flg]
	jz	cm_notx68

;==============================================================================
;	ＯＰＭ/ＯＰＬの場合
;==============================================================================
	cmp	[part],10
	jz	opm_pcm_set
	mov	[ongen],fm
	jmp	part_stadr_set
opm_pcm_set:
	mov	[ongen],pcm
	jmp	part_stadr_set

;==============================================================================
;	ＯＰＮの場合
;==============================================================================
cm_notx68:
	mov	al,[part]
	xor	ah,ah
ons0:	cmp	al,4
	jc	onsext
	sub	al,3
	inc	ah
	jmp	ons0
onsext:	mov	[ongen],ah

endif
;==============================================================================
;	パートのスタートアドレスのセット
;==============================================================================
part_stadr_set:
	mov	bl,[part]
	xor	bh,bh
	dec	bx
	add	bx,bx
	add	bx,offset m_buf

	mov	dx,di
	sub	dx,offset m_buf
	mov	es:[bx],dx

;==============================================================================
;	Workの初期化
;==============================================================================
cmloop2:
	mov	si,offset mml_buf
	xor	ax,ax
	mov	[maxprg],al
	mov	[volss],al
	mov	[skip_flag],al
	mov	[tie_flag],al
	mov	[porta_flag],al
	mov	[ss_speed],al
	mov	[ss_depth],al
	mov	[ss_length],al
	mov	[ge_delay],al
	mov	[ge_depth],al
	mov	[ge_depth2],al
	mov	[pitch],ax
	mov	[detune],ax
	mov	[alldet],8000h

	mov	al,3
	mov	[octarb],al
	inc	al	;AL=4
	mov	[deflng],al

ife	efc
	cmp	[part],1
	jnz	not_partA
	cmp	[fm3_partchr1],0
	jz	not_ext_fm3
	mov	al,0c6h	;FM3 拡張パートの指定
	stosb
	mov	[fm3_ofsadr],di
	xor	ax,ax
	stosw
	stosw
	stosw
not_ext_fm3:
	cmp	[zenlen],96
	jz	not_zenlen
	mov	ah,[zenlen]
	mov	al,0dfh
	stosw		;#Zenlenが指定されている場合は Zコマンド発行(partA)
not_zenlen:
	cmp	[tempo],0
	jz	not_tempo
	mov	ah,[tempo]
	mov	al,0fch
	stosw		;#Tempoが指定されている場合は tコマンド発行(partA)
not_tempo:
not_partA:
	mov	al,[opl_flg]
	or	al,[x68_flg]
	jnz	non_ext_env	;OPM/OPL=DX/EXを却下
	cmp	[ext_detune],0
	jz	non_ext_detune
	cmp	[ongen],psg
	jnz	non_ext_detune	;PSGのみ
	mov	ax,01cch
	stosw		;Extend Detune Set (Partの頭)
non_ext_detune:
	cmp	[ext_env],0
	jz	non_ext_env
	cmp	[ongen],psg
	jc	non_ext_env	;FMは却下
	cmp	[part],rhythm
	jnc	non_ext_env	;Rhythmは却下
	mov	ax,01c9h
	stosw		;Extend Envelope Set (Partの頭)
non_ext_env:
	cmp	[ext_lfo],0
	jz	non_ext_lfo
	cmp	[part],rhythm
	jnc	non_ext_lfo	;Rhythmは却下
	mov	ax,01cah
	stosw		;Extend LFO Set (Partの頭)
non_ext_lfo:
endif
;==============================================================================
;	Ｍain Ｌoop
;==============================================================================

cloop:
c_next:
	lodsb
	cmp	al,1ah
	jz	part_end
	cmp	al," "+1
	jc	c_fin
	cmp	al,";"
	jz	c_fin
	cmp	al,"!"
	jz	hsset

	cmp	al,22h ;"
	jnz	c_nskp_01
	xor	[skip_flag],1
	jmp	c_next
c_nskp_01:
	cmp	al,27h ;'
	jnz	c_nskp_02
	mov	[skip_flag],0
	jmp	c_next
c_nskp_02:
if	efc
	dec	si
	call	lngset2
	jc	c_fin
	inc	al
	cmp	al,[part]
else
	mov	ah,[part]
	add	ah,"A"-1
	cmp	al,ah
endif
	jz	one_line_compile
	jmp	c_next

c_fin:
	call	line_skip
	jmp	cloop

part_end:
;==============================================================================
;	Error Checks
;==============================================================================
	xor	si,si		;エラー位置は不定

	cmp	[lopcnt],0
	mov	dx,"]"*256+8
	jnz	error

	cmp	[porta_flag],0
	mov	dx,"{"*256+9
	jnz	error

	cmp	[allloop_flag],0
	jz	non_allloop_error
	cmp	[length_check1],0
	mov	dx,"L"*256+10
	jz	error
non_allloop_error:

;==============================================================================
;	Part Endmark をセット
;==============================================================================
	mov	byte ptr es:[di],80h
	inc	di

;==============================================================================
;	PART INC. & LOOP
;==============================================================================
	inc	[part]
if	efc
	cmp	[part],max_part+2
else
	cmp	[part],max_part+1
endif
	jc	cmloop

ife	efc
	jnz	fm3_check
	mov	al,[maxprg]
	mov	[kpart_maxprg],al	;K partのmaxprgを保存

;==============================================================================
;	FM3 拡張パートがあればそれをcompile
;==============================================================================
fm3_check:
	cmp	[fm3_ofsadr],0
	jz	rt		;無し
	mov	al,[fm3_partchr1]
	mov	[fm3_partchr1],0
	or	al,al
	jnz	fm3c_main
	mov	al,[fm3_partchr2]
	mov	[fm3_partchr2],0
	or	al,al
	jnz	fm3c_main
	mov	al,[fm3_partchr3]
	mov	[fm3_partchr3],0
	or	al,al
	jz	rt
fm3c_main:
	mov	bx,[fm3_ofsadr]
	mov	dx,di
	sub	dx,offset m_buf
	mov	es:[bx],dx
	inc	bx
	inc	bx
	mov	[fm3_ofsadr],bx
	sub	al,"A"-1
	mov	[part],al
	mov	[ongen],fm
	jmp	cmloop2

;==============================================================================
;	R part Compile (efc.exeはしない)
;==============================================================================
rt:
;==============================================================================
;	Ｒパートのスタートアドレスをセット
;==============================================================================

	mov	bx,offset m_buf
	add	bx,2*max_part
	mov	[part],rhythm
	mov	[ongen],pcm

	mov	dx,di
	sub	dx,offset m_buf
	mov	es:[bx],dx

;==============================================================================
;	リズムデータスタートアドレスを計算してｂｘへ
;==============================================================================
	mov	bl,[kpart_maxprg]
	xor	bh,bh
	add	bx,bx
	add	bx,di
;==============================================================================
;	Ｒパートコンパイル開始
;==============================================================================
	mov	si,offset mml_buf
	xor	ax,ax
	mov	[skip_flag],al

;==============================================================================
;	データスタートアドレスをセット
;==============================================================================
rtloop:	
	cmp	[kpart_maxprg],0
	jz	rtlp2

	mov	dx,bx
	sub	dx,offset m_buf
	mov	es:[di],dx
	inc	di
	inc	di
rtlp2:
	cmp	byte ptr [si],1ah
	jz	rend

rtlp3:
	lodsb

	cmp	al,"!"+1
	jc	rskip

	cmp	al,";"
	jz	rskip

	cmp	[kpart_maxprg],0
	jz	rskip

	cmp	al,"R"
	jnz	rtlp3
	
	xchg	bx,di

	push	bx
	mov	[hsflag],1
	call	one_line_compile
	pop	bx

	mov	byte ptr es:[di],0ffh
	inc	di

	xchg	bx,di
	dec	[kpart_maxprg]

	jmp	rtloop

rskip:	call	line_skip
	jmp	rtlp2

rend:	mov	di,bx
rend2:
	cmp	[kpart_maxprg],0
	jz	rem_set
	mov	dx,29
	xor	si,si
	jmp	error

;==============================================================================
;	Remark文箇所の設定
;==============================================================================
rem_set:
	mov	[part],0

	mov	bp,di
	inc	di
	inc	di
	mov	al,vers
	stosb
	mov	al,-2
	stosb		; Remarks Check Code (0feh)
endif
;==============================================================================
;	Ｖ２．６以降用／音色データのセット
;==============================================================================
ife	hyouka
vdat_set:
	test	[prg_flg],1
	jz	memo_write

	mov	si,offset m_buf
	add	si,2*[max_part+1]

	mov	dx,di
	sub	dx,offset m_buf
	mov	es:[si],dx

	mov	bx,offset prg_num
	mov	si,offset voice_buf
if	split
	inc	si
endif
	xor	al,al
	mov	cx,256

	cmp	[opl_flg],1
	jnz	nd_s_loop

;==============================================================================
;	OPL用
;==============================================================================
nd_s_opl_loop:
	cmp	byte ptr [bx],0
	jz	nd_s_opl_00

	mov	es:[di],al
	inc	di

	push	ds
	mov	dx,voice_seg
	mov	ds,dx
	assume	ds:voice_seg
	push	cx
	mov	cx,9	;１音色９ｂｙｔｅｓ
rep	movsb
	pop	cx
	pop	ds
	assume	ds:mml_seg

	add	si,16-9
	jmp	nd_s_opl_01

nd_s_opl_00:
	add	si,16
nd_s_opl_01:
	inc	al
	inc	bx
	loop	nd_s_opl_loop
	jmp	nd_s_exit

;==============================================================================
;	OPN用
;==============================================================================
nd_s_loop:
	cmp	byte ptr [bx],0
	jz	nd_s_00

	mov	es:[di],al
	inc	di

	push	ds
	mov	dx,voice_seg
	mov	ds,dx
	assume	ds:voice_seg
	push	cx
	mov	cx,25	;１音色２５ｂｙｔｅｓ
rep	movsb
	pop	cx
	pop	ds
	assume	ds:mml_seg

	add	si,32-25
	jmp	nd_s_01
nd_s_00:
	add	si,32
nd_s_01:
	inc	al
	inc	bx
	loop	nd_s_loop

nd_s_exit:
	mov	ax,0ff00h
	stosw			;音色終了マーク
endif
;==============================================================================
;	その他メモ系文字列の書込み
;==============================================================================
memo_write:
ife	efc
	mov	bx,offset ppsfile_adr

	mov	cx,2	; #PPSFile / #PCMFile
memow_loop0:
	push	cx
	mov	si,[bx]	; si <文字列先頭番地
	mov	ax,di
	sub	ax,offset m_buf
	mov	[bx],ax	;[bx]に替わりに転送先のアドレス(ofs)を入れておく
	or	si,si
	jnz	memow_trans0
	xor	al,al
	stosb
	jmp	memow_exit0
memow_trans0:
	call	set_strings2	;小文字＞大文字変換付き
memow_exit0:
	inc	bx
	inc	bx
	pop	cx
	loop	memow_loop0

	mov	cx,3	;３つまでは無条件に書込み(title/composer/arranger)
memow_loop1:
	push	cx
	mov	si,[bx]	; si <文字列先頭番地
	mov	ax,di
	sub	ax,offset m_buf
	mov	[bx],ax	;[bx]に替わりに転送先のアドレス(ofs)を入れておく
	or	si,si
	jnz	memow_trans
	xor	al,al
	stosb
	jmp	memow_exit
memow_trans:
	call	set_strings
memow_exit:
	inc	bx
	inc	bx
	pop	cx
	loop	memow_loop1

memow_loop2:
	mov	si,[bx]	; si <文字列先頭番地
	or	si,si
	jz	memow_allexit
	mov	ax,di
	sub	ax,offset m_buf
	mov	[bx],ax	;[bx]に替わりに転送先のアドレス(ofs)を入れておく
	call	set_strings
	inc	bx
	inc	bx
	jmp	memow_loop2
memow_allexit:

	mov	ax,di
	sub	ax,offset m_buf
	mov	es:[bp],ax
	mov	si,offset ppsfile_adr
memoofsset_loop:
	lodsw
	stosw
	or	ax,ax
	jnz	memoofsset_loop

endif
;==============================================================================
;	容量オーバーcheck
;==============================================================================
	cmp	es:[mbuf_end],07fh	;check code
	mov	dx,19
	mov	si,0
	jnz	error	;容量オーバー

ife	hyouka
;==============================================================================
;	.ffの書き込み
;==============================================================================
write_ff:
	test	[prg_flg],2
	jz	write_disk
	cmp	[ff_flg],0
	jz	not_ff

	mov	cx,8*1024
	cmp	[opl_flg],1
	jnz	wf_go
	mov	cx,4*1024
wf_go:
	push	ds
	mov	ax,voice_seg
	mov	ds,ax
	assume	ds:voice_seg
	mov	ax,offset v_filename
	mov	dx,offset voice_buf
	call	DISKWRITE
	mov	dx,5
	mov	si,0
	jc	error
	pop	ds
	assume	ds:mml_seg
	jmp	write_disk

not_ff:
	print_mes	warning_mes
	print_mes	not_ff_mes
;==============================================================================
;	Disk Write
;==============================================================================
write_disk:
	cmp	[save_flg],0
	jz	compile_fin
	push	ds
	mov	ax,m_seg
	mov	ds,ax
	mov	es,ax
	assume	ds:m_seg,es:m_seg
	mov	ax,offset m_filename
	mov	dx,offset m_start
	mov	cx,di
	sub	cx,dx
	call	DISKWRITE
	mov	dx,4
	mov	si,0
	jc	error
	pop	ds
	assume	ds:mml_seg
else
;
;	評価版／音色データエリアにコンパイル後の音色データを転送
;
	cmp	[pmd_flg],0
	jz	compile_fin
	push	es
	push	ds
	push	di
	mov	ah,7
	int	60h	;get_tonedata_address to ds:dx
	mov	ax,ds
	mov	es,ax
	mov	ax,voice_seg
	mov	ds,ax
	mov	si,offset voice_buf
	mov	di,dx
	mov	cx,16*256
rep	movsw
	pop	di
	pop	ds
	pop	es

endif

;==============================================================================
;	Compile 終了
;==============================================================================
compile_fin:
	print_mes	finmes
ife	efc
	mov	cx,di
	sub	cx,offset m_start

	cmp	[play_flg],0
	jz	not_play

	cmp	[pmd_flg],0
	jz	not_play_nonpmd

	mov	ah,1
	int	60h	; music_stop
	mov	ah,6
	int	60h	; get_music_address to ds:dx

	mov	ax,ds
	mov	es,ax
	mov	ax,m_seg
	mov	ds,ax
	mov	si,offset m_start
	mov	di,dx
rep	movsb

	mov	ax,mml_seg
	mov	ds,ax
	cmp	[memo_flg],0
	jz	non_pcmfile_put
	call	pcmfile_put
non_pcmfile_put:

	mov	ax,mml_seg
	mov	ds,ax
	cmp	[pcm_flg],0
	jz	non_pcm_read
	call	pcm_read
non_pcm_read:

	xor	ah,ah
	int	60h	; music_start

	mov	ax,mml_seg
	mov	ds,ax
	cmp	[memo_flg],0
	jz	non_memo_put
	call	memo_put
non_memo_put:
	jmp	not_play

not_play_nonpmd:
	print_mes	warning_mes
	print_mes	not_pmd_mes

not_play:
endif
	msdos_exit

line_skip:
	inc	si
	cmp	byte ptr -1[si],0ah
	jnz	line_skip
	ret

ife	efc
;==============================================================================
;	PCMファイルの読み込み
;==============================================================================
pcm_read:
	mov	ax,m_seg
	mov	ds,ax
	mov	ax,mml_seg
	mov	es,ax
	assume	ds:m_seg,es:mml_seg

	mov	bx,es:[ppsfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr [bx],0
	jz	non_ppsread

	mov	ax,bx			;DS:AX = PPS filename

	call	pps_load		;in PCMLOAD.INC
non_ppsread:

	mov	bx,es:[pcmfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr [bx],0
	jz	non_pcmread

	mov	ax,mml_seg
	mov	es,ax
	mov	di,offset mml_buf	;ES:DI = PCM_data(MMLを潰す)
	mov	ax,bx			;DS:AX = PCM filename

	call	pcm_all_load		;in PCMLOAD.INC
non_pcmread:

	mov	ax,mml_seg
	mov	ds,ax
	mov	es,ax
	ret

	include	pcmload.inc

;==============================================================================
;	#PPSFile / #PCMFile文字列の表示
;==============================================================================
pcmfile_put:
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	mov	ax,m_seg
	mov	es,ax
	assume	es:m_seg

	mov	bx,[ppsfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_ppsfile
	push	bx
	print_mes	mes_ppsfile
	pop	bx
	call	put_strings
non_ppsfile:

	mov	bx,[pcmfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_pcmfile
	push	bx
	print_mes	mes_pcmfile
	pop	bx
	call	put_strings
non_pcmfile:
	ret

;==============================================================================
;	メモ文字列の表示
;==============================================================================
memo_put:
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	mov	ax,m_seg
	mov	es,ax
	assume	es:m_seg

	mov	bx,[title_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_title
	push	bx
	print_mes	mes_title
	pop	bx
	call	put_strings
non_title:

	mov	bx,[composer_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_composer
	push	bx
	print_mes	mes_composer
	pop	bx
	call	put_strings
non_composer:

	mov	bx,[arranger_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_arranger
	push	bx
	print_mes	mes_arranger
	pop	bx
	call	put_strings
non_arranger:

	mov	si,offset memo_adr
memoput_loop:
	mov	bx,[si]
	or	bx,bx
	jz	non_memo
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],"/"
	jz	non_memo
	push	si
	push	bx
	print_mes	mes_memo
	pop	bx
	call	put_strings
	pop	si
	inc	si
	inc	si
	jmp	memoput_loop
non_memo:
	ret

;==============================================================================
;	メモ文字列の１行表示
;		input	ES:BX	mml_adr
;==============================================================================
put_strings:
	mov	dl,es:[bx]
	or	dl,dl
	jz	ps_exit
	mov	ah,2
	int	21h
	inc	bx
	jmp	put_strings
ps_exit:
	print_mes	mes_crlf
	ret

endif
;==============================================================================
;	マクロコマンド
;==============================================================================
macro_set:
	mov	bx,si		;bxに現在のsiを保存
	lodsb
	and	al,11011111b	;小文字＞大文字変換(1文字目)
	mov	ah,[si]
	and	ah,11011111b	;小文字＞大文字変換(2文字目)
	push	ax
	call	move_next_param
	mov	dh,"#"
	mov	dl,6
	jc	error
	pop	ax
ife	efc
	cmp	al,"P"
	jz	pcmfile_set
	cmp	al,"T"
	jz	title_set
	cmp	al,"C"
	jz	composer_set
	cmp	al,"A"
	jz	arranger_set
	cmp	al,"M"
	jz	memo_set
	cmp	al,"Z"
	jz	zenlen_set
	cmp	al,"L"
	jz	LFOExtend_set
	cmp	al,"E"
	jz	EnvExtend_set
	cmp	al,"F"
	jz	FM3Extend_set
endif
	cmp	al,"D"
	jz	dt2flag_set
	cmp	al,"O"
	jz	octrev_set
	cmp	al,"B"
	jz	bend_set
	cmp	al,"I"
	jz	include_set

macro_normal_ret:
	mov	bx,[linehead]
	mov	byte ptr [bx],";"	;"#"を";"に変換
	jmp	p1c_fin

ps_error:
	mov	dh,"#"
	mov	dl,7
	jmp	error

ife	efc
;==============================================================================
;	#PCMFile
;==============================================================================
pcmfile_set:
	cmp	ah,"P"
	jz	ppsfile_set
	cmp	ah,"C"
	jnz	ps_error
	mov	al,2[bx]
	and	al,11011111b	;小文字＞大文字変換(3文字目)
	cmp	al,"M"
	jnz	ps_error
	mov	al,3[bx]
	and	al,11011111b	;小文字＞大文字変換(4文字目)
	cmp	al,"V"
	jz	pcmvolume_set
	cmp	al,"F"
	jnz	ps_error
ppcfile_set:
	mov	[pcmfile_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#PCMVolume	Extend/Normal
;==============================================================================
pcmvolume_set:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"N"
	jz	pcmvol_normal
	cmp	al,"E"
	jnz	ps_error
	mov	[pcm_vol_ext],1
	jmp	macro_normal_ret
pcmvol_normal:
	mov	[pcm_vol_ext],0
	jmp	macro_normal_ret

;==============================================================================
;	#PPSFile
;==============================================================================
ppsfile_set:
	mov	al,2[bx]
	and	al,11011111b	;小文字＞大文字変換(3文字目)
	cmp	al,"C"
	jz	ppcfile_set
	cmp	al,"S"
	jnz	ps_error
	mov	[ppsfile_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Title
;==============================================================================
title_set:
	cmp	ah,"E"
	jz	tempo_set
	mov	[title_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Composer
;==============================================================================
composer_set:
	mov	[composer_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Arranger
;==============================================================================
arranger_set:
	mov	[arranger_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Memo
;==============================================================================
memo_set:
	mov	bx,offset memo_adr-2
memset_loop:
	add	bx,2
	cmp	word ptr [bx],0
	jnz	memset_loop
	mov	[bx],si
	jmp	macro_normal_ret

;==============================================================================
;	#Detune	Normal/Extend
;==============================================================================
detune_select:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"N"
	jz	detune_normal
	cmp	al,"E"
	jnz	ps_error
	mov	[ext_detune],1
	jmp	macro_normal_ret
detune_normal:
	mov	[ext_detune],0
	jmp	macro_normal_ret

;==============================================================================
;	#LFOSpeed	Normal/Extend
;==============================================================================
LFOExtend_set:
	cmp	ah,"O"
	jz	loopdef_set
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"N"
	jz	lfo_normal
	cmp	al,"E"
	jnz	ps_error
	mov	[ext_lfo],1
	jmp	macro_normal_ret
lfo_normal:
	mov	[ext_lfo],0
	jmp	macro_normal_ret

;==============================================================================
;	#LoopDefault	n
;==============================================================================
loopdef_set:
	call	lngset2
	jc	ps_error
	mov	[loop_def],al
	jmp	macro_normal_ret

;==============================================================================
;	#EnvSpeed	Normal/Extend
;==============================================================================
EnvExtend_set:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"N"
	jz	env_normal
	cmp	al,"E"
	jnz	ps_error
	mov	[ext_env],1
	jmp	macro_normal_ret
env_normal:
	mov	[ext_env],0
	jmp	macro_normal_ret

;==============================================================================
;	#Tempo
;==============================================================================
tempo_set:
	call	lngset2
	mov	dx,"#"*256+6
	jc	error
	call	timerb_get
	mov	[tempo],dl
	jmp	macro_normal_ret

;==============================================================================
;	#Zenlength
;==============================================================================
zenlen_set:
	call	lngset2
	mov	dx,"#"*256+6
	jc	error
	mov	[zenlen],al
	jmp	macro_normal_ret

;==============================================================================
;	#FM3Extend
;==============================================================================
FM3Extend_set:
	cmp	ah,"I"
	jz	file_name_set
	cmp	byte ptr [si]," "
	mov	dx,"#"+6
	jc	error

	lodsb
	call	partcheck
	jc	ps_error
	mov	[fm3_partchr1],al
	lodsb
	call	partcheck
	jc	fm3e_exit
	mov	[fm3_partchr2],al
	lodsb
	call	partcheck
	jc	fm3e_exit
	mov	[fm3_partchr3],al
	jmp	macro_normal_ret
fm3e_exit:
	dec	si
	jmp	macro_normal_ret

;==============================================================================
;	#Filename
;==============================================================================
file_name_set:
ife	hyouka
	push	di
	mov	di,es:[file_ext_adr]
	lodsb
	cmp	al,"."
	jz	file_name_set_main
	dec	si
	mov	di,offset m_filename
file_name_set_main:
	movsb
	cmp	byte ptr [si],";"
	jz	file_name_set_exit
	cmp	byte ptr [si],"!"
	jnc	file_name_set_main
file_name_set_exit:
	xor	al,al
	stosb
	pop	di
endif
	jmp	macro_normal_ret
endif
;==============================================================================
;	#DT2flag on/off
;==============================================================================
dt2flag_set:
ife	efc
	cmp	ah,"E"
	jz	detune_select
endif
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"O"
	jnz	ps_error
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"N"
	jz	dt2flag_norm
	cmp	al,"F"
	jnz	ps_error
	mov	[dt2_flg],0
	jmp	macro_normal_ret
dt2flag_norm:
	mov	[dt2_flg],1
	jmp	macro_normal_ret

;==============================================================================
;	#Octarb	rev/norm
;==============================================================================
octrev_set:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"R"
	jz	oct_reverse
	cmp	al,"N"
	jnz	ps_error
	mov	cs:[ou00],">"
	mov	cs:[od00],"<"
	jmp	macro_normal_ret
oct_reverse:
	mov	cs:[ou00],"<"
	mov	cs:[od00],">"
	jmp	macro_normal_ret

;==============================================================================
;	#Bendrange
;==============================================================================
bend_set:
	call	lngset2
	mov	dx,"#"*256+6
	jc	error
	mov	[bend],al
	jmp	macro_normal_ret

;==============================================================================
;	#Include
;==============================================================================
include_set:
;------------------------------------------------------------------------------
;	ファイル名の取り込み
;------------------------------------------------------------------------------
	push	es
	push	di
	mov	ax,ds
	mov	es,ax
	assume	es:mml_seg
	mov	di,offset mml_filename2
	call	set_strings
	push	si		;SI= CR位置 を保存
	inc	si
	inc	si		;SI= 次の行の先頭位置(に読み込む予定)

;------------------------------------------------------------------------------
;	現在のMML残りをMMLバッファ末端に移動
;	I---------------I---------------I---------------I
;	mml_buf		SI		[mml_endadr]	mmlbuf_end
;			-------CX-------SI		DI	にしてstd/movsw
;------------------------------------------------------------------------------
	mov	cx,[mml_endadr]
	sub	cx,si			;CX= 転送するbyte数
	mov	si,[mml_endadr]
	dec	si			;SI= 現在のMMLの終端
	mov	di,offset mmlbuf_end	;DI= MML_buf最終端
	std
rep	movsb
	cld
	mov	bp,di
	inc	bp			;BP= 転送したMML開始位置
	pop	si

;------------------------------------------------------------------------------
;	Include開始check codeをMMLに書く
;------------------------------------------------------------------------------
	push	si
	inc	si
	inc	si
	mov	di,si

	mov	al,1
	stosb		;IncludeFile開始 CheckCode

;------------------------------------------------------------------------------
;	FileをOpenしてFile名をMMLに書く
;------------------------------------------------------------------------------
	mov	cs:[oh_filename],0
	mov	dx,offset mml_filename2	;DS:DX=Filename
	push	es
	push	ds
	push	si
	push	di
	mov	es,cs:[kankyo_seg]
	call	opnhnd
	pop	di
	pop	si
	pop	ds
	pop	es
	mov	dx,"#"*256+3
	jc	inc_error
	mov	si,offset mml_filename2
	cmp	cs:[oh_filename],0
	jz	inc_fns_loop
	mov	ax,cs
	mov	ds,ax
	mov	si,offset oh_filename	;環境を参照した場合
inc_fns_loop:
	movsb
	cmp	byte ptr -1[si],0
	jnz	inc_fns_loop

	mov	al,0ah
	stosb		;LFの書込み = Line_skipに引っ掛かるようにする

;------------------------------------------------------------------------------
;	Fileの読み込み
;------------------------------------------------------------------------------
	mov	ax,mml_seg
	mov	ds,ax
	mov	dx,di	;DS:DX	= 読み込む位置
	mov	cx,bp
	sub	cx,dx	;CX     = Fileの最大長
	inc	cx	;Over Check用に 1byte余計に読みだし
	push	dx
	push	cx
	call	redhnd	;読み込み
	push	ax
	pushf
	call	clohnd	;Close
	mov	dx,"#"*256+3
	jc	inc_error4
	popf
	jc	inc_error3
	pop	ax		;AX = 読み込んだ長さ
	pop	cx		;CX = 読み込める長さ
	pop	di
	add	di,ax		;DI = 読み込んだFileのEOF位置 +1
	cmp	cx,ax			;読み込める長さ+1を読み込めたら
	mov	dx,"#"*256+18		;サイズが大き過ぎる
	jz	inc_error

;------------------------------------------------------------------------------
;	File終端のEOFを削ってCR/LFが無ければ書き足す
;------------------------------------------------------------------------------
inc_eof_chk_loop:
	cmp	byte ptr -1[bx],0
	jnz	inc_eof_check
	dec	bx
	jmp	inc_eof_chk_loop
inc_eof_check:
	cmp	byte ptr -1[di],01ah
	jnz	inc_crlf_set
	dec	di	;EOFは無視
inc_crlf_set:
	cmp	byte ptr -2[di],cr
	jnz	inc_non_crlf
	cmp	byte ptr -1[di],lf
	jz	inc_crlf_ok
inc_non_crlf:
	mov	ax,lf*256+cr
	stosw		;CRLF Write
inc_crlf_ok:

;------------------------------------------------------------------------------
;	Include->MainのCheckCodeの書込み
;------------------------------------------------------------------------------
	mov	ax,0ah*256+2
	stosw		;IncludeFile終了 CheckCode

	cmp	bp,di		;BP<DIなら
	mov	dx,"#"*256+18	;サイズが大き過ぎる
	jc	inc_error

;------------------------------------------------------------------------------
;	転送した残りMMLを元に戻す
;------------------------------------------------------------------------------
	mov	si,bp	;SI = 転送したMMLの先頭
	mov	cx,offset mmlbuf_end+1
	sub	cx,bp	;CX = 転送したMMLのSize
rep	movsb

	mov	[mml_endadr],di	;MML終端位置の書き直し

	pop	si	;DS:SI=CR位置 に戻す
	pop	di
	pop	es
	assume	es:m_seg

	jmp	macro_normal_ret

inc_error4:
	popf
inc_error3:
	pop	si
	pop	si
inc_error:
	pop	si	;SI=CR位置 に戻してからError
	jmp	error

;==============================================================================
;	alの文字が使用中のパートかどうかcheck
;==============================================================================
partcheck:
	cmp	al,"L"
	jc	pc_stc_ret
	cmp	al,"R"
	jz	pc_stc_ret
	cmp	al,7fh
	jnc	pc_stc_ret
	clc
	ret
pc_stc_ret:
	stc
	ret

;==============================================================================
;	文字列のセット
;		crlfが来るまで
;==============================================================================
set_strings:
	lodsb
	cmp	al,9	;TAB
	jz	setstr_next
	cmp	al,1bh	;ESC
	jz	setstr_next
	cmp	al," "
	jc	setstr_exit
setstr_next:
	stosb
	jmp	set_strings
setstr_exit:
	dec	si
	xor	al,al
	stosb
	ret

set_strings2:	;小文字＞大文字変換付き
	lodsb
	cmp	al,9	;TAB
	jz	setstr_next2
	cmp	al,1bh	;ESC
	jz	setstr_next2
	cmp	al," "
	jc	setstr_exit2
	cmp	al,"a"
	jc	setstr_next2
	cmp	al,"z"+1
	jnc	setstr_next2
	sub	al,"a"-"A"
setstr_next2:
	stosb
	jmp	set_strings2
setstr_exit2:
	dec	si
	xor	al,al
	stosb
	ret

;==============================================================================
;	次のパラメータに強制移動する
;		1.space又はtabをsearch
;		2.文字列をsearch
;==============================================================================
move_next_param:
	lodsb
	cmp	al,9	;TAB
	jz	mnp_loop
	cmp	al," "
	jz	mnp_loop
	jc	mnp_errret
	jmp	move_next_param

mnp_loop:
	lodsb
	cmp	al,1bh	;ESC
	jz	mnp_exit
	cmp	al,9	;TAB
	jz	mnp_loop
	cmp	al," "
	jz	mnp_loop
	jc	mnp_errret
mnp_exit:
	dec	si
	clc
	ret
mnp_errret:
	stc
	ret

;==============================================================================
;	MML 変数の設定
;==============================================================================
hsset:
	call	lngset2
	jnc	hsset2

	lodsb
	sub	al,64
	mov	dx,"!"*256+7
	jc	error
	cmp	al,64
	jnc	error

	xor	ah,ah
	add	ax,ax
	add	ax,offset hsbuf
	mov	bx,ax
	jmp	hsset3

hsset2:
	xor	ah,ah
	add	ax,ax
	add	ax,offset hsbuf2
	mov	bx,ax
	jmp	hsset3

hsset3:
	push	si
hsset_loop:
	lodsb
	cmp	al,0dh	;cr
	jz	hsset_fin
	cmp	al," "+1
	jnc	hsset_loop

	mov	[bx],si

hsset_fin:
	pop	si
	cmp	[pass],0
	jz	p1_hsset_fin
	jmp	c_next
p1_hsset_fin:
	jmp	p1c_fin

;==============================================================================
;	音色の設定
;		@ num,alg,fb
;		  ar,dr,sr,rr,sl,tl,ks,ml,dt,[dt2,]ams
;		  ar,dr,sr,rr,sl,tl,ks,ml,dt,[dt2,]ams
;		  ar,dr,sr,rr,sl,tl,ks,ml,dt,[dt2,]ams
;		  ar,dr,sr,rr,sl,tl,ks,ml,dt,[dt2,]ams
;	(OPL)
;		@ num,alg,fb
;		  ar,dr,rr,sl,tl,ksl,ml,ksr,egt,vib,am
;		  ar,dr,rr,sl,tl,ksl,ml,ksr,egt,vib,am
;==============================================================================
new_neiro_set:
	push	di
	push	bx
	call	nns
	pop	bx
	pop	di
	jmp	p1c_fin

nns:
	cmp	[opl_flg],1
	jz	opl_nns

	push	es
	mov	ax,mml_seg
	mov	es,ax
	assume	es:mml_seg
	mov	di,offset prgbuf_start
	mov	cx,prgbuf_length/2
	xor	ax,ax
rep	stosw
	pop	es
	assume	es:m_seg

	call	get_param
	mov	[newprg_num],al
	call	get_param
	and	al,00000111b
	mov	ch,al
	push	cx
	call	get_param
	pop	cx
	and	al,00000111b
	rol	al,1
	rol	al,1
	rol	al,1
	or	al,ch
	mov	[alg_fb],al
	mov	[prg_name],0

	mov	di,offset slot_1
	call	slot_get
	mov	di,offset slot_2
	call	slot_get
	mov	di,offset slot_3
	call	slot_get
	mov	di,offset slot_4
	call	slot_get

	mov	bx,offset voice_buf
if	split
	inc	bx
endif

	mov	dl,[newprg_num]
	xor	dh,dh
	add	dx,dx
	add	dx,dx
	add	dx,dx
	add	dx,dx
	add	dx,dx	;*32

	add	dx,bx

	push	es
	mov	ax,voice_seg
	mov	es,ax
	assume	es:voice_seg
	mov	bx,offset slot_1
	call	slot_trans
	inc	dx
	mov	bx,offset slot_3
	call	slot_trans
	inc	dx
	mov	bx,offset slot_2
	call	slot_trans
	inc	dx
	mov	bx,offset slot_4
	call	slot_trans
	mov	bx,21
	add	bx,dx
	mov	al,[alg_fb]
	mov	es:[bx],al
	inc	bx

nns_pname_set:
	mov	bp,offset prg_name
	mov	cx,7
nns_loop:
	mov	al,ds:[bp]
	or	al,al
	jz	nnsl_00
	inc	bp
nnsl_00:
	mov	byte ptr es:[bx],al
	inc	bx
	loop	nns_loop
	pop	es
	assume	es:m_seg

	ret

;==============================================================================
;	OPL版音色設定
;==============================================================================
opl_nns:
	push	es
	push	si
	mov	ax,mml_seg
	mov	es,ax
	assume	es:mml_seg
	mov	di,offset oplbuf
	mov	cx,8
	xor	ax,ax
rep	stosw

	call	get_param
	mov	[newprg_num],al

	mov	bx,offset oplprg_table
	mov	di,offset oplbuf

	mov	cx,2+11*2

oplset_loop:
	push	cx
	push	bx
	call	get_param
	pop	bx
	and	al,1[bx]	;max
	mov	cl,2[bx]	;rot
	rol	al,cl
	push	bx
	mov	bl,0[bx]	;offset
	xor	bh,bh
	or	[di+bx],al	;設定
	pop	bx
	pop	cx
	add	bx,3

	loop	oplset_loop

	mov	ax,voice_seg
	mov	es,ax
	assume	es:voice_seg

	mov	si,offset oplbuf
	mov	di,offset voice_buf
	mov	dl,[newprg_num]
	xor	dh,dh
	add	dx,dx
	add	dx,dx
	add	dx,dx
	add	dx,dx	;*16

	add	di,dx

	mov	cx,9
rep	movsb
	pop	si

	mov	bx,di
	jmp	nns_pname_set

	assume	es:m_seg

;==============================================================================
;	スロット毎のデータを転送
;==============================================================================
slot_trans:
	mov	bp,dx
	mov	cx,6
st_loop:
	mov	al,[bx]
	mov	es:[bp],al
	inc	bx
	add	bp,4
	loop	st_loop
	ret

;==============================================================================
;	各スロットの数値を読む
;==============================================================================
slot_get:
	call	get_param	;AR
	and	al,00011111b
	mov	[di+2],al
	call	get_param	;DR
	and	al,00011111b
	mov	[di+3],al
	call	get_param	;SR
	and	al,00011111b
	mov	[di+4],al
	call	get_param	;RR
	and	al,00001111b
	mov	[di+5],al
	call	get_param	;SL
	and	al,00001111b
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	or	[di+5],al
	call	get_param	;TL
	and	al,01111111b
	mov	[di+1],al
	call	get_param	;KS
	and	al,00000011b
	ror	al,1
	ror	al,1
	or	[di+2],al
	call	get_param	;ML
	and	al,00001111b
	mov	[di+0],al
	call	get_param	;DT
	test	al,80h
	jz	dt_norm_set
	neg	al
	and	al,00000011b
	or	al,00000100b
dt_norm_set:
	and	al,00000111b
	ror	al,1
	ror	al,1
	ror	al,1
	ror	al,1
	or	[di+0],al

	cmp	[dt2_flg],0
	jz	ams_set
	call	get_param	;DT2 (for opm)
	and	al,00000011b
	ror	al,1
	ror	al,1
	or	[di+4],al

ams_set:
	call	get_param	;AMS
	and	al,00000001b
	ror	al,1
	or	[di+3],al
	ret

;==============================================================================
;	音色設定用パラメータの取り出し
;==============================================================================
get_param:
	lodsb
	cmp	al," "
	jz	get_param
	cmp	al,9	;tab
	jz	get_param
	cmp	al,","
	jz	get_param
	cmp	al,"="
	jz	get_vname
	cmp	al,";"
	jz	gp_skip
	cmp	al,13
	jz	gp_skip

	dec	si
	cmp	al,"+"
	jz	gp_gnm
	cmp	al,"-"
	jz	gp_gnm
	call	numget
	mov	dx,"@"*256+1
	jc	error
	dec	si
gp_gnm:
	call	getnum
	mov	al,dl
	ret
gp_skip:
	call	line_skip
	cmp	byte ptr [si],1ah
	mov	dx,"@"*256+6
	jz	error
	jmp	get_param

get_vname:
	dec	si
gsc_loop:
	inc	si
	cmp	byte ptr [si]," "
	jz	gsc_loop
	cmp	byte ptr [si],9
	jz	gsc_loop

	mov	bp,offset prg_name
	mov	cx,7
gvn_loop:
	lodsb
;;	cmp	al," "
;;	jz	gv_skip
;;	cmp	al,";"
;;	jz	gv_skip
	cmp	al,9
	jz	gv_skip
	cmp	al,13
	jz	gv_skip
	mov	ds:[bp],al
	inc	bp
	loop	gvn_loop
gv_skip:
	mov	byte ptr ds:[bp],0
	jmp	gp_skip

;==============================================================================
;	一行 Compile
;		INPUTS	-- ds:si to MML POINTER
;			-- es:di to M POINTER
;			-- [PART] to PART
;==============================================================================
one_line_compile:
	lodsb
	cmp	al,0dh	;cr
	jz	olc_fin
	cmp	al,";"
	jz	olc_skip
	cmp	al," "+1
	jnc	one_line_compile
	mov	[lastprg],0	;Rパート用

olc0:	xor	al,al
olc02:	mov	[prsok],al
	cmp	byte ptr es:[mbuf_end],07fh	;check code
	mov	dx,19
	jnz	error	;容量オーバー
olc03:	lodsb
	cmp	al," "
	jz	olc03
	cmp	al,9
	jz	olc03	;tab
	cmp	al,";"
	jnz	notskp
olc_skip:
	call	line_skip
	jmp	comend

notskp:	cmp	al,'"'
	jnz	nskp_01
	xor	[skip_flag],1
	jmp	olc03

nskp_01:
	cmp	al,"'"
	jnz	nskp_02
	mov	[skip_flag],0
	jmp	olc03

nskp_02:
ife	efc
	cmp	al,"|"
	jz	skip_mml
endif

	cmp	al,"/"
	jz	part_end2

notend:	cmp	al,13
	jnz	olc00
olc_fin:
	inc	si

comend:	cmp	[hsflag],0
	jnz	hs_ret
	jmp	cloop

part_end2:
	cmp	[hsflag],0
	jz	part_end
hs_ret:
	ret

ife	efc
;==============================================================================
;	"|" command (Skip MML except selected Parts)
;==============================================================================
skip_mml:
	cmp	byte ptr [si]," "+1
	jc	olc03		; | only = Select All

	mov	ah,[part]
	add	ah,"A"-1
skm_loop:
	lodsb
	cmp	al,ah
	jz	part_found
	cmp	al,13		; cr
	jz	olc_fin		; line end
	cmp	al," "+1
	jnc	skm_loop

;==============================================================================
;	Not Found --- Skip to Next "|" or Next line
;==============================================================================
part_not_found:
	lodsb
	cmp	al,13		; cr
	jz	olc_fin		; line_end
	cmp	al,"|"
	jnz	part_not_found
	jmp	skip_mml

;==============================================================================
;	Found --- Cancel for the other Parts & Compile Next
;==============================================================================
part_found:
	lodsb
	cmp	al,13		; cr
	jz	olc_fin		; line end
	cmp	al," "+1
	jnc	part_found
	jmp	olc03
endif

;==============================================================================
;	Command Jump
;==============================================================================
olc00:	
	mov	bx,offset comtbl
olc1:	cmp	al,cs:[bx]
	jz	jump
	add	bx,3
	cmp	cs:byte ptr [bx],0
	mov	dx,1
	jz	error
	jmp	olc1

jump:	inc	bx
	mov	dh,al
	mov	ax,cs:[bx]
	jmp	ax

;==============================================================================
;	Command Table
;==============================================================================

comtbl:	db	"c"
	dw	otoc
	db	"d"
	dw	otod
	db	"e"
	dw	otoe
	db	"f"
	dw	otof
	db	"g"
	dw	otog
	db	"a"
	dw	otoa
	db	"b"
	dw	otob
	db	"r"
	dw	otor
	db	"l"
	dw	lengthset
	db	"o"
	dw	octset
ou00	db	">"
	dw	octup
od00	db	"<"
	dw	octdown
	db	"C"
	dw	zenlenset
	db	"t"
	dw	tempoa
	db	"T"
	dw	tempob
	db	"q"
	dw	qset
	db	"Q"
	dw	qset2
	db	"v"
	dw	vseta
	db	"V"
	dw	vsetb

	db	"R"
	dw	neirochg
	db	"@"
	dw	neirochg

	db	"&"
	dw	tieset
	db	"D"
	dw	detset
	db	"["
	dw	stloop
	db	"]"
	dw	edloop
	db	":"
	dw	extloop
	db	"L"
	dw	lopset
	db	"_"
	dw	oshift
	db	")"
	dw	volup
	db	"("
	dw	voldown
	db	"M"
	dw	lfoset
	db	"*"
	dw	lfoswitch
	db	"E"
	dw	psgenvset
	db	"y"
	dw	ycommand
	db	"w"
	dw	psgnoise
	db	"P"
	dw	psgpat
	db	"!"
	dw	hscom
	db	"B"
	dw	bendset
	db	"I"
	dw	pitchset
	db	"p"
	dw	panset
	db	"\"
	dw	rhycom

	db	"X"
	dw	octrev
	db	"^"
	dw	lngmul
	db	"="
	dw	lngrew

	db	"H"
	dw	hardlfo_set
	db	"#"
	dw	hardlfo_onoff

	db	"Z"
	dw	syousetu_lng_set

	db	"S"
	dw	sousyoku_onp_set
	db	"W"
	dw	giji_echo_set

	db	7eh	;	"~"
	dw	status_write

	db	"{"
	dw	porta_start
	db	"}"
	dw	porta_end

	db	"n"
	dw	ssg_efct_set
	db	"N"
	dw	fm_efct_set
	db	"F"
	dw	fade_set

	db	"s"
	dw	slotmask_set

	db	"0"
	dw	lngrew_2
	db	"1"
	dw	lngrew_2
	db	"2"
	dw	lngrew_2
	db	"3"
	dw	lngrew_2
	db	"4"
	dw	lngrew_2
	db	"5"
	dw	lngrew_2
	db	"6"
	dw	lngrew_2
	db	"7"
	dw	lngrew_2
	db	"8"
	dw	lngrew_2
	db	"9"
	dw	lngrew_2
	db	"%"
	dw	lngrew_2
	db	"$"
	dw	lngrew_2

	db	0

;==============================================================================
;	s command (fm slot mask)
;==============================================================================
slotmask_set:
	cmp	byte ptr [si],"d"
	jz	slotdetune_set
	call	lngset
	mov	byte ptr es:[di],0cfh
	inc	di
	mov	ah,al
	xor	al,al
	cmp	byte ptr [si],","
	jnz	not_car_set
	inc	si
	call	lngset
not_car_set:
	rol	ah,1
	rol	ah,1
	rol	ah,1
	rol	ah,1
	and	ah,0f0h
	and	al,00fh
	or	al,ah
	stosb
	jmp	olc0

;==============================================================================
;	sd command (slot detune) / sdd command (slot detune 相対)
;==============================================================================
slotdetune_set:
	mov	al,0c8h
	inc	si
	cmp	byte ptr [si],"d"
	jnz	sds_set
	dec	al	;al=0c7h
	inc	si
sds_set:
	stosb
	call	getnum
	mov	al,dl
	stosb
	cmp	byte ptr [si],","
	mov	dx,"s"*256+6
	jnz	error
	inc	si
	call	getnum
	mov	ax,bx
	stosw
	jmp	olc0

;==============================================================================
;	n command (ssg effect)
;==============================================================================
ssg_efct_set:
	call	lngset
	cmp	[skip_flag],0
	jnz	olc03
	mov	byte ptr es:[di],0d4h
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	N command (fm effect)
;==============================================================================
fm_efct_set:
	call	lngset
	cmp	[skip_flag],0
	jnz	olc03
	mov	byte ptr es:[di],0d3h
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	F command (fadeout)
;==============================================================================
fade_set:
	call	lngset
	mov	byte ptr es:[di],0d2h
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	"{" Command [Portament_start]
;==============================================================================
porta_start:
	cmp	[skip_flag],0
	jnz	olc03
	cmp	[porta_flag],0
	mov	dx,"{"*256+9
	jnz	error
	mov	byte ptr es:[di],0dah
	inc	di
	mov	[porta_flag],1
	jmp	olc0

;==============================================================================
;	"}" Command [Portament_end]
;==============================================================================
porta_end:
	cmp	[skip_flag],0
	jnz	pe_skip
	cmp	[porta_flag],1
	mov	dx,"}"*256+13
	jnz	error
	cmp	byte ptr es:-5[di],0dah
	mov	dl,14
	jnz	error
	cmp	byte ptr es:-4[di],0fh
	mov	dl,15
	jz	error
	cmp	byte ptr es:-2[di],0fh
	jz	error
	mov	al,byte ptr es:-2[di]
	mov	byte ptr es:-3[di],al
	dec	di
	dec	di
	mov	[porta_flag],0
	call	lngset2
	call	lngcal
	call	futen
	stosb
	jmp	olc0

pe_skip:
	call	lngset2
	call	lngcal
	call	futen
	jmp	olc03

;==============================================================================
;	"~" Command [ＳＴＡＴＵＳの書き込み]
;	~[+,-]n
;==============================================================================
status_write:
	cmp	byte ptr [si],"-"
	jz	sw_sweep
	cmp	byte ptr [si],"+"
	jz	sw_sweep
	call	lngset
	mov	dl,al
	mov	dh,0dch
	jmp	parset
sw_sweep:
	call	getnum
	mov	dh,0dbh
	jmp	parset

;==============================================================================
;	"W" Command [擬似エコーの設定]
;	Wdelay[,+-depth][,tie/nextflag]
;==============================================================================
giji_echo_set:
	call	lngset
	mov	[ge_delay],al
	or	al,al
	jz	ge_cut
	mov	[ge_tie],0
	mov	[ge_depth],-1
	mov	[ge_depth2],-1
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	getnum
	mov	[ge_depth],dl
	mov	[ge_depth2],dl
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	lngset
	mov	[ge_tie],al
	jmp	olc03
ge_cut:
	mov	[ge_depth],al
	mov	[ge_depth2],al
	jmp	olc03

;==============================================================================
;	"S" Command [装飾音符の設定]
;	Sspeed[,depth]
;==============================================================================
sousyoku_onp_set:
	call	lngset
	mov	[ss_speed],al
	or	al,al
	jz	ss_cut
	mov	[ss_tie],1
	mov	[ss_depth],-1
	cmp	byte ptr [si],","
	jnz	ss_exit
	inc	si
	call	getnum
	mov	[ss_depth],dl
	cmp	byte ptr [si],","
	jnz	ss_exit
	inc	si
	call	lngset
	mov	[ss_tie],al
ss_exit:
	mov	ah,[ss_depth]
	test	ah,80h
	jz	ss_exit_1
	neg	ah
ss_exit_1:
	mov	al,[ss_speed]
	cmp	ah,1
	jz	ss_exit_2
	mul	ah
	mov	dx,"S"*256+2
	jc	error
ss_exit_2:
	mov	[ss_length],al
	jmp	olc03
ss_cut:
	xor	al,al
	mov	[ss_depth],al
	mov	[ss_length],al
	jmp	olc03

;==============================================================================
;	"Z" Command [小節の長さ指定]
;==============================================================================
syousetu_lng_set:
	call	lngset
syousetu_lng_set_2:
	mov	dl,al
	mov	dh,0dfh
	jmp	parset

;==============================================================================
;	"H" Command （ハードＬＦＯの設定）
;	 Hpms[,ams]
;==============================================================================
hardlfo_set:
if	efc
	mov	dx,"H"*256+11
	jmp	error
else
	call	lngset
	cmp	al,8
	mov	dx,"H"*256+2
	jnc	error
	cmp	byte ptr [si],","
	jnz	pmsonly
	inc	si
	push	ax
	call	lngset
	pop	bx
	cmp	al,4
	mov	dx,"H"*256+2
	jnc	error
	jmp	bxset00
pmsonly:
	mov	bl,al
	xor	al,al
bxset00:
	rol	al,1
	rol	al,1
	rol	al,1
	rol	al,1
	or	al,bl
	and	al,00110111b
	mov	dl,al
	mov	dh,0e1h
	jmp	parset
endif
;==============================================================================
;	Command "#" （ハードＬＦＯのスイッチ）
;	 #sw[,depth]
;	Command "#w/#p/#a/##" （OPM用）
;	 #w wf
;	 #p pmd
;	 #a amd
;	 ## wf,pmd,amd
;==============================================================================
hardlfo_onoff:
if	efc
	mov	dx,"#"*256+11
	jmp	error
else
	lodsb
	cmp	al,"f"
	jz	opm_hf_set
	cmp	al,"w"
	jz	opm_wf_set
	cmp	al,"p"
	jz	opm_pmd_set
	cmp	al,"a"
	jz	opm_amd_set
	cmp	al,"#"
	jz	opm_all_set

	dec	si
	call	lngset
	or	al,al
	jnz	hlon
	mov	dx,0e000h
	jmp	parset
hlon:
	cmp	byte ptr [si],","
	mov	dx,"#"*256+6
	jnz	error
	inc	si
	call	lngset
	cmp	al,8
	mov	dx,"#"*256+2
	jnc	error
	or	al,00001000b
	mov	dl,al
	mov	dh,0e0h
	jmp	parset

opm_hf_set:
	call	hf_set
	jmp	olc0

opm_wf_set:
	call	wf_set
	jmp	olc0

opm_pmd_set:
	call	pmd_set
	jmp	olc0

opm_amd_set:
	call	amd_set
	jmp	olc0

opm_all_set:
	call	hf_set
	lodsb
	cmp	al,","
	mov	dx,"#"*256+6
	jnz	error
	call	wf_set
	lodsb
	cmp	al,","
	jnz	error
	call	pmd_set
	lodsb
	cmp	al,","
	jnz	error
	call	amd_set
	jmp	olc0

hf_set:
	call	getnum
	mov	byte ptr es:[di],0d7h
	inc	di
	mov	es:[di],dl
	inc	di
	ret

wf_set:
	call	lngset
	cmp	al,4
	mov	dx,"#"*256+2
	jnc	error
	mov	byte ptr es:[di],0d9h
	inc	di
	stosb
	ret

pmd_set:
	call	getnum
	or	dl,80h
	mov	byte ptr es:[di],0d8h
	inc	di
	mov	es:[di],dl
	inc	di
	ret

amd_set:
	call	getnum
	and	dl,7fh
	mov	byte ptr es:[di],0d8h
	inc	di
	mov	es:[di],dl
	inc	di
	ret

endif
;==============================================================================
;	"<",">" の反転
;==============================================================================
octrev:	mov	al,cs:[ou00]
	xchg	al,cs:[od00]
	mov	cs:[ou00],al
	jmp	olc03

;==============================================================================
;	"^" ... Length Multiple
;==============================================================================
lngmul:	call	reget
	call	lngset
	or	al,al
	mov	dx,"^"*256+2
	jz	error
	cmp	[ge_delay],0
	mov	dl,31
	jnz	error
	cmp	[ss_length],0
	jnz	error

	cmp	[skip_flag],0
	jnz	olc03

	dec	al
	jz	olc03
	mov	cl,al
	xor	ch,ch		; cx = 足す回数

	mov	al,es:-1[di]	; al = 足される数
	mov	ah,al		; ah = 足す数
lnml00:
	add	al,ah
	jc	lm_over
lnml01:
	loop	lnml00

	mov	es:-1[di],al
	jmp	olc03

lm_over:
	inc	al
	mov	byte ptr es:-1[di],0ffh
	mov	byte ptr es:[di],0fbh
	mov	bl,es:-2[di]
	mov	es:1[di],bl
	mov	byte ptr es:2[di],0
	add	di,3
	jmp	lnml01

;==============================================================================
;	"=" ... Length Rewrite
;==============================================================================
lngrew:	cmp	[ge_delay],0
	mov	dx,"="*256+31
	jnz	error
	cmp	[ss_length],0
	jnz	error
	call	reget
	call	lngset2
	call	lngcal
	call	futen
	cmp	[skip_flag],0
	jnz	olc03
	mov	es:-1[di],al
	jmp	olc03
lngrew_2:
	dec	si
	jmp	lngrew

;==============================================================================
;	音長を再度読めるかを判定
;==============================================================================
reget:	cmp	[prsok],1
	mov	dl,16
	jnz	error
	cmp	byte ptr es:-3[di],0fbh
	mov	dl,17
	jz	error
	ret

;==============================================================================
;	c ～ b の時
;==============================================================================
otoc:	mov	al,0
	jmp	otoset
otod:	mov	al,2
	jmp	otoset
otoe:	mov	al,4
	jmp	otoset
otof:	mov	al,5
	jmp	otoset
otog:	mov	al,7
	jmp	otoset
otoa:	mov	al,9
	jmp	otoset
otob:	mov	al,0bh
	jmp	otoset
otor:	mov	al,0fh
	jmp	rest

otoset:
ife	efc
	cmp	[part],rhythm2
	mov	dl,17
	jz	error		; K part = error
	cmp	[part],rhythm
	jnz	ots000
;==============================================================================
;	リズム（Ｒ）パートで音程が指定された＝［＠ｎ　ｃ］に変換
;==============================================================================
	mov	cx,[lastprg]
	or	cx,cx
	mov	dl,30
	jz	error
	cmp	[skip_flag],0
	jnz	not_set_00
	xchg	ch,cl
	mov	es:[di],cx
	inc	di
	inc	di
	mov	[length_check1],1	;音長データがあったよ
	mov	[length_check2],1
not_set_00:
	mov	[prsok],0	;圧縮しちゃだめだめだめぇ
	jmp	bp9
endif
;==============================================================================
;	+,- 判定
;==============================================================================
ots000:
	cmp	byte ptr [si],"+"
	jnz	bp2
	inc	al
	inc	si	

bp2:	cmp	byte ptr [si],"-"
	jnz	bp3
	dec	al
	inc	si
	
;==============================================================================
;	c- は 1oct 下へ, b+ は 1oct 上へ
;==============================================================================

bp3:	and	al,0fh
	mov	bl,al
	mov	al,[octarb]
	and	al,0fh
	mov	bh,al
	cmp	bl,0fh
	jnz	bp4
	dec	bh
	cmp	bh,-1
	mov	dl,26
	jz	error
	mov	bl,0bh
bp4:	
	cmp	bl,0ch
	jnz	bp5
	inc	bh
	cmp	bh,8
	mov	dl,26
	jz	error
	xor	bl,bl
bp5:
	mov	al,bl
	cmp	byte ptr [si],"+"	;++
	jz	ots000
	cmp	byte ptr [si],"-"	;--
	jz	ots000

;==============================================================================
;	音階データをblにセット
;==============================================================================
	ror	bh,1
	ror	bh,1
	ror	bh,1
	ror	bh,1
	or	bl,bh	; bl=音階 DATA

	cmp	[bend],0
	jz	bp8

	; PITCH/DETUNE SET
	push	bx

	mov	al,bl
	xor	bx,bx
	cmp	[pitch],0
	jz	bp6

ife	efc
	cmp	[ongen],psg
	jc	fmpt
	mov	bx,[pitch]
	sar	bx,1		; PSG/PCMの時はPITCHを128で割る
	sar	bx,1
	sar	bx,1
	sar	bx,1
	sar	bx,1
	sar	bx,1
	sar	bx,1
	test	bx,8000h
	jz	bp6
	inc	bx
	jmp	bp6
endif

fmpt:	and	al,0fh
	xor	ah,ah
	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1
	shl	ax,1
	mov	dx,ax		;DX = PITCHを掛けない状態のFnum値のある番地

	push	dx
	xor	dx,dx
	mov	ax,32
	mov	bl,[bend]
	xor	bh,bh
	imul	bx
	mov	bx,[pitch]
	imul	bx
	mov	bx,8192
	idiv	bx		;AX = PITCHでずらす番地 / 2
	pop	dx

	mov	bx,dx
	push	ds
	mov	cx,fnumdat_seg
	mov	ds,cx
	mov	dx,ds:[bx]	;DX = PITCHを掛けない状態の Fnum値
	pop	ds
	shl	ax,1
	add	bx,ax		;BX = PITCHを掛けた後のFnum値のある番地

bp50:	or	bx,bx		;オクターブを下回ったか？
	jns	bp51
	add	bx,32*12*2
	add	dx,26ah
	jmp	bp50
bp51:	cmp	bx,32*12*2	;オクターブを上回ったか？
	jc	bp52
	sub	bx,32*12*2
	sub	dx,26ah
	jmp	bp50

bp52:	push	ds
	mov	cx,fnumdat_seg
	mov	ds,cx
	sub	dx,ds:[bx]
	pop	ds
	mov	bx,dx
	neg	bx		;BX = PITCHをDETUNEに換算した値
bp6:
	add	bx,[detune]
	cmp	bx,[alldet]
	jz	bp7
	cmp	[porta_flag],1
	jz	porta_pitchset
	mov	al,0fah
	stosb
	mov	es:[di],bx
	add	di,2
bp6b:	mov	[alldet],bx

bp7:	pop	bx
	jmp	bp8

porta_pitchset:
	cmp	byte ptr es:-1[di],0dah
	mov	dx,14
	jnz	error
	dec	di
	mov	al,0fah
	stosb
	mov	es:[di],bx
	add	di,2
	mov	byte ptr es:[di],0dah
	inc	di
	jmp	bp6b

;==============================================================================
;	REST 用 entry
;==============================================================================

rest:
ife	efc
	cmp	[part],rhythm2
	mov	dx,"r"*256+17
	jz	error		; K part = error
endif
	mov	bl,al

;==============================================================================
;	音階 DATA SET
;==============================================================================

bp8:	cmp	[skip_flag],0
	jnz	bp9
	mov	[length_check1],1	;音長データがあったよ
	mov	[length_check2],1
	mov	es:[di],bl
	inc	di

;==============================================================================
;	音長計算
;==============================================================================

bp9:	call	lngset2
	call	lngcal
	call	futen
	call	press

;==============================================================================
;	音長 DATA SET
;==============================================================================

	cmp	[skip_flag],0
	jnz	bp10
	mov	al,[length]
	stosb

	mov	al,es:-2[di]
	and	al,0fh
	cmp	al,0fh
	jz	bp10		;休符

	cmp	[tie_flag],0
	jnz	bp10
	cmp	[porta_flag],0
	jnz	bp10

	mov	[ge_flag1],0
	mov	[ge_flag2],0

	cmp	[ge_delay],0
	jz	bp9_2
	call	ge_set		;擬似エコーセット＋装飾音符設定
	jmp	bp10
bp9_2:
	cmp	[ss_length],0
	jz	bp10
	call	ss_set		;装飾音符設定
bp10:
	mov	[tie_flag],0

	mov	al,1
	jmp	olc02

;==============================================================================
;	擬似エコーのセット
;==============================================================================
ge_set:
	mov	al,[ge_depth2]
	mov	[ge_depth],al
ge_loop:
	mov	al,es:-1[di]
	sub	al,[ge_delay]
	jbe	ge_set_ret	;長さが足りない(cf or zf=1)
	mov	dh,al		;dh=length-delay
	mov	dl,es:-2[di]	;dl=onkai
	mov	al,[ge_delay]
	mov	es:-1[di],al
	cmp	[ss_length],0
	jz	ge_ss1
	push	dx
	call	ss_set
	pop	dx
ge_ss1:
	test	[ge_tie],1
	jz	ge_not_tie

	mov	byte ptr es:[di],0fbh	;"&"
	inc	di
ge_not_tie:
	call	ge_set_vol

	mov	es:[di],dx
	inc	di
	inc	di

	test	[ge_tie],2
	jnz	ge_set_ret
	jmp	ge_loop

ge_set_ret:
	cmp	[ss_length],0
	jz	ge_ss2
	call	ss_set
ge_ss2:	ret

ge_set_vol:
	mov	al,[ge_depth]
	test	al,80h
	jnz	ge_minus
	or	al,al
	jz	gen_00

;==============================================================================
;	音量が上がる
;==============================================================================
	mov	byte ptr [di],0deh
	inc	di
	mov	[ge_flag1],0deh
	call	ongen_sel_vol
	stosb
	mov	[ge_flag2],al
	mov	al,[ge_depth]
	add	al,[ge_depth2]
	cmp	al,16
	jc	gen_00
	mov	al,15
gen_00:
	mov	[ge_depth],al
	ret

;==============================================================================
;	音量が下がる
;==============================================================================
ge_minus:
	neg	al
	mov	byte ptr es:[di],0ddh
	inc	di
	mov	[ge_flag1],0ddh
	call	ongen_sel_vol
	stosb
	mov	[ge_flag2],al
	mov	al,[ge_depth]
	add	al,[ge_depth2]
	cmp	al,-15
	jnc	gem_00
	mov	al,-15
gem_00:
	mov	[ge_depth],al
	ret

;==============================================================================
;	各音源によって音量の増減を変える
;==============================================================================
ongen_sel_vol:
ife	efc
	cmp	[part],pcmpart
	jz	sel_pcm
	cmp	[ongen],psg
	jnz	sel_fm
	ret
sel_fm:
endif
	add	al,al
	add	al,al
	ret

ife	efc
sel_pcm:
	add	al,al
	add	al,al
	add	al,al
	add	al,al
	ret
endif
;==============================================================================
;	装飾音符のセット
;==============================================================================
ss_set:
	mov	al,[ss_length]
	sub	al,es:-1[di]
	jnc	ss_set_ret	;長さが足りない
	dec	di
	dec	di
	mov	dx,es:[di]
	xchg	dh,dl		;Dh=Onkai/Dl=Length
	mov	al,[ss_depth]
	test	al,80h
	jz	ss_plus

;==============================================================================
;	下から上がる
;==============================================================================
	neg	al
	mov	cl,al
	xor	ch,ch	; cx = Depth
	mov	bh,dh	; bh = Onkai(for Move)
ss_minus_loop:
	call	one_down
	loop	ss_minus_loop

ss_minus_loop2:
	cmp	[ge_flag1],0
	jz	ssm_non_ge
	mov	al,[ge_flag1]
	stosb
	mov	al,[ge_flag2]
	stosb
ssm_non_ge:
	mov	al,[ss_speed]
	mov	es:[di],bh
	inc	di
	stosb

	cmp	[ss_tie],0
	jz	ssm_not_tie

	mov	byte ptr es:[di],0fbh	;"&"
	inc	di
ssm_not_tie:

	call	one_up
	cmp	bh,dh
	jnz	ss_minus_loop2
	jmp	ss_fin

;==============================================================================
;	上から下がる
;==============================================================================
ss_plus:
	mov	cl,al
	xor	ch,ch	; cx = Depth
	mov	bh,dh	; bh = Onkai (for Move)
ss_plus_loop:
	call	one_up
	loop	ss_plus_loop

ss_plus_loop2:
	cmp	[ge_flag1],0
	jz	ssp_non_ge
	mov	al,[ge_flag1]
	stosb
	mov	al,[ge_flag2]
	stosb
ssp_non_ge:
	mov	al,[ss_speed]
	mov	es:[di],bh
	inc	di
	stosb

	cmp	[ss_tie],0
	jz	ssp_not_tie

	mov	byte ptr es:[di],0fbh	;"&"
	inc	di
ssp_not_tie:

	call	one_down
	cmp	bh,dh
	jnz	ss_plus_loop2

;==============================================================================
;	最後の音符を書き込む
;==============================================================================
ss_fin:
	cmp	[ge_flag1],0
	jz	ssf_non_ge
	mov	al,[ge_flag1]
	stosb
	mov	al,[ge_flag2]
	stosb
ssf_non_ge:
	mov	es:[di],dh
	inc	di
	sub	dl,[ss_length]
	mov	es:[di],dl
	inc	di
ss_set_ret:
	ret

;==============================================================================
;	音階を一つ下げる
;		input/output	bh to Onkai
;==============================================================================
one_down:
	dec	bh
	mov	al,bh
	and	al,0fh
	cmp	al,0fh
	jnz	one_down_ret
	and	bh,0f0h
	or	bh,0bh
	test	bh,80h
	push	dx
	mov	dx,"S"*256+26
	jnz	error
	pop	dx
one_down_ret:
	ret

;==============================================================================
;	音階を一つ上げる
;		input/output	bh to Onkai
;==============================================================================
one_up:
	inc	bh
	mov	al,bh
	and	al,0fh
	cmp	al,0ch
	jnz	one_up_ret
	and	bh,0f0h
	add	bh,10h
	test	bh,80h
	push	dx
	mov	dx,"S"*256+26
	jnz	error
	pop	dx
one_up_ret:
	ret

;==============================================================================
;	前も同じ音符で、しかも"&"で繋がっていた場合は、圧縮する処理
;==============================================================================
press:	cmp	[prsok],1
	jnz	press_ret
	cmp	[skip_flag],0
	jnz	press_ret

	cmp	byte ptr es:-1[di],0fh
	jz	restprs

ife	efc
	cmp	[part],rhythm
	jz	prs3		;リズムパートで圧縮可能＝無条件に圧縮
endif

	cmp	byte ptr es:-2[di],0fbh
	jnz	press_ret

prs0:	mov	ah,es:-1[di]
	cmp	ah,es:-4[di]
	jnz	press_ret
prs1:	sub	di,3
	add	al,es:[di]
	jnc	prs200
	sub	al,es:[di]
	add	di,3
press_ret:
	ret

prs200:
	mov	[length],al
	ret
;
restprs:
ife	efc
	cmp	[part],rhythm
	jz	prs3
endif
	cmp	byte ptr es:-3[di],0fh
	jnz	press_ret

prs3:	dec	di
	dec	di
	add	al,es:[di]
	jnc	prs200
	sub	al,es:[di]
	inc	di
	inc	di
	ret

;==============================================================================
;	数値の読み出し（書かれていない時は１）
;		output	bx/al/[length]
;==============================================================================
lngset:
	call	lngset2
	jnc	lngset_ret
	mov	bx,1
	jmp	lnexit

;==============================================================================
;	[si]から数値を読み出す
;	数字が書かれていない場合は[deflng]の値が返り、cy=1になる
;		output	al/bx/[length]
;==============================================================================
lngset2:
	xor	bh,bh
	mov	[calflg],bh
	cmp	byte ptr [si],"%"
	jnz	lgs00
	inc	si
	mov	[calflg],1
lgs00:	cmp	byte ptr [si],"$"
	jz	lgs01

;	10進の場合
	call	numget
lgs02:	mov	bl,al
	jnc	lng1
lgs03:	mov	bl,[deflng]
	stc
	jmp	lnexit

lng1:	call	numget	;A=NUMBER
	jnc	lng2

	clc
lnexit:	mov	al,bl
	mov	[length],al
lngset_ret:
	ret

lng2:	push	dx
	add	bx,bx
	mov	dx,bx
	add	bx,bx
	add	bx,bx
	add	bx,dx	;bx=bx*10
	pop	dx

	add	bl,al
	adc	bh,0	;bx=bx+al

	jmp	lng1

;	16進の場合
lgs01:	inc	si
	call	hexget8
	mov	bl,al
	jc	lgs03
	jmp	lnexit

hexget8:
	lodsb
	call	hexcal8
	jc	hexget8_ret	;ERROR RETURN
	mov	bl,al
	lodsb
	call	hexcal8
	jnc	hg800
	dec	si
	mov	al,bl
	clc
hexget8_ret:
	ret

hg800:	add	bl,bl
	add	bl,bl
	add	bl,bl
	add	bl,bl	;bl=bl*16
	add	al,bl	;al=bl+al
	clc
	ret

hexcal8:
	cmp	al,"a"
	jc	hc801
	sub	al,"a"-"A"	;小文字は大文字に変換

hc801:	sub	al,"0"
	jc	herr8
	cmp	al,10
	jc	hc800
	sub	al,"A"-"9"-1
	cmp	al,10
	jc	herr8
hc800:	cmp	al,16
	jnc	herr8
	clc
	ret
	
herr8:	stc
	ret

;==============================================================================
;	符点(.)があるかを見て、あれば[length]を1.5倍する。
;	符点が２個以上あっても可
;		output	al/bl/[length]
;==============================================================================
futen:	mov	al,[length]
	xor	ah,ah
	mov	bx,ax
ftloop:	cmp	byte ptr [si],"."
	jnz	ft0
	shr	bx,1	;bx=bx/2
	mov	dx,"."*256+21
	jc	error
	add	ax,bx
	inc	si
	jmp	ftloop
ft0:	or	ah,ah
	jnz	ft1	;音長 255 OVER
	mov	bx,ax
	mov	[length],al
	ret
ft1:
	mov	[prsok],0	;圧縮不可にする
	cmp	[ge_delay],0
	mov	dx,"."*256+20
	jnz	error		;Wコマンド使用中はError
	cmp	[ss_length],0
	jnz	error		;Sコマンド使用中もError
	mov	word ptr es:[di],0fbh*256+255	;音長255＋タイを設定
	inc	di
	inc	di
	mov	bl,es:-3[di]
	mov	es:[di],bl	;音符
	inc	di
	sub	ax,255
	jmp	ft0

;==============================================================================
;	0 ～ 9 の数値を得る
;		inputs	-- ds:si to mml pointer
;		outputs	-- al
;			-- cy [1=error]
;==============================================================================
numget:	lodsb
	sub	al,"0"
	jc	nmerr
	cmp	al,10
	jnc	nmerr
	clc
	ret
nmerr:	dec	si
	stc
	ret

;==============================================================================
;	COMMAND "o" オクターブの設定
;==============================================================================
octset:
	call	lngset
	mov	dl,6
	jc	error
	dec	al
octs0:	
	cmp	al,8
	mov	dl,26
	jnc	error
	mov	[octarb],al
	jmp	olc03

;==============================================================================
;	COMMAND ">","<" オクターブup/down
;==============================================================================
octup:
	mov	al,[octarb]
	inc	al
	jmp	octs0
octdown:
	mov	al,[octarb]
	dec	al
	jmp	octs0

;==============================================================================
;	COMMAND	"l" デフォルト音長の設定
;==============================================================================
lengthset:
	call	lngset2
	mov	[deflng],al
	jmp	olc03

;==============================================================================
;	COMMAND "C" 全音符の長さを設定
;==============================================================================
zenlenset:
	call	lngset
	mov	[zenlen],al
	jmp	syousetu_lng_set_2

;==============================================================================
;	音長から具体的な長さを得る
;		INPUTS	-- [length] to 音長
;			-- [zenlen] to 全音符の長さ
;		OUTPUTS	-- al,[length]
;==============================================================================
lngcal:	mov	al,[length]
	or	al,al
	mov	dx,21
	jz	error		;LENGTH=0 ... ERROR
	cmp	[calflg],0
	jz	lcl001
	ret

lcl001:	mov	al,[zenlen]
	xor	ah,ah
	div	[length]
	or	ah,ah
	mov	dx,21
	jnz	error		;音長が全音符の公約数でない
	mov	[length],al
	ret

;==============================================================================
;	2byte [dh/dl] の dataをセットして戻る
;==============================================================================
parset:	xchg	dh,dl
	mov	es:[di],dx
	inc	di
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "t" / "T" テンポ／TimerBセット
;==============================================================================
tempoa:	call	lngset
	cmp	al,18
	mov	dx,"t"*256+2
	jc	error
	call	timerb_get
	mov	al,dl
	jmp	tset

;==============================================================================
;	"T" Command Entry
;==============================================================================

tempob: call	lngset
tset:
if	efc
	mov	dx,"t"*256+12
	jmp	error	;効果音emlにはテンポは指定出来ない
else
	mov	[tempo],al
	mov	dh,0fch
	mov	dl,al
	jmp	parset
endif

;==============================================================================
;	タイマＢの数値 を 計算
;		INPUTS --  AL = TEMPO
;		OUTPUTS -- DL = タイマＢの数値
;
;	DL = 256 - [ 112CH / TEMPO ]
;==============================================================================
timerb_get:
	mov	bl,al
	mov	ax,112ch
	div	bl
	xor	dl,dl
	sub	dl,al
	ret

;==============================================================================
;	COMMAND	"q" step-gate time change
;==============================================================================
qset:	call	lngset
	mov	dl,al
	mov	dh,0feh
	jmp	parset

;==============================================================================
;	COMMAND	"Q" step-gate time change 2
;==============================================================================
qset2:	cmp	byte ptr [si],"%"
	jz	qset3
	call	lngset
	cmp	al,9
	mov	dx,"Q"*256+2
	jnc	error
	add	al,al
	jz	q2_not_inc
	add	al,al
	add	al,al
	add	al,al
	add	al,al		;x32
	dec	al
q2_not_inc:
	not	al
	mov	dl,al
	mov	dh,0c4h
	jmp	parset

;==============================================================================
;	COMMAND	"Q%" step-gate time change 2
;==============================================================================
qset3:
	inc	si
	call	lngset
	not	al
	mov	dl,al
	mov	dh,0c4h
	jmp	parset

;==============================================================================
;	COMMAND	"v"/"V" volume_set
;==============================================================================
vseta:	mov	al,[si]
	cmp	al,"+"
	jz	vss
	cmp	al,"-"
	jz	vss
	call	lngset
	cmp	bl,17
	mov	dx,"v"*256+2
	jnc	error

ife	efc
	cmp	[part],pcmpart
	jz	vsetm
	cmp	[ongen],psg
	jnc	vset
endif
	xor	bh,bh
	add	bx,offset fmvol
	mov	bl,[bx]

vset:	mov	dl,bl
vset2:	mov	dh,0fdh
	mov	al,[volss]
	add	al,dl
	cmp	al,80h
	jc	vset4
	cmp	al,0c0h
	jc	vset3
	xor	al,al
	jmp	vset4
vset3:	
ife	efc
	cmp	[ongen],psg
	jc	vset3f
	mov	al,15
	jmp	vset4
endif
vset3f:	mov	al,7fh
vset4:	mov	dl,al
	mov	[nowvol],al
	jmp	parset

;==============================================================================
;	command "V" entry
;==============================================================================
vsetb:	call	lngset
ife	efc
	cmp	[part],pcmpart
	jz	vsetm1
endif
	jmp	vset

;==============================================================================
;	PCM volset patch
;==============================================================================
ife	efc
vsetm:	cmp	[pcm_vol_ext],1
	jz	vsetma
	add	bl,bl
	add	bl,bl
	add	bl,bl
	add	bl,bl
	jnc	vsetm1
	mov	bl,255
	jmp	vsetm1
vsetma:	mov	al,bl
	mul	bl
	cmp	ax,256
	jc	vsetmb
	mov	al,255
vsetmb:	mov	bl,al
vsetm1:	mov	dh,0fdh
	mov	dl,bl
	mov	al,[volss]
	test	al,80h
	jz	vsetm0
	add	dl,al
	jc	vset4m
	xor	dl,dl
	jmp	vset4m
vsetm0:	add	dl,al
	jnc	vset4m
	mov	dl,255
vset4m:	mov	al,dl
	jmp	vset4

endif
;==============================================================================
;	command "v+"/"v-" entry
;==============================================================================
vss:	call	getnum
	mov	[volss],dl
	mov	dl,[nowvol]
ife	efc
	cmp	[part],pcmpart
	jz	vsetm1
endif
	jmp	vset2

;==============================================================================
;	command	"@"	音色の変更
;==============================================================================
neirochg:
	call	lngset
	cmp	[prg_flg],0
	jz	not_sp
	call	set_prg
not_sp:
ife	efc
	cmp	[part],rhythm
	jz	rhyprg
	cmp	[ongen],psg
	jz	psgprg
endif
	mov	dl,bl
	mov	dh,0ffh
	inc	bl
	cmp	[maxprg],bl
	jnc	nc00
	mov	[maxprg],bl

if	efc

nc00:	jmp	parset

else

nc00:	cmp	[part],pcmpart
	jz	repeat_check
	cmp	[part],rhythm2
	jnz	parset
	cmp	[skip_flag],0
	jnz	olc0
	mov	es:[di],dl
	inc	di
	mov	[length_check1],1	;音長データがあったよ
	mov	[length_check2],1
	jmp	olc0

rhyprg:	cmp	bx,4000h
	mov	dx,"@"*256+2
	jnc	error
	or	bh,10000000b
	mov	[lastprg],bx
	jmp	olc03

psgprg:
	add	bl,bl
	add	bl,bl
	xor	bh,bh
	add	bx,offset psgenvdat
	mov	byte ptr es:[di],0f0h
	inc	di
	mov	cx,4
pplop0:	mov	al,[bx]
	inc	bx
	mov	es:[di],al
	inc	di
	loop	pplop0
	jmp	olc0

repeat_check:
	cmp	byte ptr [si],","
	jnz	parset

	mov	ax,dx
	xchg	ah,al
	stosw
	inc	si
	call	getnum
	mov	al,0ceh
	stosb
	mov	ax,bx
	stosw
	cmp	byte ptr [si],","
	jnz	noset_stop
	inc	si
	call	getnum
	mov	ax,bx
	stosw
	cmp	byte ptr [si],","
	jnz	noset_release
	inc	si
	call	getnum
	mov	ax,bx
	stosw
	jmp	olc0

noset_stop:
	xor	ax,ax
	stosw
noset_release:
	mov	ax,8000h
	stosw
	jmp	olc0

endif
;==============================================================================
;	Ｖ２．６用 / ＦＭ音源の音色使用フラグセット
;==============================================================================
set_prg:
ife	efc
	cmp	[ongen],psg
	jnc	set_prg_ret
endif
	push	bx
	xor	bh,bh
	add	bx,offset prg_num
	mov	byte ptr [bx],1
	pop	bx
set_prg_ret:
	ret
;==============================================================================
;	COMMAND "&"	タイ／スラー
;==============================================================================
tieset:
	cmp	[part],rhythm
	mov	dx,"&"*256+32
	jz	error			;Rパートでは使用不可

	cmp	[skip_flag],0
	jnz	tie_skip
	call	lngset2
	jc	tie_norm
	call	lngcal
	call	futen
	cmp	[prsok],1
	mov	dx,"&"*256+22
	jnz	error
	mov	ah,es:-1[di]
	add	ah,al
	jc	tie_lng_over
	mov	es:-1[di],ah
	jmp	olc03
tie_lng_over:
	mov	byte ptr es:[di],0fbh
	mov	ah,es:-2[di]
	inc	di
	mov	es:[di],ah
	inc	di
	stosb
	jmp	olc03
tie_norm:
	mov	byte ptr es:[di],0fbh
	inc	di
	mov	[tie_flag],1
	cmp	[prsok],1
	jz	olc03
	jmp	olc0
tie_skip:
	call	lngset2
	call	lngcal
	call	futen
	jmp	olc03

;==============================================================================
;	COMMAND "D"	デチューンの設定
;==============================================================================
detset:
	cmp	byte ptr [si],"D"
	jz	detset_2
	cmp	byte ptr [si],"X"
	jz	extdet_set
	call	getnum

	mov	[detune],bx
	cmp	[bend],0
	jnz	olc03
	mov	al,0fah
	stosb
	mov	es:[di],bx
	inc	di
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "DD"	相対デチューンの設定
;==============================================================================
detset_2:
	inc	si
	call	getnum

	mov	byte ptr es:[di],0d5h
	inc	di
	mov	es:[di],bx
	inc	di
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "DX"	拡張デチューン指定
;==============================================================================
extdet_set:
	inc	si
	mov	al,0cch
	stosb
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	符号付き数値を読む
;		OUTPUTS -- bx[word],dl[byte]
;==============================================================================
getnum:	cmp	byte ptr [si],"+"
	jz	plusa
	cmp	byte ptr [si],"-"
	jnz	plusb
	; -
	mov	dh,1
	inc	si
	jmp	gn0	
plusa:	; +
	inc	si
plusb:	; 符号無し(+)
	xor	dh,dh

gn0:	push	dx
	call	lngset
	pop	dx
	mov	dl,bl
	or	dh,dh
	jz	getnum_ret
	
;	dlとbxの符号を反転
	neg	bx
	neg	dl
getnum_ret:
	ret

;==============================================================================
;	COMMAND "[" [LOOP START]
;==============================================================================
stloop:
	mov	byte ptr es:[di],0f9h
	inc	di
	mov	al,[lopcnt]
	inc	[lopcnt]

	xor	ah,ah
	add	ax,ax
	mov	bx,offset loptbl
	add	bx,ax	;bxにloptblをセット

	; dxに、di - mbufを入れる
	mov	dx,di
	sub	dx,offset m_buf

	; 現在のdi - mbufをloptblに書く
	mov	[bx],dx

	;lextblに 0を書いておく
	add	bx,loopnest*2
	mov	word ptr [bx],0

	;2byte 開けておく
	inc	di
	inc	di

	mov	[length_check2],0	;[]0発見対策

	jmp	olc0

;==============================================================================
;	COMMAND "]" [LOOP END]
;==============================================================================
edloop:
	mov	byte ptr es:[di],0f8h
	inc	di
	call	lngset2
	jnc	edl00
	mov	bl,[loop_def]

;	繰り返し回数セット
edl00:
	mov	es:[di],bl
	inc	di
	or	bl,bl
	jnz	edl_nonmuloop
	cmp	[length_check2],0
	mov	dx,"["*256+24
	jz	error

edl_nonmuloop:
;	ひとつ開ける（ドライバーで使用する）
	mov	byte ptr es:[di],0
	inc	di

	dec	[lopcnt]
	mov	al,[lopcnt]
	cmp	al,-1
	mov	dx,"]"*256+23
	jz	error

	xor	ah,ah
	add	ax,ax
	mov	bx,offset loptbl
	add	bx,ax

;	loptblに書いておいた値をセット
	mov	dx,[bx]
	mov	es:[di],dx

;==============================================================================
;	"[" のあった所に今のアドレスを書く
;==============================================================================
	push	bx

	add	dx,offset m_buf	;dx=[ commandで２つ開けておいたアドレス

	mov	bx,di
	dec	bx
	dec	bx		;bx=繰り返し回数がセットされているアドレス
	sub	bx,offset m_buf
	xchg	dx,bx

	mov	es:[bx],dx

	pop	bx

;==============================================================================
;	":" があった時にはそこにも書く
;==============================================================================
	add	bx,loopnest*2	;bx＝lextblの位置

	mov	bx,[bx]		;bx＝lextblの値
	or	bx,bx
	jz	nonexit		;":"はない
	mov	es:[bx],dx	;そこにもdxを書く

	; DETUNE CANCEL (Bend On / ":"のあった時のみ)
	cmp	[bend],0
	jz	nonexit
	mov	word ptr [alldet],8000h

nonexit:
	inc	di
	inc	di

	jmp	olc0

;==============================================================================
;	COMMAND ":"	ループから脱出
;==============================================================================
extloop:
	mov	byte ptr es:[di],0f7h
	inc	di
	mov	al,[lopcnt]
	dec	al
	cmp	al,-1
	mov	dx,":"*256+23
	jz	error

	xor	ah,ah
	add	ax,ax
	mov	bx,offset lextbl
	add	bx,ax
	mov	dx,[bx]
	or	dx,dx
	mov	dx,":"*256+25
	jnz	error		;":"が２つ以上あった

	mov	[bx],di		;lextblに開けておくアドレスをセット
	inc	di
	inc	di		;２つ、開けておく

	jmp	olc0

;==============================================================================
;	COMMAND "L" [LOOP SET]
;==============================================================================
lopset:
	mov	byte ptr es:[di],0f6h
	inc	di
	mov	[allloop_flag],1
	mov	[length_check1],0
	jmp	olc0

;==============================================================================
;	COMMAND	"_" [転調] , "__" [相対転調]
;==============================================================================
oshift:
	cmp	byte ptr [si],"_"
	jnz	osf00
	inc	si
	call	getnum
	mov	dh,0e7h
	jmp	parset
osf00:
	call	getnum
	mov	dh,0f5h
	jmp	parset

;==============================================================================
;	COMMAND ")"	volume up
;==============================================================================
volup:
	cmp	byte ptr [si],"%"
	jz	volup3
	cmp	byte ptr [si],"^"
	jz	volup4
	call	lngset
	cmp	al,1
	jnz	volup2
	mov	byte ptr es:[di],0f4h
	inc	di
	jmp	olc0
volup2:
	mov	byte ptr es:[di],0e3h
	inc	di
	call	ongen_sel_vol
	stosb
	jmp	olc0
volup3:
	inc	si
	call	lngset
	mov	byte ptr es:[di],0e3h
	inc	di
	stosb
	jmp	olc0
volup4:
	inc	si
	cmp	byte ptr [si],"%"
	jz	volup5
	call	lngset
	call	ongen_sel_vol
	mov	byte ptr es:[di],0deh
	inc	di
	stosb
	jmp	olc0
volup5:
	inc	si
	call	lngset
	mov	byte ptr es:[di],0deh
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "("	volume down
;==============================================================================
voldown:
	cmp	byte ptr [si],"%"
	jz	voldown3
	cmp	byte ptr [si],"^"
	jz	voldown4
	call	lngset
	cmp	al,1
	jnz	voldown2
	mov	byte ptr es:[di],0f3h
	inc	di
	jmp	olc0
voldown2:
	mov	byte ptr es:[di],0e2h
	inc	di
	call	ongen_sel_vol
	stosb
	jmp	olc0
voldown3:
	inc	si
	call	lngset
	mov	byte ptr es:[di],0e2h
	inc	di
	stosb
	jmp	olc0
voldown4:
	inc	si
	cmp	byte ptr [si],"%"
	jz	voldown5
	call	lngset
	mov	byte ptr es:[di],0ddh
	inc	di
	call	ongen_sel_vol
	stosb
	jmp	olc0
voldown5:
	inc	si
	call	lngset
	mov	byte ptr es:[di],0ddh
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "M"	lfo set
;==============================================================================
lfoset:
	cmp	byte ptr [si],"X"
	jz	extlfo_set
	cmp	byte ptr [si],"P"
	jz	portaset
	cmp	byte ptr [si],"D"
	jz	depthset
	cmp	byte ptr [si],"W"
	jz	waveset
	cmp	byte ptr [si],"M"
	jz	lfomask_set
	mov	byte ptr es:[di],0f2h
	inc	di
	mov	cx,3
ls0:
	call	getnum
	mov	es:[di],dl
	inc	di
	lodsb
	cmp	al,","
	mov	dx,"M"*256+6
	jnz	error
	loop	ls0

	call	getnum
	mov	es:[di],dl
	inc	di

	jmp	olc0

;==============================================================================
;	COMMAND "MX" LFO Speed Extended Mode Set Ver.4.0m～
;==============================================================================
extlfo_set:
	inc	si
	mov	al,0cah
	stosb
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "MD" [DEPTH SET] for PMD V3.3-
;	MDa,b
;==============================================================================
depthset:
	inc	si
	mov	byte ptr es:[di],0d6h
	inc	di
	call	getnum
	mov	byte ptr es:[di],dl
	inc	di
	cmp	byte ptr [si],","
	mov	dx,"M"*256+6
	jnz	error
	inc	si
	call	getnum
	mov	byte ptr es:[di],dl
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "MP" [PORTAMENT SET] for PMD V2.3-
;	MPa[,b][,c] = Mb,c,a,255*1 def.b=0,c=1
;==============================================================================
portaset:
	inc	si
	mov	[bend2],0
	mov	[bend3],1
	mov	byte ptr es:[di],0f2h
	inc	di
	call	getnum
	mov	[bend1],dl
	cmp	byte ptr [si],","
	jnz	bset
	inc	si
	call	getnum
	mov	[bend2],dl
	cmp	byte ptr [si],","
	jnz	bset
	inc	si
	call	getnum
	mov	[bend3],dl
bset:
	mov	al,[bend2]
	stosb
	mov	al,[bend3]
	stosb
	mov	al,[bend1]
	stosb
	mov	al,255
	stosb
	mov	dh,0f1h
	mov	dl,1
	jmp	parset

;==============================================================================
;	COMMAND "MW" [WAVE SET] for PMD V4.0j～
;==============================================================================
waveset:
	inc	si
	call	getnum
	mov	dh,0cbh
	jmp	parset

;==============================================================================
;	COMMAND "MM"	LFO Mask for PMD v4.2～
;==============================================================================
lfomask_set:
	inc	si
	call	getnum
	mov	dh,0c5h
	jmp	parset

;==============================================================================
;	COMMAND "*"	lfo switch
;==============================================================================
lfoswitch:
	call	lngset
	mov	dx,"*"*256+6
	jc	error
	mov	dh,0f1h
	mov	dl,al
	jmp	parset

;==============================================================================
;	COMMAND "E"	PSG Software_envelope
;==============================================================================
psgenvset:
	cmp	byte ptr [si],"X"
	jz	extenv_set
	mov	byte ptr es:[di],0f0h
	inc	di
	mov	cx,3
pe0:
	call	getnum
	mov	es:[di],dl
	inc	di
	lodsb
	cmp	al,","
	mov	dx,"E"*256+6
	jnz	error
	loop	pe0

	call	getnum
	mov	es:[di],dl
	inc	di

	cmp	byte ptr [si],","
	jz	extend_psgenv

	jmp	olc0

;	4.0h Extended
extend_psgenv:
	mov	byte ptr es:-5[di],0cdh
	inc	si
	call	getnum
	and	byte ptr es:-1[di],0fh
	rol	dl,1
	rol	dl,1
	rol	dl,1
	rol	dl,1
	and	dl,0f0h
	or	es:-1[di],dl

	xor	dl,dl
	cmp	byte ptr [si],","
	jnz	not_set_al
	inc	si
	call	getnum
not_set_al:
	mov	es:[di],dl
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "EX"	Envelope Speed Extended Mode Set
;==============================================================================
extenv_set:
	inc	si
	mov	al,0c9h
	stosb
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "y"	OPN Register set
;==============================================================================
ycommand:
	mov	byte ptr es:[di],0efh
	inc	di

	call	lngset
	mov	es:[di],bl
	inc	di
	lodsb
	cmp	al,","
	mov	dx,"y"*256+6
	jnz	error
	call	lngset
	mov	es:[di],bl
	inc	di

	jmp	olc0

;==============================================================================
;	COMMAND "w"	PSG noise 平均周波数設定
;==============================================================================
psgnoise:
	cmp	byte ptr [si],"+"
	jz	psgnoise_move
	cmp	byte ptr [si],"-"
	jz	psgnoise_move

	mov	byte ptr es:[di],0eeh
	inc	di

	call	lngset
	mov	es:[di],bl
	inc	di
	jmp	olc0

psgnoise_move:
	mov	byte ptr es:[di],0d0h
	inc	di
	call	getnum
	mov	es:[di],dl
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "P"	PSG tone/noise/mix Select
;==============================================================================
psgpat:
	mov	byte ptr es:[di],0edh
	inc	di

	call	lngset
	mov	dx,"P"*256+6
	jc	error
	cmp	al,4
	mov	dl,2
	jnc	error

	mov	ah,al
	and	ah,2
	and	al,1
	rol	ah,1
	rol	ah,1
	or	al,ah

	mov	ah,al
	rol	al,1
	or	al,ah
	mov	ah,al
	rol	al,1
	or	al,ah

	mov	es:[di],al
	inc	di

	jmp	olc0

;==============================================================================
;	COMMAND "B"	ベンド幅の設定
;==============================================================================
bendset:
	call	getnum

	cmp	dl,13
	push	dx
	mov	dx,"B"*256+2
	jnc	error
	pop	dx
	mov	[bend],dl
	or	dl,dl
	jnz	olc03
	mov	[alldet],8000h	;０が指定されたらalldet値を初期化
	jmp	olc03

;==============================================================================
;	COMMAND "I"	ピッチの設定
;==============================================================================
pitchset:
	call	getnum
	mov	[pitch],bx
	jmp	olc03

;==============================================================================
;	COMMAND	"p"	パンの設定
;==============================================================================
panset:
	cmp	byte ptr [si],"x"
	jz	panset_extend
	call	getnum
	mov	byte ptr es:[di],0ech
	inc	di
	mov	es:[di],dl
	inc	di
	jmp	olc0
panset_extend:
	inc	si
	call	getnum
	mov	byte ptr es:[di],0c3h
	inc	di
	mov	es:[di],dl
	inc	di
	mov	byte ptr es:[di],0
	inc	di
	cmp	byte ptr [si],","
	jnz	olc0
	inc	si
	call	getnum
	or	dl,dl
	jz	olc0
	mov	byte ptr es:-1[di],01h
	jmp	olc0

;==============================================================================
;	COMMAND "\"	リズム音源コントロール
;==============================================================================
rhycom:	
	lodsb
	mov	bx,offset rcomtbl
rc00:	cmp	byte ptr cs:[bx],0
	mov	dx,"\"*256+1
	jz	error
	cmp	al,cs:[bx]
	jz	rc01
	add	bx,3
	jmp	rc00
rc01:	inc	bx
	mov	ax,cs:[bx]
	call	ax
	jmp	olc0

rcomtbl:db	"V"
	dw	mstvol
	db	"v"
	dw	rthvol
	db	"l"
	dw	panlef
	db	"m"
	dw	panmid
	db	"r"
	dw	panrig
	db	"b"
	dw	bdset
	db	"s"
	dw	snrset
	db	"c"
	dw	cymset
	db	"h"
	dw	hihset
	db	"t"
	dw	tamset
	db	"i"
	dw	rimset
	db	0
mstvol:
	cmp	byte ptr [si],"+"
	jz	mstvol_sft
	cmp	byte ptr [si],"-"
	jz	mstvol_sft
	mov	byte ptr es:[di],0e8h
	inc	di
	call	lngset
	mov	es:[di],bl
	inc	di
	ret
mstvol_sft:
	call	getnum
	mov	byte ptr es:[di],0e6h
	inc	di
	mov	es:[di],dl
	inc	di
	ret
rthvol:
	call	rhysel
	push	ax
	cmp	byte ptr [si],"+"
	jz	rhyvol_sft
	cmp	byte ptr [si],"-"
	jz	rhyvol_sft
	call	lngset
	pop	ax
	mov	byte ptr es:[di],0eah
	inc	di
rc02:	and	al,11100000b
	and	bl,00011111b
	or	al,bl
	mov	es:[di],al
	inc	di
	ret
rhyvol_sft:
	pop	ax
	mov	byte ptr es:[di],0e5h
	inc	di
	and	al,11100000b
	rol	al,1
	rol	al,1
	rol	al,1
	mov	es:[di],al
	inc	di
	call	getnum
	mov	es:[di],dl
	inc	di
	ret
panlef:
	mov	bl,2
	jmp	rpanset
panmid:
	mov	bl,3
	jmp	rpanset
panrig:
	mov	bl,1
rpanset:
	mov	byte ptr es:[di],0e9h
	inc	di
	call	rhysel
	jmp	rc02
rhysel:
	lodsb
	mov	bh,1
	cmp	al,"b"
	jz	rsel
	inc	bh
	cmp	al,"s"
	jz	rsel
	inc	bh
	cmp	al,"c"
	jz	rsel
	inc	bh
	cmp	al,"h"
	jz	rsel
	inc	bh
	cmp	al,"t"
	jz	rsel
	inc	bh
	cmp	al,"i"
	jz	rsel
	mov	dx,"\"*256+1
	jmp	error
rsel:
	mov	al,bh
	ror	al,1
	ror	al,1
	ror	al,1
	ret
bdset:
	mov	al,1
	jmp	rs00
snrset:
	mov	al,2
	jmp	rs00
cymset:
	mov	al,4
	jmp	rs00
hihset:
	mov	al,8
	jmp	rs00
tamset:	
	mov	al,16
	jmp	rs00
rimset:
	mov	al,32
rs00:
	cmp	byte ptr [si],"p"
	jnz	rs01
	inc	si
	or	al,80h
	jmp	rs02
rs01:
	cmp	byte ptr es:-2[di],0ebh
	jnz	rs02
	test	byte ptr es:-1[di],80h
	jnz	rs02
	cmp	[prsok],2
	jnz	rs02
	or	al,es:-1[di]
	mov	es:-1[di],al
	jmp	rsexit
rs02:
	mov	byte ptr es:[di],0ebh
	mov	es:1[di],al
	inc	di
	inc	di
	test	al,80h
	jz	rsexit
	ret
rsexit:
	pop	cx
	mov	al,2
	jmp	olc02

;==============================================================================
;	MML 変数の使用
;==============================================================================
hscom:
	call	lngset2
	jnc	hscom2

	lodsb
	sub	al,64
	mov	dx,"!"*256+7
	jc	error
	cmp	al,64
	jnc	error

	xor	ah,ah
	add	ax,ax
	mov	bx,offset hsbuf
	add	bx,ax
	jmp	hscom3

hscom2:
	xor	ah,ah
	add	ax,ax
	mov	bx,offset hsbuf2
	add	bx,ax

hscom3:
	cmp	word ptr [bx],0
	mov	dx,"!"*256+27
	jz	error		;定義されてないってばさ

	push	si

	inc	[hsflag]
	mov	si,[bx]
	call	olc0
	dec	[hsflag]

	pop	si
	jmp	olc03

;==============================================================================
;	ERRORの表示
;		input	dl		ERROR_NUMBER
;			dh		ERROR Command	0なら不定
;			si		ERROR address	0なら不定
;			[part]		part番号	0なら不定
;==============================================================================
error:
	mov	ax,mml_seg
	mov	ds,ax
	mov	es,ax
	assume	ds:mml_seg,es:mml_seg
	push	dx
	call	calc_line
	pop	dx

;------------------------------------------------------------------------------
;	filename,lineの表示
;------------------------------------------------------------------------------
	or	si,si
	jz	non_line

	push	dx
	push	si
	mov	bx,offset mml_filename
	print_line
	print_chr	"("
	mov	ax,[line]
	call	print_16
	print_chr	")"
	print_chr	" "
	print_chr	":"
	pop	si
	pop	dx
non_line:
;------------------------------------------------------------------------------
;	Error番号の表示
;------------------------------------------------------------------------------
	push	ds
	push	si
	push	dx
	mov	ax,err_seg
	mov	ds,ax
	assume	ds:err_seg
	print_mes	errmes_1
	pop	dx
	push	dx
	mov	al,dl
	call	print_8
	pop	dx
	pop	si
	pop	ds
	assume	ds:mml_seg

;------------------------------------------------------------------------------
;	Partの表示
;------------------------------------------------------------------------------
	cmp	[part],0
	jz	non_part
	push	ds
	push	si
	push	dx
	mov	ax,err_seg
	mov	ds,ax
	assume	ds:err_seg
	print_mes	errmes_2
	mov	dl,[part]
	add	dl,"A"-1
	mov	ah,2
	int	21h	;１文字表示
	cmp	[hsflag],0
	jz	non_macro
	cmp	[part],rhythm
	jnz	errmes5_put
	cmp	[hsflag],1
	jz	non_macro
errmes5_put:
	print_mes	errmes_5
non_macro:
	pop	dx
	pop	si
	pop	ds
	assume	ds:mml_seg


non_part:

;------------------------------------------------------------------------------
;	Commandの表示
;------------------------------------------------------------------------------
	or	dh,dh
	jz	non_command
	push	ds
	push	si
	push	dx
	mov	ax,err_seg
	mov	ds,ax
	assume	ds:err_seg
	print_mes	errmes_3
	pop	dx
	push	dx
	mov	dl,dh
	mov	ah,2
	int	21h	;１文字表示
	pop	dx
	pop	si
	pop	ds
	assume	ds:mml_seg
non_command:

;------------------------------------------------------------------------------
;	Error Messageの表示
;------------------------------------------------------------------------------
	push	ds
	mov	ax,err_seg
	mov	ds,ax
	assume	ds:err_seg
	push	si
	push	dx
	print_mes	errmes_4
	pop	bx
	xor	bh,bh
	add	bx,bx
	add	bx,offset err_table
	mov	dx,ds:[bx]
	mov	ah,09h
	int	21h	;文字列表示
	pop	si
	pop	ds
	assume	ds:mml_seg

;------------------------------------------------------------------------------
;	エラー箇所の表示
;------------------------------------------------------------------------------
	or	si,si
	jz	non_lineput
	cmp	[line],0
	jz	non_lineput
	mov	di,[linehead]
	cmp	byte ptr [di],9
	jz	lineput
	cmp	byte ptr [di]," "
	jc	non_lineput
lineput:
	mov	al,cr
	mov	cx,1024
repnz	scasb
	jnz	err_non_crlf
	inc	di
	jmp	put_errline
err_non_crlf:
	mov	di,[linehead]
	mov	al,01ah	;EOF
	mov	cx,1024
repnz	scasb
	jnz	non_lineput
	dec	di
put_errline:
	mov	byte ptr [di],0
	push	si
	mov	bx,[linehead]
	print_line
	pop	si
	mov	word ptr [si],"$^"
	cmp	byte ptr -1[si]," "
	jc	nullset_loop
	mov	byte ptr -1[si],"^"
	dec	si
nullset_loop:
	cmp	si,[linehead]
	jz	put_errpoint
	dec	si
	cmp	byte ptr [si]," "+1
	jc	nullset_loop
	mov	byte ptr [si]," "
	jmp	nullset_loop
put_errpoint:
	mov	dx,[linehead]
	mov	ah,09h
	int	21h	;文字列表示
	mov	ax,err_seg
	mov	ds,ax
	assume	ds:err_seg
	print_mes	crlf_mes

non_lineput:
	error_exit	1

;==============================================================================
;	Error位置のline,lineheadを計算
;		input	DS:SI		Error位置
;		output	[line]		Line
;			[linehead]	Lineの頭位置
;			[mml_filename]	MMLのファイル名
;==============================================================================
calc_line:
	or	si,si
	jz	cl_err_exit
	xor	ah,ah	;Main/Include Flag
	mov	dx,si	;DX=Error位置
	mov	si,offset mml_buf
	mov	[line],1
	mov	[sp_push],sp	;SPを保存
cl_loop0:
	mov	[linehead],si
	cmp	si,dx	;１文字目でerrorの場合
	jz	cl_exit
cl_loop1:
	lodsb
	cmp	si,dx	;Error位置まで来たか？
	jz	cl_exit
	cmp	al,1ah		;EOF
	jz	cl_err_exit
	jnc	cl_loop1
	cmp	al,13		;CR
	jz	cl_line_inc
	cmp	al,1		;Main->Include check code
	jz	cl_inc_inc
	cmp	al,2		;Include->Main check code
	jz	cl_inc_dec
	jmp	cl_loop1
cl_line_inc:
	inc	si	;LFを飛ばす
	inc	[line]
	jmp	cl_loop0

cl_inc_inc:
	push	[line]		;Lineを保存
	push	bx		;MMLのファイル名位置を保存
	mov	[line],1	;1行目から
	inc	ah		;Include階層を一つ増やす
	mov	bx,si		;MMLのファイル名位置をBXに保存
clei_loop:
	lodsb
	cmp	al,0ah
	jnz	clei_loop	;ファイル名部分を飛ばす
	jmp	cl_loop0

cl_inc_dec:
	pop	bx		;MMLのファイル名位置を元に戻す
	pop	[line]		;Line位置を元に戻す
	dec	ah		;Include階層を一つ減らす
	inc	si
	jmp	cl_loop0

cl_exit:
	or	ah,ah
	jz	cl_exit2
	mov	sp,[sp_push]	;SPを元に戻す
	mov	si,bx
	mov	di,offset mml_filename
cle_loop:
	movsb			;Include中にError --> MML Filenameを変更
	cmp	byte ptr -1[si],0
	jnz	cle_loop
cl_exit2:
	mov	si,dx		;Error位置をSIに戻す
	ret

cl_err_exit:	;特定出来ないままEOFまで来た
	mov	[line],0
	mov	[linehead],0
	xor	si,si
	ret

;==============================================================================
;	数値の表示 8bit
;		input	AL
;==============================================================================
print_8:
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
; 	usage put & exit
;==============================================================================
usage:
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	print_mes	usames
	error_exit	1

;==============================================================================
; 	command lineのスペースを飛ばす
;
;		in	ds:si = command line point
;==============================================================================
space_cut:
	cmp	byte ptr [si]," "
	jnz	sc_ret
	inc	si
	jmp	space_cut
sc_ret:
	ret

mc	endp

	include	diskpmd.inc
kankyo_seg	dw	?	;環境のセグメント (cs:)

code	ends

err_seg		segment	word	public	'code'

err_table	dw	err00,err01,err02,err03,err04,err05,err06,err07
		dw	err08,err09,err10,err11,err12,err13,err14,err15
		dw	err16,err17,err18,err19,err20,err21,err22,err23
		dw	err24,err25,err26,err27,err28,err29,err30,err31
		dw	err32

errmes_1	db	"Error ",eof
errmes_2	db	": Part ",eof
errmes_3	db	": Command ",eof
errmes_4	db	cr,lf,"---------- ",eof
errmes_5	db	" (Macro)",eof
incfile_mes	db	"Include file:",eof
crlf_mes	db	cr,lf,eof

err00	db	"The option specification is incorrect.",cr,lf,eof
err01	db	"Indefinable token in the MML code.",cr,lf,eof
err02	db	"The specified number is invalid.",cr,lf,eof
err03	db	"The MML file cannot be read.",cr,lf,eof
err04	db	"The M file cannot be written.",cr,lf,eof
err05	db	"The FF file cannot be written.",cr,lf,eof
err06	db	"Insufficient parameter specification.",cr,lf,eof
err07	db	"Invaild token in the MML code.",cr,lf,eof
err08	db	"The specified note length is too long.",cr,lf,eof
err09	db	"The portamento end symbol (}) is missing.",cr,lf,eof
err10	db	"No pitch specification is after the L command.",cr,lf,eof
err11	db	"Hard LFO cannot be used for the sound effect part.",cr,lf,eof
err12	db	"Tempo commands cannot be used with sound effect parts.",cr,lf,eof
err13	db	"The portamento start symbol ({) is missing.",cr,lf,eof
err14	db	"The specification in the portamento command is incorrect.",cr,lf,eof
err15	db	"There is a rest in the portamento command.",cr,lf,eof
err16	db	"A command is specified immediately after the pitch command.",cr,lf,eof
err17	db	"This command cannot be used here.",cr,lf,eof
err18	db	"The MML size is too large.",cr,lf,eof
err19	db	"Compiled size is too large.",cr,lf,eof
err20	db	"When using the W/S command, you cannot specify a duration that exceeds 255 steps.",cr,lf,eof
err21	db	"An unusable length is specified.",cr,lf,eof
err22	db	"The tie is not specified immediately after the pitch command.",cr,lf,eof
err23	db	"Missing loop start symbol [",cr,lf,eof
err24	db	"There is no instruction with a duration in an infinite loop.",cr,lf,eof
err25	db	"There are two or more escape symbols in one loop.",cr,lf,eof
err26	db	"The pitch has exceeded the limit.",cr,lf,eof
err27	db	"The MML variable is not defined.",cr,lf,eof
err28	db	"Specify a tone file or a /V option.",cr,lf,eof
err29	db	"R part is not defined though required.",cr,lf,eof ; as required ?
err30	db	"The tone has not been defined.",cr,lf,eof
err31	db	"The previous note length is compressed or processed.",cr,lf,eof
err32	db	"Tie slurs cannot be used in the R part.",cr,lf,eof

err_seg		ends

fnumdat_seg	segment	para	public	'code'
;	paraなので先頭offsetは必ず 0000
;******* block=3 c ********
	dw      26ah,26bh,26ch,26eh,26fh,270h,271h,272h
	dw      273h,274h,276h,277h,278h,279h,27ah,27bh
	dw      27ch,27eh,27fh,280h,281h,282h,283h,284h
	dw      286h,287h,288h,289h,28ah,28bh,28dh,28eh

;******* block=3 c# ********
	dw      28fh,290h,291h,293h,294h,295h,296h,297h
	dw      299h,29ah,29bh,29ch,29dh,29fh,2a0h,2a1h
	dw      2a2h,2a3h,2a5h,2a6h,2a7h,2a8h,2aah,2abh
	dw      2ach,2adh,2aeh,2b0h,2b1h,2b2h,2b3h,2b5h

;******* block=3 d ********
	dw      2b6h,2b7h,2b8h,2bah,2bbh,2bch,2bdh,2bfh
	dw      2c0h,2c1h,2c3h,2c4h,2c5h,2c6h,2c8h,2c9h
	dw      2cah,2cch,2cdh,2ceh,2cfh,2d1h,2d2h,2d3h
	dw      2d5h,2d6h,2d7h,2d9h,2dah,2dbh,2ddh,2deh

;******* block=3 d# ********
	dw      2dfh,2e1h,2e2h,2e3h,2e5h,2e6h,2e7h,2e9h
	dw      2eah,2ebh,2edh,2eeh,2efh,2f1h,2f2h,2f3h
	dw      2f5h,2f6h,2f8h,2f9h,2fah,2fch,2fdh,2feh
	dw      300h,301h,303h,304h,305h,307h,308h,30ah

;******* block=3 e ********
	dw      30bh,30ch,30eh,30fh,311h,312h,313h,315h
	dw      316h,318h,319h,31bh,31ch,31dh,31fh,320h
	dw      322h,323h,325h,326h,328h,329h,32ah,32ch
	dw      32dh,32fh,330h,332h,333h,335h,336h,338h

;******* block=3 f ********
	dw      339h,33bh,33ch,33eh,33fh,341h,342h,344h
	dw      345h,347h,348h,34ah,34bh,34dh,34fh,350h
	dw      352h,353h,355h,356h,358h,359h,35bh,35ch
	dw      35eh,35fh,361h,363h,364h,366h,367h,369h

;******* block=3 f# ********
	dw      36ah,36ch,36dh,36fh,371h,372h,374h,375h
	dw      377h,379h,37ah,37ch,37dh,37fh,381h,382h
	dw      384h,386h,387h,389h,38ah,38ch,38eh,38fh
	dw      391h,393h,394h,396h,398h,399h,39bh,39dh

;******* block=3 g ********
	dw      39eh,3a0h,3a2h,3a3h,3a5h,3a7h,3a8h,3aah
	dw      3ach,3adh,3afh,3b1h,3b3h,3b4h,3b6h,3b8h
	dw      3b9h,3bbh,3bdh,3bfh,3c0h,3c2h,3c4h,3c6h
	dw      3c7h,3c9h,3cbh,3cdh,3ceh,3d0h,3d2h,3d4h

;******* block=3 g# ********
	dw      3d5h,3d7h,3d9h,3dbh,3dch,3deh,3e0h,3e2h
	dw      3e4h,3e5h,3e7h,3e9h,3ebh,3edh,3efh,3f0h
	dw      3f2h,3f4h,3f6h,3f8h,3f9h,3fbh,3fdh,3ffh
	dw      401h,403h,405h,406h,408h,40ah,40ch,40eh

;******* block=3 a ********
	dw      410h,412h,414h,415h,417h,419h,41bh,41dh
	dw      41fh,421h,423h,425h,427h,428h,42ah,42ch
	dw      42eh,430h,432h,434h,436h,438h,43ah,43ch
	dw      43eh,440h,442h,444h,446h,448h,44ah,44ch

;******* block=3 a# ********
	dw      44eh,450h,452h,454h,456h,458h,45ah,45ch
	dw      45eh,460h,462h,464h,466h,468h,46ah,46ch
	dw      46eh,470h,472h,474h,476h,478h,47ah,47ch
	dw      47eh,480h,483h,485h,487h,489h,48bh,48dh

;******* block=3 b ********
	dw      48fh,491h,493h,495h,498h,49ah,49ch,49eh
	dw      4a0h,4a2h,4a4h,4a6h,4a9h,4abh,4adh,4afh
	dw      4b1h,4b3h,4b6h,4b8h,4bah,4bch,4beh,4c1h
	dw      4c3h,4c5h,4c7h,4c9h,4cch,4ceh,4d0h,4d2h

mml_seg	segment	byte	public

;==============================================================================
;	Work Area
;==============================================================================
warning_mes	db	"Warning ",eof
not_ff_mes	db	": The tone file name is not specified.",cr,lf,eof
ff_readerr_mes	db	": The tone file cannot be read.",cr,lf,eof
not_pmd_mes	db	": PMD is not in residentment.",cr,lf,eof

if	efc
usames		db	"Usage:  EFC [/option] filename[.EML] [filename[.FF]]",cr,lf,cr,lf
		db	"Option: /V  compile with tone datas",cr,lf
		db	"        /VW write Voicefile after compile",cr,lf
		db	"        /N  Compile on OPN Mode",cr,lf
		db	"        /M  Compile on OPM Mode",cr,lf
		db	"        /L  Compile on OPL Mode (Default)",cr,lf,eof

titmes		db	" .EML file --> .EFC file Compiler ver ",ver
		db	cr,lf
		db	"		Programmed by M.Kajihara(KAJA) ",date
		db	cr,lf,cr,lf,eof

else

usames		db	"Usage: MC"
if	hyouka
		db	"H"
endif
		db	" [/option] filename[.MML] [filename[.FF]]",13,10,13,10
		db	"Options:",13,10
ife	hyouka
		db	"        /V  Compile with tone data, messages and filename",cr,lf
		db	"        /VW Write tone data after compilation",cr,lf
		db	"        "
endif
		db	"        /N  		    OPN   Mode",cr,lf
		db	"        /L  		    OPL   Mode (Default)",cr,lf
ife	hyouka
		db	"        /M  			OPM   Mode",cr,lf
		db	"        /T  			TOWNS Mode",cr,lf
		db	"        /P   play after compiling",cr,lf
		db	"        /S  don't write compiled file & play",cr,lf
endif
		db	"        /A  don't set PCMFile before play",cr,lf
		db	"        /O  don't print title messages before playing",cr,lf
		db	eof
		
titmes_cos		equ	" .MML file --> .M file Compiler"
ife	hyouka
titmes		db	titmes_cos
else
titmes		db	titmes_cos," (trial version)"
endif
		db	" ver ",ver,cr,lf
		db	"		Programmed by M.Kajihara(KAJA) ",date
		db	cr,lf,cr,lf,eof
endif

finmes		db	"Compiliation completed."
mes_crlf	db	cr,lf,eof

mes_title	db	cr,lf,"The playback started.",cr,lf,cr,lf
		db	"Title: ",eof
mes_composer	db	"Composer: ",eof
mes_arranger	db	"Arranger: ",eof
mes_memo	db	"        : ",eof

mes_ppsfile	db	"PPSFile  : ",eof
mes_pcmfile	db	"PCMFile  : ",eof

tempo		db	0
octarb		db	4
length		db	0
zenlen		db	96
deflng		db	4
calflg		db	0
hsflag		db	0
lopcnt		db	0
volss		db	0
nowvol		db	0
line		dw	0
linehead	dw	0
length_check1	db	0
length_check2	db	0
allloop_flag	db	0

detune		dw	0
alldet		dw	0
bend		db	0
pitch		dw	0

bend1		db	0
bend2		db	0
bend3		db	0

fmvol		db	127-2ah	;VOLUME	00
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
		db	127-00h	;VOLUME	16

ife	efc

pcm_vol_ext	db	0

;	ＰＳＧ音色のパターン
psgenvdat	db	0,0,0,0		; @0 ﾋｮｳｼﾞｭﾝ 
		db	2,-1,0,1	; @1 Synth 1 
		db	2,-2,0,1	; @2 Synth 2
		db	2,-2,0,8	; @3 Synth 3
		db	2,-1,24,1	; @4 E.Piano 1
		db	2,-2,24,1	; @5 E.Piano 2
		db	2,-2,4,1	; @6 Glocken/Malimba
		db	2,1,0,1		; @7 Strings 
		db	1,2,0,1		; @8 Brass 1
		db	1,2,24,1	; @9 Brass 2

max_part	equ	11
fm		equ	0
fm2		equ	1
psg		equ	2
pcm		equ	3

else

max_part	equ	126

endif

pcmpart		equ	10
rhythm2		equ	11
rhythm		equ	18

part		db	0
ongen		db	0
pass		db	0

maxprg		db	0
kpart_maxprg	db	0
lastprg		dw	0

prsok		db	0

prg_flg		db	0
ff_flg		db	0
x68_flg		db	0
dt2_flg		db	0
opl_flg		db	1
play_flg	db	0
save_flg	db	0
pmd_flg		db	0
ext_detune	db	0
ext_lfo		db	0
ext_env		db	0
memo_flg	db	0
pcm_flg		db	0
loop_def	db	0

sp_push		dw	0

ss_speed	db	0
ss_depth	db	0
ss_length	db	0
ss_tie		db	0

ge_delay	db	0
ge_depth	db	0
ge_depth2	db	0
ge_tie		db	0
ge_flag1	db	0
ge_flag2	db	0

skip_flag	db	0
tie_flag	db	0
porta_flag	db	0

fm3_partchr1	db	0
fm3_partchr2	db	0
fm3_partchr3	db	0
fm3_ofsadr	dw	0

;		offset,max,rot
oplprg_table	label	byte
	db	08,001,0	;alg
	db	08,007,1	;fbl

	db	04,015,4	;ar
	db	04,015,0	;dr
	db	06,015,0	;rr
	db	06,015,4	;sl
	db	02,063,0	;tl
	db	02,003,6	;ksl
	db	00,015,0	;ml
	db	00,001,4	;ksr
	db	00,001,5	;egt
	db	00,001,6	;vib
	db	00,001,7	;am

	db	05,015,4	;ar
	db	05,015,0	;dr
	db	07,015,0	;rr
	db	07,015,4	;sl
	db	03,063,0	;tl
	db	03,003,6	;ksl
	db	01,015,0	;ml
	db	01,001,4	;ksr
	db	01,001,5	;egt
	db	01,001,6	;vib
	db	01,001,7	;am

mml_endadr	dw	?

loopnest	equ	32	; MAX 32 NEST 
loptbl	db	loopnest*2 dup (?)
lextbl	db	loopnest*2 dup (?)

hsbuf	db	2*64 dup (?)
hsbuf2	db	2*256 dup (?)

prgbuf_start	label	byte
prgbuf_length	equ	26
newprg_num	db	?
alg_fb		db	?
slot_1		db	6 dup (?)
slot_2		db	6 dup (?)
slot_3		db	6 dup (?)
slot_4		db	6 dup (?)
prg_name	db	8 dup (?)

oplbuf		db	16 dup(?)

prg_num		db	256 dup (?)

mml_filename	db	128 dup(?)
mml_filename2	db	128 dup(?)		;include用
ppsfile_adr	dw	?
pcmfile_adr	dw	?
title_adr	dw	?
composer_adr	dw	?
arranger_adr	dw	?
memo_adr	dw	128 dup(?)

mml_buf		db	61*1024-1 dup (?)		;max 61k(.mml file)
mmlbuf_end	db	?

mml_seg		ends

m_seg		segment	word	public
m_filename	db	128 dup(?)
file_ext_adr	dw	?
	if	efc+olddat
m_start		label	byte
m_buf		db	63*1024-1 dup (?)		;max 63k(.m file)
mbuf_end	db	?
	else
m_start		db	?
m_buf		db	63*1024-2 dup (?)
mbuf_end	db	?
	endif
m_seg		ends

voice_seg	segment	word	public
v_filename	db	128 dup(?)
voice_buf	db	8192 dup (?)
voice_seg	ends

stack		segment	stack
		db	1024 dup(?)
stack		ends

end	mc

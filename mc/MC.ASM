;==============================================================================
;
;	MML/SFX compiler for PC-9801/88VA English ver.
;							ver 4.8sEn
;
;==============================================================================
;	.186

ver		equ	"4.8sEn"		;version
vers		equ	48h
date		equ	"2020/03/10"	;date

ifndef	hyouka
hyouka		equ	0		; Trial verson (no save feature)
endif
ifndef	efc
efc		equ	0		; FM sfx compiling
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

olddat		equ	0		; format before v2.92
split		equ	0		; inst. in SPLIT formats
tempo_old_flag	equ	0		; old tempo computing
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
	assume	cs:code,ss:stack_seg

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
	mov	[opl_flg],ah
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
	push	es
	push	ds
	push	si
	mov	ax,mml_seg
	mov	ds,ax
	assume	ds:mml_seg
	mov	es,[kankyo_seg]
	mov	si,offset mcopt_txt
	call	search_env
	jc	no_mcopt
	mov	ax,es
	mov	ds,ax
	mov	si,di
	call	get_option
	jnc	no_mcopt
	mov	ax,mml_seg
	mov	ds,ax
	print_mes	warning_mes
	print_mes	mcopt_err_mes
no_mcopt:
	pop	si
	pop	ds
	pop	es
	assume	ds:nothing,es:mml_seg
	call	get_option

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
	jmp	g_mfn_loop
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

	call	read_fffile

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
	push	es
	mov	ax,hs_seg
	mov	es,ax
	assume	es:hs_seg

;;	mov	di,offset hsbuf
;;	mov	cx,+(offset hsbuf_end - offset hsbuf)/2
	mov	di,offset hsbuf2
	mov	cx,+(offset hsbuf_end - offset hsbuf2)/2
	xor	ax,ax
rep	stosw

	pop	es
	assume	es:mml_seg

	mov	di,offset ppzfile_adr
	mov	cx,128+8
rep	stosw

;==============================================================================
;	環境変数 user= , composer= , arranger= を検索して設定
;==============================================================================
	mov	es,[kankyo_seg]
	mov	si,offset user_txt
	call	search_env		;"USER=" 検索
	jc	no_user
	mov	[composer_adr],di
	mov	[arranger_adr],di
	mov	[composer_seg],es
	mov	[arranger_seg],es
no_user:
	mov	si,offset composer_txt
	call	search_env		;"COMPOSER="検索
	jc	no_composer
	mov	[composer_adr],di
	mov	[composer_seg],es
no_composer:
	mov	si,offset arranger_txt
	call	search_env		;"ARRANGER="検索
	jc	no_arranger
	mov	[arranger_adr],di
	mov	[arranger_seg],es
no_arranger:

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

	mov	[skip_flag],0

;==============================================================================
;	Ｍain Ｌoop(pass1)
;==============================================================================

p1cloop:
	mov	[linehead],si
p1c_next:
	lodsb

	call	sjis_check
	jnc	p1c_nosjis
	inc	si
	jmp	p1c_next
p1c_nosjis:

	cmp	al,1ah
	jz	p1_end
	cmp	al," "+1
	jc	p1c_fin
	cmp	al,";"
	jz	p1c_fin

	cmp	al,"`"
	jnz	p1c_no_skip
	xor	[skip_flag],2
	jmp	p1c_next
p1c_no_skip:
	test	[skip_flag],2
	jnz	p1c_next

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

	mov	di,2*(max_part+1)
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
	call	cm_init

ife	efc
	cmp	[part],1
	jnz	not_partA
	cmp	[fm3_partchr1],0
	jz	not_ext_fm3
	mov	al,0c6h	;FM3 拡張パートの指定 (partA)
	stosb
	mov	[fm3_ofsadr],di
	xor	ax,ax
	stosw
	stosw
	stosw
not_ext_fm3:
not_partA:

	cmp	[part],pcmpart
	jnz	not_partJ
	cmp	[pcm_partchr1],0
	jz	not_ext_pcm
	mov	al,0b4h	;PCM 拡張パートの指定 (partJ)
	stosb
	mov	[pcm_ofsadr],di
	xor	ax,ax
	mov	cx,8
rep	stosw
not_ext_pcm:
not_partJ:

	cmp	[part],7
	jnz	not_partG
	cmp	[zenlen],96
	jz	not_zenlen
	mov	ah,[zenlen]
	mov	al,0dfh
	stosw		;#Zenlenが指定されている場合は Zコマンド発行(partG)
not_zenlen:
ife	tempo_old_flag
	cmp	[tempo],0
	jz	not_tempo
	mov	ax,0fffch
	stosw		;#Tempoが指定されている場合は tコマンド発行(partG)
	mov	al,[tempo]
	stosb
not_tempo:
endif
	cmp	[timerb],0
	jz	not_timerb
	mov	ah,[timerb]
	mov	al,0fch
	stosw		;#Timerが指定されている場合は Tコマンド発行(partG)
not_timerb:

	cmp	[towns_flg],1
	jz	not_partG		;TOWNSは4.6f @@@@
	cmp	[fm_voldown],0
	jz	not_vd_fm
	mov	ax,0fec0h
	add	ah,[fm_voldown_flag]
	stosw
	mov	al,[fm_voldown]
	stosb		;#Voldownが指定されている場合は DFコマンド発行(partG)
not_vd_fm:

	cmp	[ssg_voldown],0
	jz	not_vd_ssg
	mov	ax,0fcc0h
	add	ah,[ssg_voldown_flag]
	stosw
	mov	al,[ssg_voldown]
	stosb		;#Voldownが指定されている場合は DSコマンド発行(partG)
not_vd_ssg:

	cmp	[pcm_voldown],0
	jz	not_vd_pcm
	mov	ax,0fac0h
	add	ah,[pcm_voldown_flag]
	stosw
	mov	al,[pcm_voldown]
	stosb		;#Voldownが指定されている場合は DPコマンド発行(partG)
not_vd_pcm:

	cmp	[ppz_voldown],0
	jz	not_vd_ppz
	mov	ax,0f5c0h
	add	ah,[ppz_voldown_flag]
	stosw
	mov	al,[ppz_voldown]
	stosb		;#Voldownが指定されている場合は DZコマンド発行(partG)
not_vd_ppz:

	cmp	[rhythm_voldown],0
	jz	not_vd_rhythm
	mov	ax,0f8c0h
	add	ah,[rhythm_voldown_flag]
	stosw
	mov	al,[rhythm_voldown]
	stosb		;#Voldownが指定されている場合は DRコマンド発行(partG)
not_vd_rhythm:

not_partG:
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
	cmp	[part],rhythm2
	jz	non_ext_env	;Rhythmは却下
	mov	ax,01c9h
	stosw		;Extend Envelope Set (Partの頭)
non_ext_env:
	cmp	[ext_lfo],0
	jz	non_ext_lfo
	cmp	[part],rhythm2
	jz	non_ext_lfo	;Rhythmは却下
	mov	ax,01cah
	stosw		;Extend LFO Set (Partの頭)
	cmp	[towns_flg],1
	jz	non_ext_lfo		;TOWNSは4.6f @@@@
	mov	ax,01bbh
	stosw		;Extend LFO Set (Partの頭)
non_ext_lfo:
	cmp	[towns_flg],1
	jz	not_adpcm_flag		;TOWNSは4.6f @@@@
	cmp	[adpcm_flag],-1
	jz	not_adpcm_flag
	cmp	[part],pcmpart	;pcmのみ
	jnz	not_adpcm_flag
	mov	ax,0f7c0h
	stosw		;ADPCM set (partの頭)
	mov	al,[adpcm_flag]
	stosb
not_adpcm_flag:
	cmp	[transpose],0
	jz	non_transpose
	cmp	[part],rhythm2
	jz	non_transpose	;Rhythmは却下
	mov	al,0b2h
	mov	ah,[transpose]
	stosw			;Master Transpose (Partの頭)
non_transpose:
endif
;==============================================================================
;	Ｍain Ｌoop
;==============================================================================

cloop:
c_next:
	lodsb
	call	sjis_check
	jnc	c_nosjis
	inc	si
	jmp	c_next
c_nosjis:
	cmp	al,1ah
	jz	part_end
	cmp	al," "+1
	jc	c_fin
	cmp	al,";"
	jz	c_fin
	cmp	al,"`"
	jnz	c_no_skip
	xor	[skip_flag],2
	jmp	c_next
c_no_skip:
	test	[skip_flag],2
	jnz	c_nskp_02
	cmp	al,"!"
	jz	hsset
	cmp	al,'"'
	jnz	c_nskp_01
	xor	[skip_flag],1
	mov	al,0c0h
	stosb
	mov	al,[skip_flag]
	and	al,1
	stosb
	jmp	c_next
c_nskp_01:
	cmp	al,"'"
	jnz	c_nskp_02
	and	[skip_flag],0feh
	mov	ax,00c0h
	stosw
	jmp	c_next
c_nskp_02:
if	efc
	dec	si
	call	lngset
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

check_lopcnt:
	cmp	[lopcnt],0
	jz	loop_ok
	push	es
	mov	ax,mml_seg
	mov	es,ax
	assume	es:mml_seg
	print_mes	warning_mes
	call	put_part
	print_mes	loop_err_mes
	pop	es
	assume	es:m_seg

	mov	byte ptr es:[di],0f8h
	inc	di
	mov	bl,1
	call	edl00

	jmp	check_lopcnt
loop_ok:

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

if	efc
	jmp	vdat_set
else
	jnz	fm3_check
	mov	al,[maxprg]
	cmp	[towns_flg],1
	jnz	maxprg_towns_chk
	xor	al,al			;TOWNSはRパート無し
maxprg_towns_chk:
	mov	[kpart_maxprg],al	;K partのmaxprgを保存
	mov	al,[deflng]
	mov	[deflng_k],al		;l 値を保存

;==============================================================================
;	FM3 拡張パートがあればそれをcompile
;==============================================================================
fm3_check:
	cmp	[fm3_ofsadr],0
	jz	pcm_check	;無し
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
	jz	pcm_check
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
;	PCM 拡張パートがあればそれをcompile
;==============================================================================
pcm_check:
	cmp	[pcm_ofsadr],0
	jz	rt		;無し
	mov	cx,8
	mov	bx,offset pcm_partchr1
pcmc_loop:
	mov	al,[bx]
	mov	byte ptr [bx],0
	inc	bx
	test	al,al
	jnz	pcmc_main
	loop	pcmc_loop
	jmp	rt

pcmc_main:
	mov	bx,[pcm_ofsadr]
	mov	dx,di
	sub	dx,offset m_buf
	mov	es:[bx],dx
	inc	bx
	inc	bx
	mov	[pcm_ofsadr],bx
	sub	al,"A"-1
	mov	[part],al
	mov	[ongen],pcm_ex
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
	mov	[pass],2

	mov	si,offset mml_buf
	call	cm_init
	mov	al,[deflng_k]
	mov	[deflng],al	; l 値だけKパートから引用

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

	call	sjis_check
	jnc	rt_nosjis
	inc	si
	jmp	rtlp3
rt_nosjis:

	cmp	al," "+1
	jc	rskip

	cmp	al,";"
	jz	rskip

	cmp	al,"`"
	jnz	r_no_skip
	xor	[skip_flag],2
	jmp	rtlp3
r_no_skip:
	test	[skip_flag],2
	jnz	rt_no_skip2

	cmp	al,"!"
	jz	hsset

rt_no_skip2:
	cmp	[kpart_maxprg],0
	jz	rskip

	cmp	al,"R"
	jnz	rtlp3
	
	xchg	bx,di

	push	bx
	mov	[hsflag],1
	mov	[prsok],0
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

endif
;==============================================================================
;	Part Init.
;==============================================================================
cm_init:
	xor	ax,ax
	mov	[maxprg],al
	mov	[volss],al
	mov	[volss2],al
	mov	[octss],al
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
	mov	[master_detune],ax
	mov	[detune],ax
	mov	[def_a],al
	mov	[def_b],al
	mov	[def_c],al
	mov	[def_d],al
	mov	[def_e],al
	mov	[def_f],al
	mov	[def_g],al
	mov	[prsok],al
	mov	[alldet],8000h

	mov	[octave],3
	mov	al,[zenlen]
	shr	al,1
	shr	al,1
	mov	[deflng],al
	ret

ife	efc
;==============================================================================
;	Remark文箇所の設定
;==============================================================================
rem_set:
	mov	[part],0

	cmp	[towns_flg],1
	jz	tclc_towns_chk

	mov	al,[lc_flag]
	push	di
	call	lc
	pop	di
	push	ds
	mov	ax,cs
	mov	ds,ax
	mov	si,offset max_all
	mov	cx,4
rep	movsw			;TC/LC書き込み (4.8a～)
	pop	ds

tclc_towns_chk:
	mov	bp,di
	inc	di
	inc	di

	mov	al,vers
	cmp	[towns_flg],1
	jnz	vers_towns_chk
	mov	al,46h		;Townsは4.6f @@@@
vers_towns_chk:

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
	add	si,2*(max_part+1)

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
	mov	bx,offset ppzfile_adr
	mov	cx,3	; #PPZFile / #PPSFile / #PCMFile

	cmp	[towns_flg],1
	jnz	ppz_towns_chk
	mov	bx,offset ppsfile_adr
	dec	cx		;Townsは4.6f @@@@
ppz_towns_chk:

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

;	#Title
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

;	#Composer
	mov	si,[bx]	; si <文字列先頭番地
	mov	ax,di
	sub	ax,offset m_buf
	mov	[bx],ax	;[bx]に替わりに転送先のアドレス(ofs)を入れておく
	or	si,si
	jnz	memow_trans_composer
	xor	al,al
	stosb
	jmp	memow_exit_composer
memow_trans_composer:
	push	ds
	mov	ax,[composer_seg]
	or	ax,ax
	jz	no_set_ds_composer
	mov	ds,ax
no_set_ds_composer:
	call	set_strings
	pop	ds
memow_exit_composer:
	inc	bx
	inc	bx

;	#Arranger
	mov	si,[bx]	; si <文字列先頭番地
	mov	ax,di
	sub	ax,offset m_buf
	mov	[bx],ax	;[bx]に替わりに転送先のアドレス(ofs)を入れておく
	or	si,si
	jnz	memow_trans_arranger
	xor	al,al
	stosb
	jmp	memow_exit_arranger
memow_trans_arranger:
	push	ds
	mov	ax,[arranger_seg]
	or	ax,ax
	jz	no_set_ds_arranger
	mov	ds,ax
no_set_ds_arranger:
	call	set_strings
	pop	ds
memow_exit_arranger:
	inc	bx
	inc	bx

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
	mov	si,offset ppzfile_adr
	cmp	[towns_flg],1
	jnz	memo_towns_chk
	mov	si,offset ppsfile_adr		;Townsは4.6f @@@@
memo_towns_chk:
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

	call	set_filename_topmd

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

	cli
	xor	ah,ah
	int	60h	; music_start
	cmp	[jump_flag],0
	jz	non_jump
	mov	ah,1ch
	mov	dx,[jump_flag]
	int	60h	; FF_Music
non_jump:
	sti

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
;	PMDへファイル名の書き込み
;==============================================================================
set_filename_topmd:
	mov	ah,21h
	int	60h
	mov	di,dx
	mov	ax,ds
	mov	es,ax	;es:di = filename buffer

;	書き込むファイルの名の元位置を所得 (ds:si)
if	hyouka
	mov	ax,mml_seg
	mov	ds,ax
	mov	si,offset mml_filename
else
	mov	ax,mml_seg
	mov	ds,ax
	mov	si,offset mml_filename
	cmp	byte ptr [save_flg],0
	jz	sft_no_save
	mov	ax,m_seg
	mov	ds,ax
	mov	si,offset m_filename
sft_no_save:
endif

;	パス名を回避
	mov	bp,si
sft_loop:
	lodsb
	call	sjis_check
	jnc	sft_no_sjis
	inc	si
	jmp	sft_loop
sft_no_sjis:
	test	al,al
	jz	sft_write
	cmp	al,"\"
	jnz	sft_loop
	mov	bp,si
	jmp	sft_loop

;	書き込み
sft_write:
	mov	si,bp
	mov	cx,12
sft_fnset_loop:
	movsb
	cmp	byte ptr -1[si],0
	jz	sft_00
	loop	sft_fnset_loop
	mov	byte ptr es:[di],0
sft_00:
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	ret

;==============================================================================
;	PCMファイルの読み込み
;==============================================================================
pcm_read:
	mov	ax,m_seg
	mov	ds,ax
	mov	ax,mml_seg
	mov	es,ax
	assume	ds:m_seg,es:mml_seg

	mov	bx,es:[ppzfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr [bx],0
	jz	non_ppzread

	mov	ax,bx			;DS:AX = PPS filename
	mov	cl,3			;２つまとめ読み
	call	ppz_load		;in PCMLOAD.INC
non_ppzread:

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

	mov	bx,[ppzfile_adr]
	add	bx,offset m_buf
	cmp	byte ptr es:[bx],0
	jz	non_ppzfile
	push	bx
	print_mes	mes_ppzfile
	pop	bx
	call	put_strings
non_ppzfile:

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
;	FF File read
;		in.ds:si	strings
;==============================================================================
read_fffile:
	mov	ax,mml_seg
	mov	es,ax
	assume	ds:nothing,es:mml_seg
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
	jmp	g_vfn_loop
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
	push	si
	mov	es,cs:[kankyo_seg]
	mov	dx,offset v_filename
	call	opnhnd
	pop	si
	pop	ds
	pop	es
	jc	not_set_voicefile
	mov	dx,offset voice_buf
	mov	cx,8*1024	;最大 8KB
	call	redhnd
	pushf
	call	clohnd
	pop	ax
	jc	not_set_voicefile
	push	ax
	popf
	jc	not_set_voicefile
	mov	ax,mml_seg
	mov	ds,ax
	mov	es,ax
	assume	ds:mml_seg
	mov	ax,m_seg
	mov	es,ax
	assume	es:m_seg
ife	hyouka
	or	[prg_flg],1
endif
	ret

not_set_voicefile:
	mov	ax,mml_seg
	mov	ds,ax
	mov	ax,m_seg
	mov	es,ax
	print_mes	warning_mes
	print_mes	ff_readerr_mes
	ret

;==============================================================================
;	オプション文字列読み取り
;==============================================================================
get_option:
	push	es
	mov	ax,mml_seg
	mov	es,ax
	assume	ds:nothing,es:mml_seg

option_loop:
	lodsb
	cmp	al," "
	jz	option_loop
	jc	option_exit
	cmp	al,"/"
	jz	option_get
	cmp	al,"-"
	jz	option_get
	mov	ax,ds
	xor	dx,dx
	cmp	ax,mml_seg
	jz	error
	cmp	ax,[kankyo_seg]
	jz	go_ret
	jmp	option_exit

option_get:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"V"
	jz	prgflg_set
	cmp	al,"P"
	jz	playflg_set
	cmp	al,"S"
	jz	saveflg_reset
	cmp	al,"M"
	jz	x68flg_set
	cmp	al,"T"
	jz	townsflg_set
	cmp	al,"N"
	jz	x68flg_reset
	cmp	al,"L"
	jz	oplflg_set
	cmp	al,"O"
	jz	memoflg_reset
	cmp	al,"A"
	jz	pcmflg_reset
	cmp	al,"C"
	jz	lcflg_set
	xor	dx,dx
	mov	ax,ds
	cmp	ax,mml_seg
	jz	error
	cmp	ax,[kankyo_seg]
	jz	go_ret
	xor	si,si
	jmp	error
go_ret:
	pop	es
	stc
	ret

;==============================================================================
;	/v,/vw	option
;==============================================================================
prgflg_set:
	mov	al,[si]
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"W"
	jnz	v_only
	inc	si
ife	hyouka
	or	[prg_flg],2
endif
	jmp	option_loop
v_only:
ife	hyouka
	or	[prg_flg],1
endif
	jmp	option_loop

;==============================================================================
;	/p	 option
;==============================================================================
playflg_set:
ife	hyouka
	mov	[play_flg],1
endif
	jmp	option_loop

;==============================================================================
;	/s	 option
;==============================================================================
saveflg_reset:
ife	hyouka
	mov	[save_flg],0
	mov	[play_flg],1
endif
	jmp	option_loop

;==============================================================================
;	/m	 option
;==============================================================================
x68flg_set:
	mov	[towns_flg],0
	mov	[x68_flg],1
	mov	[opl_flg],0
	mov	[dt2_flg],1
	jmp	option_loop

;==============================================================================
;	/n	 option
;==============================================================================
x68flg_reset:
	mov	[towns_flg],0
	mov	[x68_flg],0
	mov	[opl_flg],0
	mov	[dt2_flg],0
	jmp	option_loop

;==============================================================================
;	/t	 option
;==============================================================================
townsflg_set:
	mov	[towns_flg],1
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

;==============================================================================
;	/c	 option
;==============================================================================
lcflg_set:
	mov	[lc_flag],1
	jmp	option_loop

option_exit:
	dec	si
	pop	es
	assume	ds:mml_seg,es:m_seg
	clc
	ret

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
	cmp	al,"V"
	jz	VolDown_set
	cmp	al,"J"
	jz	JumpFlag_set
endif
	cmp	al,"F"
	jz	FM3Extend_set
	cmp	al,"D"
	jz	dt2flag_set
	cmp	al,"O"
	jz	octrev_set
	cmp	al,"B"
	jz	bend_set
	cmp	al,"I"
	jz	include_set
ps_error:
	mov	dh,"#"
	mov	dl,7
	jmp	error

macro_normal_ret:
	mov	bx,[linehead]
	mov	byte ptr [bx],";"	;"#"を";"に変換
	jmp	p1c_fin

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
	cmp	al,"E"
	jz	pcmextend_set
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
;	#PCMExtend
;==============================================================================
pcmextend_set:
ife	efc
	mov	al,3[bx]
	and	al,11011111b	;小文字＞大文字変換(4文字目)
	cmp	al,"F"
	jz	ppzfile_set

	cmp	byte ptr [si]," "
	mov	dx,"#"+6
	jc	error

	lodsb
	call	partcheck
	jc	ps_error

	push	di
	mov	di,offset pcm_partchr1
	mov	bx,offset _pcm_partchr1	;in cs
	mov	[di],al
	mov	cs:[bx],al
	inc	di
	inc	bx

	mov	cx,7	;1+7 = 8 parts
pcmex_set_loop:
	lodsb
	call	partcheck
	jc	pcme_exit
	mov	[di],al
	mov	cs:[bx],al
	inc	di
	inc	bx
	loop	pcmex_set_loop
	inc	si
pcme_exit:
	dec	si
	pop	di
	jmp	macro_normal_ret
else
	jmp	ps_error
endif

;==============================================================================
;	#PPZFile
;==============================================================================
ppzfile_set:
	mov	[ppzfile_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#PPSFile
;==============================================================================
ppsfile_set:
	mov	al,2[bx]
	and	al,11011111b	;小文字＞大文字変換(3文字目)
	cmp	al,"C"
	jz	ppcfile_set	;#PPC
	cmp	al,"Z"
	jz	pcmextend_set	;#PPZ
	cmp	al,"S"
	jnz	ps_error
	mov	[ppsfile_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Title
;==============================================================================
title_set:
	cmp	ah,"E"		;#TEmpo
	jz	tempo_set
	cmp	ah,"R"		;#TRanspose
	jz	transpose_set
	mov	al,2[bx]
	and	al,11011111b	;小文字＞大文字変換(3文字目)
	cmp	al,"M"		;#TIMer
	jz	tempo_set2
	mov	[title_adr],si
	jmp	macro_normal_ret

;==============================================================================
;	#Composer
;==============================================================================
composer_set:
	mov	[composer_adr],si
	mov	[composer_seg],0
	jmp	macro_normal_ret

;==============================================================================
;	#Arranger
;==============================================================================
arranger_set:
	cmp	ah,"D"
	jz	adpcm_set
	mov	[arranger_adr],si
	mov	[arranger_seg],0
	jmp	macro_normal_ret

;==============================================================================
;	#ADPCM	on/off
;==============================================================================
adpcm_set:
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"O"
	jnz	ps_error
	lodsb
	and	al,11011111b	;小文字＞大文字変換
	mov	ah,1
	cmp	al,"N"
	jz	adps_exit
	dec	ah
	cmp	al,"F"
	jnz	ps_error
adps_exit:
	mov	[adpcm_flag],1
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
;	#Transpose
;==============================================================================
transpose_set:
	call	lngset
	jc	ps_error
	mov	[transpose],al
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
	call	lngset
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
;	#VolumeDown
;==============================================================================
VolDown_set:
	xor	bx,bx		;FSPR select bit , 絶対/相対flag clear
voldown_loop:
	lodsb
	cmp	al,"9"+1
	jc	vd_numget
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"F"
	jnz	vd_nofm
	or	bh,1
	jmp	voldown_loop
vd_nofm:
	cmp	al,"S"
	jnz	vd_nossg
	or	bh,2
	jmp	voldown_loop
vd_nossg:
	cmp	al,"P"
	jnz	vd_nopcm
	or	bh,4
	jmp	voldown_loop
vd_nopcm:
	cmp	al,"R"
	jnz	vd_norhythm
	or	bh,8
	jmp	voldown_loop
vd_norhythm:
	cmp	al,"Z"
	mov	dx,"#"*256+1
	jnz	error
	or	bh,16
	jmp	voldown_loop
vd_noppz:

vd_numget:
	dec	si
	cmp	al,"+"
	jz	vd_numget2
	cmp	al,"-"
	jz	vd_numget2
	inc	bl		;絶対指定
vd_numget2:
	test	bh,bh
	mov	dx,"#"*256+1
	jz	error
	push	bx
	call	getnum
	pop	bx

	ror	bh,1
	jnc	vdset_nofm
	mov	[fm_voldown],dl
	mov	[fm_voldown_flag],bl

vdset_nofm:
	ror	bh,1
	jnc	vdset_nossg
	mov	[ssg_voldown],dl
	mov	[ssg_voldown_flag],bl

vdset_nossg:
	ror	bh,1
	jnc	vdset_nopcm
	mov	[pcm_voldown],dl
	mov	[pcm_voldown_flag],bl

vdset_nopcm:
	ror	bh,1
	jnc	vdset_norhythm
	mov	[rhythm_voldown],dl
	mov	[rhythm_voldown_flag],bl

vdset_norhythm:
	ror	bh,1
	jnc	vdset_noppz
	mov	[ppz_voldown],dl
	mov	[ppz_voldown_flag],bl

vdset_noppz:
	cmp	byte ptr [si],","
	jnz	macro_normal_ret
	inc	si
	jmp	VolDown_set

;==============================================================================
;	#Jump
;==============================================================================
JumpFlag_set:
	call	lngset
	mov	dx,"#"*256+6
	jc	error
	mov	[jump_flag],bx
	jmp	macro_normal_ret

;==============================================================================
;	#Tempo
;==============================================================================
tempo_set:
	call	lngset
	mov	dx,"#"*256+6
	jc	error
if	tempo_old_flag
	call	timerb_get
	mov	[timerb],dl
else
	mov	[tempo],al
endif
	jmp	macro_normal_ret

;==============================================================================
;	#Timer
;==============================================================================
tempo_set2:
	call	lngset
	mov	dx,"#"*256+6
	jc	error
	mov	[timerb],al
	jmp	macro_normal_ret

;==============================================================================
;	#Zenlength
;==============================================================================
zenlen_set:
	call	lngset
	mov	dx,"#"*256+6
	jc	error
	mov	[zenlen],al
	shr	al,1
	shr	al,1
	mov	[deflng],al
	jmp	macro_normal_ret

endif

;==============================================================================
;	#FM3Extend
;==============================================================================
FM3Extend_set:
	cmp	ah,"I"
	jz	file_name_set
	cmp	ah,"F"
	jz	fffile_set
ife	efc
	cmp	byte ptr [si]," "
	mov	dx,"#"+6
	jc	error

	lodsb
	call	partcheck
	jc	ps_error
	mov	[fm3_partchr1],al
	mov	[_fm3_partchr1],al
	lodsb
	call	partcheck
	jc	fm3e_exit
	mov	[fm3_partchr2],al
	mov	[_fm3_partchr2],al
	lodsb
	call	partcheck
	jc	fm3e_exit
	mov	[fm3_partchr3],al
	mov	[_fm3_partchr3],al
	jmp	macro_normal_ret
fm3e_exit:
	dec	si
	jmp	macro_normal_ret
else
	jmp	ps_error
endif

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

;==============================================================================
;	#FFFile
;==============================================================================
fffile_set:
	push	ds
	push	es
	call	read_fffile
	pop	es
	pop	ds
	jmp	macro_normal_ret

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
;	#octave	rev/norm
;==============================================================================
octrev_set:
	cmp	ah,"P"
	jz	option_set
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
;	#Option
;==============================================================================
option_set:
	call	get_option
	jmp	macro_normal_ret

;==============================================================================
;	#Bendrange
;==============================================================================
bend_set:
	call	lngset
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
	push	es
	push	bx
	mov	ax,hs_seg
	mov	es,ax
	assume	es:hs_seg

	call	lngset
	jc	hsset3

hsset2:
	xor	ah,ah
	add	ax,ax
	add	ax,offset hsbuf2
	mov	bx,ax
	jmp	hsset_main

hsset3:
	push	si
	call	search_hs3
	pop	si
	jnc	hsset_main	;上書き

	mov	bx,offset hsbuf3
	mov	cx,256
hsset3_loop:
	cmp	word ptr es:[bx],0
	jz	hsset3b
	add	bx,hs_length
	loop	hsset3_loop
	mov	dx,"!"*256+33
	jmp	error
hsset3b:
	push	bx
	push	di
	lea	di,2[bx]
	mov	cx,hs_length-2
hsset3b_loop:
	lodsb
	cmp	al,"!"
	jc	hsset3c
	stosb
	loop	hsset3b_loop
hsset3b_loop2:
	lodsb
	cmp	al,"!"
	jnc	hsset3b_loop2
hsset3c:
	dec	si
	pop	di
	pop	bx

hsset_main:
	push	si
hsset_loop:
	lodsb
	cmp	al,0dh	;cr
	jz	hsset_fin
	cmp	al," "+1
	jnc	hsset_loop

	mov	es:[bx],si

hsset_fin:
	pop	si
	pop	bx
	pop	es
	assume	es:m_seg

	mov	al,[pass]
	test	al,al
	jz	p1c_fin
ife	efc
	dec	al
	jz	c_fin
	jmp	rskip
else
	jmp	c_fin
endif

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
	call	sjis_check
	jnc	gp_nosjis
	inc	si
	jmp	get_param
gp_nosjis:
	cmp	al,9	;tab
	jz	get_param
	cmp	al," "
	jz	get_param
	jc	gp_skip
	cmp	al,","
	jz	get_param
	cmp	al,";"
	jz	gp_skip
	cmp	al,"`"
	jnz	gp_no_skip
	xor	[skip_flag],2
	jmp	get_param
gp_no_skip:
	test	[skip_flag],2
	jnz	get_param

	cmp	al,"="
	jz	get_vname

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
	mov	[lastprg],0	;Rパート用
	lodsb
	call	sjis_check
	jnc	olc_nosjis
	inc	si
	jmp	one_line_compile
olc_nosjis:
	cmp	al,0dh	;cr
	jz	olc_fin
	cmp	al,";"
	jz	olc_skip
	cmp	al,"`"
	jnz	olc_no_skip
	xor	[skip_flag],2
	jmp	one_line_compile
olc_no_skip:
	test	[skip_flag],2
	jnz	olc_skip2
	cmp	al," "+1
	jnc	one_line_compile
	jmp	olc02

olc0:	xor	al,al
	mov	[prsok],al
olc02:	cmp	byte ptr es:[mbuf_end],07fh	;check code
	mov	dx,19
	jnz	error	;容量オーバー
olc03:	lodsb
	call	sjis_check
	jnc	olc_nosjis2
	inc	si
	jmp	olc03
olc_nosjis2:
	cmp	al,9
	jz	olc03	;tab
	cmp	al," "
	jz	olc03
	jc	notend
	cmp	al,";"
	jz	olc_skip

	cmp	al,"`"
	jnz	olc_no_skip2
	xor	[skip_flag],2
	jmp	olc03
olc_no_skip2:
	test	[skip_flag],2
	jnz	olc_skip2

notskp:	cmp	al,'"'
	jnz	nskp_01
	xor	[skip_flag],1
	mov	dh,0c0h
	mov	dl,[skip_flag]
	and	dl,1
	jmp	parset

nskp_01:
	cmp	al,"'"
	jnz	nskp_02
	and	[skip_flag],0feh
	mov	dx,0c000h
	jmp	parset

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

olc_skip2:
	lodsb
	call	sjis_check
	jnc	os2_no_sjis
	inc	si
	jmp	olc_skip2
os2_no_sjis:
	cmp	al,0ah	;lf
	jz	comend
	cmp	al,"`"
	jnz	olc_skip2
	and	[skip_flag],0fdh
	jmp	olc03

olc_skip:
	call	line_skip
	jmp	comend

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
	mov	ah,[part]
	add	ah,"A"-1

	cmp	byte ptr [si],"!"
	jc	olc03		; | only = Select All
	jnz	skm_loop

	inc	si
skm_reverse_loop:
	lodsb
	cmp	al,ah
	jz	part_not_found
	cmp	al,13		; cr
	jz	olc_fin		; line end
	cmp	al," "+1
	jnc	skm_reverse_loop
	dec	si
	jmp	part_found

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
;	Found --- Compile Next
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
	db	"x"
	dw	otox
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
	db	"m"
	dw	partmask_set

	db	"O"
	dw	tl_set

	db	"A"
	dw	adp_set

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
	db	"."
	dw	lngrew_2
	db	"-"
	dw	lng_dec
	db	"+"
	dw	tieset_2

	db	0

;==============================================================================
;	A command ( ADPCM set )
;==============================================================================
adp_set:
	mov	ax,0f7c0h
	stosw
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	O command ( TL set )
;==============================================================================
tl_set:
	mov	al,0b8h
	cmp	[part],rhythm
	mov	dx,"O"*256+17
	jz	error
	stosb
	call	getnum
	mov	al,bl
	cmp	al,16
	mov	dx,"O"*256+6
	jnc	error
	stosb
	lodsb
	cmp	al,","
	mov	dl,6
	jnz	error
	cmp	byte ptr [si],"+"
	jz	tl_slide
	cmp	byte ptr [si],"-"
	jnz	tl_next
tl_slide:
	or	byte ptr es:-1[di],0f0h
tl_next:
	call	getnum
	mov	al,bl
	stosb
	jmp	olc0

;==============================================================================
;	m command (part mask)
;==============================================================================
partmask_set:
	call	lngset
	mov	dx,"m"*256+6
	jc	error
	cmp	al,2
	mov	dl,2
	jnc	error
	mov	dh,0c0h
	mov	dl,al
	jmp	parset

;==============================================================================
;	s command (fm slot mask)
;==============================================================================
slotmask_set:
	cmp	byte ptr [si],"d"
	jz	slotdetune_set
	cmp	byte ptr [si],"k"
	jz	slotkeyondelay_set
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
;	sk command (slot keyon delay)
;==============================================================================
slotkeyondelay_set:
	inc	si
	mov	al,0b5h
	stosb
	call	getnum
	mov	al,dl
	stosb
	cmp	byte ptr [si],","
	mov	dx,"s"*256+6
	jnz	sks_err
	inc	si
	mov	dh,"s"
	call	get_clock
sks_exit:
	stosb
	jmp	olc0
sks_err:
	test	al,al
	jz	sks_exit
	jmp	error

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
	cmp	byte ptr [si],"B"
	jz	fb_set
	call	lngset
	mov	byte ptr es:[di],0d2h
	inc	di
	stosb
	jmp	olc0

;==============================================================================
;	FB command (FeedBack set)
;==============================================================================
fb_set:	inc	si
	mov	al,0b6h
	stosb
	cmp	byte ptr [si],"+"
	jz	_fb_set
	cmp	byte ptr [si],"-"
	jz	_fb_set
	call	getnum
	cmp	bl,8
	mov	dx,"F"*256+2
	jnc	error
	mov	al,bl
	stosb
	jmp	olc0
_fb_set:
	call	getnum
	add	dl,+7
	cmp	dl,15
	mov	dx,"F"*256+2
	jnc	error
	mov	al,bl
	or	al,080h
	stosb
	jmp	olc0

;==============================================================================
;	"{" Command [Portament_start] / "{{" Command [分散和音開始]
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

;	分散和音開始アドレスをセット	4.8r
	mov	[bunsan_start],0
	cmp	byte ptr [si],"{"
	jnz	pst_end
	inc	si
	mov	[bunsan_start],di

pst_end:jmp	olc0

;==============================================================================
;	"}" Command [Portament_end] / "}}" Command [分散和音終了]
;==============================================================================
porta_end:
	cmp	byte ptr [si],"}"	;4.8r
	jz	bunsan_end		;//

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
	test	bh,bh
	mov	dx,"}"*256+8
	jnz	error
	call	lngcal
	call	futen
	stosb
	mov	dx,"}"*256+8
	jc	error

	cmp	byte ptr [si],","
	jnz	pe_exit

;	ディレイ指定
	inc	si
	call	lngset2
	mov	dx,"}"*256+6
	jc	error
	call	lngcal
	call	futen
	mov	dl,8
	cmp	al,es:-1[di]
	jnc	error

	mov	dx,es:-2[di]
	mov	es:1[di],dx
	mov	dx,es:-4[di]	;dh=start ontei
	mov	es:-1[di],dx
	mov	es:-4[di],dh
	mov	es:-3[di],al
	mov	byte ptr es:-2[di],0fbh	; "&"
	sub	es:2[di],al
	add	di,3

pe_exit:
	mov	[prsok],9	;ポルタの音長
	jmp	olc02

pe_skip:
	call	lngset2
	test	bh,bh
	mov	dx,"}"*256+8
	jnz	error
	call	futen_skip
;------	ディレイスキップ処理を挿入 2019/12/28
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	lngset2
	mov	dx,"}"*256+6
	jc	error
	call	futen_skip
;------	ここまで
	jmp	olc03

;==============================================================================
;	"}}" Command [分散和音終了]	4.8r
;	{{cdeg}}lng[,cnt[,tie[,gate[,vol]]]]
;==============================================================================
bunsan_end:
	inc	si
	cmp	[skip_flag],0
	jnz	bunsan_skip

;	和音数のチェック
	mov	bx,[bunsan_start]
	test	bx,bx
	mov	dx,"}"*256+34
	jz	error
	mov	cx,di
	sub	cx,bx
	jz	bunsan_error	; 音なし
	shr	cx,1		; cx = 分散和音数
	jc	bunsan_error	; 間が奇数バイトでエラー
	cmp	cx,17		; 17音以上でエラー
	jnc	bunsan_error
	mov	[bunsan_count],cl

;	bunsan_work に音階をセットしていく
	mov	bp,offset bunsan_work
bend_loop:
	mov	al,es:[bx]
	test	al,al
	js	bunsan_error	;音階ではない
	mov	ds:[bp],al
	inc	bx
	inc	bx
	inc	bp
	cmp	di,bx
	jnz	bend_loop

;	パラメータ取り込み
	call	lngset2			;prm1 全体音長
	test	bh,bh
	jnz	bunsan_error
	call	lngcal
	call	futen
	jc	bunsan_error
	mov	[bunsan_length],al

	xor	al,al
	mov	[bunsan_vol],al		;音量 def = ±0
	mov	[bunsan_gate],al	;ゲート def = 0
	inc	al
	mov	[bunsan_1cnt],al	;1cnt def = %1
	mov	[bunsan_tieflag],al	;Tie def = ON(1)

	cmp	byte ptr [si],","
	jnz	bunsan_main
	inc	si
	call	lngset2			;prm2 1音符長
	jc	bunsan_prm3
	test	bh,bh
	jnz	bunsan_error
	call	lngcal
	call	futen
	jc	bunsan_error
	mov	[bunsan_1cnt],al
bunsan_prm3:
	cmp	byte ptr [si],","
	jnz	bunsan_main
	inc	si
	call	lngset2			;prm3 タイフラグ
	jc	bunsan_prm4
	test	bh,bh
	jnz	bunsan_error
	cmp	al,2
	jnc	bunsan_error
	mov	[bunsan_tieflag],al
bunsan_prm4:
	cmp	byte ptr [si],","
	jnz	bunsan_main
	inc	si
	call	lngset2			;prm4 ゲート長
	jc	bunsan_prm5
	test	bh,bh
	jnz	bunsan_error
	cmp	al,[bunsan_length]
	jnc	bunsan_error
	mov	[bunsan_gate],al
	sub	[bunsan_length],al
bunsan_prm5:
	cmp	byte ptr [si],","
	jnz	bunsan_main
	inc	si
	call	getnum			;prm5 音量±
	mov	[bunsan_vol],dl


;	分散和音展開
bunsan_main:
	mov	di,[bunsan_start]
	dec	di		;ポルタコマンドをつぶす

;	ループ回数チェック
	mov	al,[bunsan_1cnt]
	mul	[bunsan_count]		;AX = 音符数 x 一音符の長さ = 1ループの長さ
	test	ah,ah
	jnz	bunsan_error
	mov	[bunsan_1loop],al
	xor	cx,cx
	mov	cl,[bunsan_length]
	xchg	ax,cx			;AX = 全体の長さ / CX = 1ループの長さ
	cmp	cx,ax
	jnc	bunsan_last		;1ループに満たない場合
	div	cl			;AL = 全体の長さ \ 1ループの長さ = ループ回数
	cmp	[bunsan_tieflag],0
	jz	bunsan_setloop
	test	ah,ah			;タイありで割り切れた場合は
	jnz	bunsan_setloop
	dec	al			;ループ回数 -1

bunsan_setloop:
	cmp	al,1			;ループ1回ならループ不要
	jz	bunsan_nonloop

	push	ax
	mov	al,0f9h			;"[" Loop Start
	stosb
	mov	bx,di			; BX = 戻り先
	inc	di
	inc	di
	push	bx
	call	bunsan_set1loop
	pop	bx
	mov	al,0f8h			;"]" Loop End
	stosb
	pop	ax
	stosb
	stosb
	mul	[bunsan_1loop]
	sub	[bunsan_length],al
	mov	ax,bx
	sub	ax,offset m_buf
	stosw
	lea	ax,[di-4]
	sub	ax,offset m_buf
	mov	es:[bx],ax		;戻り先セット
	jmp	bunsan_last

;	1ループでいいのでループ不要
bunsan_nonloop:
	call	bunsan_set1loop
	mov	al,[bunsan_1loop]
	sub	[bunsan_length],al

;	ループ後最終セット
bunsan_last:
	cmp	[bunsan_length],0
	jz	bunsan_exit		;タイなしの場合ここで0になることがある
	mov	bx,offset bunsan_work
bunsan_last_loop:
	mov	al,[bx]
	stosb
	inc	bx
	mov	al,[bunsan_1cnt]
	mov	ah,[bunsan_length]
	cmp	al,ah
	jnc	bunsan_lastnote
	stosb
	sub	[bunsan_length],al
	cmp	[bunsan_tieflag],1
	jnz	bunsan_last_loop
	mov	al,0fbh
	stosb
	jmp	bunsan_last_loop

bunsan_lastnote:
	mov	al,ah
	stosb

;	分散和音終了処理
bunsan_exit:
	mov	ah,[bunsan_gate]	;Gateがある場合は休符追加
	test	ah,ah
	jz	bunsan_exit2
	mov	al,0fh
	stosb
	mov	al,ah
	stosb
bunsan_exit2:
	xor	ax,ax
	mov	[bunsan_start],ax
	mov	[porta_flag],al
	jmp	olc0

;	1ループ分音階をセット
bunsan_set1loop:
	mov	bx,offset bunsan_work
	xor	cx,cx
	mov	cl,[bunsan_count]	;CX=音符数
bunsan_s1l_loop:
	mov	al,[bx]
	stosb				;音階セット
	inc	bx
	mov	al,[bunsan_1cnt]
	stosb				;長さセット
	cmp	[bunsan_tieflag],1
	jnz	bunsan_s1l_fin
	mov	al,0fbh			;"&"セット
	stosb
bunsan_s1l_fin:
	loop	bunsan_s1l_loop
	mov	ah,[bunsan_vol]
	test	ah,ah
	jz	bunsan_s1l_exit
	mov	al,0e3h			;)x
	jns	bunsan_sl1_volset
	dec	al			;(x
	neg	ah
bunsan_sl1_volset:
	stosb
	mov	al,ah
	stosb
bunsan_s1l_exit:
	ret

bunsan_error:			;分散和音／エラー時の処理
	mov	dx,"}"*256+35
	jmp	error

bunsan_skip:			;分散和音／スキップ時の処理
	call	lngset2
	call	futen_skip
	cmp	byte ptr [si],","
	jnz	bskip_end
	inc	si
	call	lngset2
	call	futen_skip
	cmp	byte ptr [si],","
	jnz	bskip_end
	inc	si
	call	lngset2
	cmp	byte ptr [si],","
	jnz	bskip_end
	inc	si
	call	lngset2
	cmp	byte ptr [si],","
	jnz	bskip_end
	inc	si
	call	getnum
bskip_end:
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
	mov	dh,"W"
	call	get_clock
	mov	[ge_delay],al
	or	al,al
	jz	ge_cut
	mov	[ge_tie],0
	mov	[ge_dep_flag],0
	mov	[ge_depth],-1
	mov	[ge_depth2],-1
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	cmp	byte ptr [si],"%"
	jnz	ge_no_depf
	inc	si
	mov	[ge_dep_flag],1
ge_no_depf:
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

	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	getnum		;dummy
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	getnum		;dummy
	jmp	olc03

;==============================================================================
;	"S" Command [装飾音符の設定]
;	Sspeed[,depth]
;==============================================================================
sousyoku_onp_set:
	cmp	byte ptr [si],"E"
	jz	ssgeg_set
	mov	dh,"S"
	call	get_clock
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
	cmp	byte ptr [si],","
	jnz	olc03
	inc	si
	call	lngset		;dummy
	jmp	olc03

;==============================================================================
;	"SE" Command [SSGEG指定] →yコマンド変換
;	SEslot,num
;==============================================================================
ssgeg_set:
	mov	dx,"S"*256+17
ife	efc
	cmp	[ongen],psg		;FMでなければエラー
	jnc	error
endif
	mov	al,[opl_flg]		;OPL/OPMではエラー
	or	al,[x68_flg]
	jnz	error
	inc	si

	call	lngset2
	mov	dx,"S"*256+6
	jc	error
	cmp	byte ptr [si],","
	jnz	error
	mov	dl,2
	test	al,al
	jz	error
	cmp	al,16
	jnc	error

	inc	si
	push	ax
	call	lngset2			;AL=num
	pop	cx			;CL=slot
	mov	dx,"S"*256+6
	jc	error
	mov	dl,2
	cmp	al,16
	jnc	error

	mov	dh,[part]		;DHにFMのSSGEG reg取得
	dec	dh
	cmp	dh,6
	jc	sss_notfm3ex
	mov	dh,2			;6以上はFM3exのみ
sss_notfm3ex:
	cmp	dh,3
	jc	sss_notfm2
	sub	dh,3			;FM2ならpart -3
sss_notfm2:
	add	dh,90h			;SSGEG $90 + [part]

	shr	cl,1			;指定slotに対応したyコマンド発行
	jnc	sss_slot2
	call	sss_set1slot
sss_slot2:
	add	dh,8
	shr	cl,1
	jnc	sss_slot3
	call	sss_set1slot
sss_slot3:
	sub	dh,4
	shr	cl,1
	jnc	sss_slot4
	call	sss_set1slot
sss_slot4:
	add	dh,8
	shr	cl,1
	jnc	sss_fin
	call	sss_set1slot
sss_fin:
	jmp	olc0

sss_set1slot:
	mov	byte ptr es:[di],0efh
	inc	di
	mov	es:[di],dh
	inc	di
	stosb
	ret

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
;	 Hpms[,ams][,dly]
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
	mov	ah,al
	mov	al,0e1h
	mov	es:[di],ax
	inc	di
	inc	di
	mov	dh,"H"
	lodsb
	cmp	al,","
	jz	hdelay_set2
	dec	si
	jmp	olc0
endif
;==============================================================================
;	Command "#" （ハードＬＦＯのスイッチ）
;	 #sw[,depth]
;	Command "#w/#p/#a/##" （OPM用）
;	 #w wf
;	 #p pmd
;	 #a amd
;	 ## wf,pmd,amd
;	Command "#D"	ハードＬＦＯディレイ
;==============================================================================
hardlfo_onoff:
if	efc
	mov	dx,"#"*256+11
	jmp	error
else
	lodsb
	cmp	al,"D"
	jz	hdelay_set
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
	cmp	byte ptr [si],","
	jnz	hloff_noparam
	inc	si
	call	lngset		;Dummy
hloff_noparam:
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

hdelay_set:
	mov	dh,"#"
hdelay_set2:
	call	get_clock
	mov	dl,al
	mov	dh,0e4h
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
lngmul:	call	lngset
	or	al,al
	mov	dx,"^"*256+2
	jz	error

	cmp	[skip_flag],0
	jnz	olc03

	test	[prsok],1	;直前 = 音長?
	mov	dl,16
	jz	error
	test	[prsok],2	;加工されているか?
	mov	dl,31
	jnz	error

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
	test	[prsok],8	;ポルタ?
	mov	dx,"^"*256+8
	jnz	error
	inc	al
	mov	byte ptr es:-1[di],0ffh
	cmp	[part],rhythm	;R ?
	jz	lmo_r
	mov	byte ptr es:[di],0fbh
	mov	bl,es:-2[di]
	mov	es:1[di],bl
	mov	byte ptr es:2[di],0
	add	di,3
	or	[prsok],2	;加工フラグ
	jmp	lnml01
lmo_r:
	mov	word ptr es:[di],000fh	;休符
	inc	di
	inc	di
	or	[prsok],2	;加工フラグ
	jmp	lnml01

;==============================================================================
;	"="  ... Length Rewrite
;	数値 ... Length Rewrite
;==============================================================================
lngrew:	cmp	[skip_flag],0
	jnz	lng_skip_ret

	test	[prsok],1	;直前=音長?
	mov	dl,16
	jz	error
	test	[prsok],2	;直前=加工音長?
	mov	dl,31
	jnz	error

	dec	di
	cmp	byte ptr [si],"."
	jnz	not_futen_rew
	mov	al,es:[di]
	mov	[leng],al
	jmp	futen_rew
not_futen_rew:
	call	lngset2
	test	bh,bh
	mov	dx,"="*256+8
	jnz	error
	call	lngcal
futen_rew:
	call	futen
	stosb
	jnc	olc03
	test	[prsok],8	;ポルタ?
	jz	olc03
	mov	dx,"^"*256+8
	jmp	error

lngrew_2:
	dec	si
	jmp	lngrew

;==============================================================================
;	"-"  ... Length 減算
;==============================================================================
lng_dec:
	cmp	[skip_flag],0
	jnz	lng_skip_ret

	test	[prsok],1	;直前=音長?
	mov	dx,"="*256+16
	jz	error

	call	lngset2
	test	bh,bh
	mov	dx,"-"*256+8
	jnz	error
	call	lngcal
	call	futen
	mov	dx,"-"*256+8
	jc	error

	cmp	es:-1[di],al
	mov	dl,8
	jbe	error		;c or z=1
	sub	es:-1[di],al
	jmp	olc03

lng_skip_ret:
	call	lngset2
	test	bh,bh
	mov	dx,"-"*256+8
	jnz	error
	call	futen_skip
	jmp	olc03

;==============================================================================
;	c ～ b の時
;==============================================================================
otoc:	mov	al,0
	mov	ah,[def_c]
	jmp	otoset
otod:	mov	al,2
	mov	ah,[def_d]
	jmp	otoset
otoe:	mov	al,4
	mov	ah,[def_e]
	jmp	otoset
otof:	mov	al,5
	mov	ah,[def_f]
	jmp	otoset
otog:	mov	al,7
	mov	ah,[def_g]
	jmp	otoset
otoa:	mov	al,9
	mov	ah,[def_a]
	jmp	otoset
otob:	mov	al,0bh
	mov	ah,[def_b]
	jmp	otoset
otox:	mov	al,0ch
	jmp	otoset
otor:	mov	al,0fh
	jmp	rest

otoset:
ife	efc
	cmp	[towns_flg],1	; TOWNSならKパートcheckは要らない
	jz	otoset_towns_chk
	cmp	[part],rhythm2
	mov	dl,17
	jz	error		; K part = error
otoset_towns_chk:
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
	jnz	bp9
	xchg	ch,cl
	mov	es:[di],cx
	inc	di
	inc	di
	mov	[length_check1],1	;音長データがあったよ
	mov	[length_check2],1
	mov	[prsok],0		;prsok RESET
	jmp	bp9
endif
;==============================================================================
;	=,+,- 判定
;==============================================================================
ots000:
	cmp	al,0ch		;x?
	jz	otoset_x	;なら素直にそのまま設定

	mov	bh,[octave]
	and	bh,0fh		;bh <-オクターブ

	cmp	byte ptr [si],"="
	jz	natural
	or	ah,ah
	jz	ots001
	add	al,ah
	jmp	bp3		;範囲check
natural:
	inc	si
ots001:
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
	cmp	byte ptr [si],"+"	;+
	jz	ots001
	cmp	byte ptr [si],"-"	;-
	jz	ots001

;==============================================================================
;	音階データをblにセット
;==============================================================================
	ror	bh,1
	ror	bh,1
	ror	bh,1
	ror	bh,1
	or	bl,bh	; bl=音階 DATA

ots002:
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
	add	bx,[master_detune]
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
	cmp	[towns_flg],1
	jz	rest_towns_chk	; TOWNSならKパートcheckは要らない
	cmp	[part],rhythm2
	mov	dx,"r"*256+17
	jz	error		; K part = error
rest_towns_chk:
endif
otoset_x:
	mov	bl,al

;==============================================================================
;	音階 DATA SET
;==============================================================================

bp8:	cmp	[skip_flag],0
	jz	bp8b
	cmp	[acc_adr],di	;直前が (^ )^命令なら
	jnz	bp8a
	sub	di,2		;それを削除
	mov	[acc_adr],0
bp8a:
	call	lngset2
	test	bh,bh
	mov	dx,8
	jnz	error
	call	futen_skip
	jmp	bp10

bp8b:	mov	[length_check1],1	;音長データがあった
	mov	[length_check2],1
	mov	es:[di],bl
	inc	di

;==============================================================================
;	音長計算
;==============================================================================

bp9:	call	lngset2
	test	bh,bh
	mov	dx,8
	jnz	error
	call	lngcal
	and	[prsok],0fdh	;加工音長フラグreset
	call	futen
	call	press

;==============================================================================
;	音長 DATA SET
;==============================================================================
	mov	al,[leng]
	stosb
	or	[prsok],1	;音長flagをset
	and	[prsok],0f3h	;音長+タイ,ポルタflagをreset

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

	mov	al,[ss_length]	;長さが足りない
	sub	al,es:-1[di]
	jnc	ge_ss1

	mov	al,[ge_flag1]	;(^の重複を避ける
	test	al,al
	jz	no_dec_di
	cmp	al,es:-4[di]
	jnz	no_dec_di
	mov	al,[ge_flag2]
	cmp	al,es:-3[di]
	jnz	no_dec_di
	mov	ax,es:-2[di]
	mov	es:-4[di],ax
	dec	di
	dec	di

no_dec_di:
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
	or	[prsok],2	;直前byte = 加工された音長

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
	test	al,al
	js	ge_minus
	jz	gen_00

;==============================================================================
;	音量が上がる
;==============================================================================
	cmp	[ge_dep_flag],1
	jz	gen_no_sel_vol
	call	ongen_sel_vol
gen_no_sel_vol:
	or	al,al	;0?
	jz	gen_not_set
	mov	byte ptr es:[di],0deh
	inc	di
	mov	[ge_flag1],0deh
	stosb
	mov	[ge_flag2],al
gen_not_set:
	mov	al,[ge_depth]
	add	al,[ge_depth2]
	cmp	[ge_dep_flag],1
	jz	gen_01
	cmp	al,16
	jc	gen_00
	mov	al,15
gen_00:
	mov	[ge_depth],al
	ret
gen_01:
	test	al,al
	jns	gen_00
	mov	[ge_depth],+127
	ret

;==============================================================================
;	音量が下がる
;==============================================================================
ge_minus:
	neg	al
	cmp	[ge_dep_flag],1
	jz	gem_no_sel_vol
	call	ongen_sel_vol
gem_no_sel_vol:
	or	al,al	;0?
	jz	gem_not_set
	mov	byte ptr es:[di],0ddh
	inc	di
	mov	[ge_flag1],0ddh
	stosb
	mov	[ge_flag2],al
gem_not_set:
	mov	al,[ge_depth]
	add	al,[ge_depth2]
	cmp	[ge_dep_flag],1
	jz	gem_01
	cmp	al,-15
	jnc	gem_00
	mov	al,-15
gem_00:
	mov	[ge_depth],al
	ret
gem_01:
	test	al,al
	js	gem_00
	mov	[ge_depth],-127
	ret

;==============================================================================
;	各音源によって音量の増減を変える
;==============================================================================
ongen_sel_vol:
ife	efc
	cmp	[part],pcmpart
	jz	sel_pcm
	cmp	[ongen],pcm_ex
	jz	sel_pcm
	cmp	[towns_flg],1
	jnz	osv_no_towns
	cmp	[part],rhythm2
	jz	sel_pcm
osv_no_towns:
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
	cmp	byte ptr es:-2[di],0ch	;x?
	jz	ss_set_ret		;なら装飾しない
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
	or	[prsok],2	;直前byte = 加工された音長
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
press:	test	[prsok],80h	;直前 = Rhythm？
	jnz	press_ret
	test	[prsok],8	;直前 = ポルタ？
	jnz	press_ret
	cmp	[skip_flag],0
	jnz	press_ret
	test	[prsok],4	;直前 = +タイ？
	jnz	press_main
	cmp	byte ptr es:-1[di],0fh
	jnz	press_ret
	test	[prsok],1	;直前 = 音長？
	jnz	restprs
press_ret:
	ret

press_main:
ife	efc
	cmp	[part],rhythm
	jz	prs3		;リズムパートで圧縮可能＝無条件に圧縮
endif

prs0:	mov	ah,es:-1[di]
	cmp	ah,es:-4[di]
	jnz	press_ret
prs1:	sub	di,3
	or	[prsok],2	;加工したflag
	add	al,es:[di]
	jnc	prs200
	mov	byte ptr es:[di],255
	inc	al		;255 over
	add	di,3
	cmp	ah,0fh
	jnz	prs200
	dec	di
	mov	es:-1[di],ah	;r&r -> rr に変更
prs200:	mov	[leng],al
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
	or	[prsok],2	;加工したflag
	add	al,es:[di]
	jnc	prs200
	mov	byte ptr es:[di],255
	inc	al		;255 over
	inc	di
	inc	di
	jmp	prs200

;==============================================================================
;	数値の読み出し（書かれていない時は１）
;		output	bx/al/[leng]
;==============================================================================
lngset:
	call	lngset2
	jnc	lngset_ret
	mov	bx,1
	jmp	lnexit

;==============================================================================
;	[si]から数値を読み出す
;	数字が書かれていない場合は[deflng]の値が返り、cy=1になる
;		output	al/bx/[leng]
;==============================================================================
lngset2:
	lodsb
	cmp	al," "
	jz	lngset2
	cmp	al,9
	jz	lngset2
	xor	bh,bh
	mov	[calflg],bh
	cmp	al,"%"
	jnz	lgs00
	mov	[calflg],1
	lodsb
lgs00:	cmp	al,"$"
	jz	lgs01
	dec	si

;	10進の場合
	call	numget
lgs02:	mov	bl,al
	jnc	lng1
lgs03:	mov	bl,[deflng]
	mov	[calflg],1
	stc
	jmp	lnexit

lng1:	call	numget	;A=NUMBER
	jnc	lng2

	clc
lnexit:	mov	al,bl
	mov	[leng],al
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
lgs01:	call	hexget8
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
;	符点(.)があるかを見て、あれば[leng]を1.5倍する。
;	符点が２個以上あっても可
;		output	al/bl/[leng]
;==============================================================================
futen:	mov	al,[leng]
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
	mov	[leng],al
	clc
	ret
ft1:
	cmp	[ge_delay],0
	mov	dx,"."*256+20
	jnz	error		;Wコマンド使用中はError
	cmp	[ss_length],0
	jnz	error		;Sコマンド使用中もError
ife	efc
	cmp	[part],rhythm
	jz	ft1_r
endif
	mov	word ptr es:[di],0fbh*256+255	;音長255＋タイを設定
	inc	di
	inc	di
	mov	bl,es:-3[di]
	mov	es:[di],bl	;音符
	inc	di
ft2:	sub	ax,255
	or	ah,ah
	jnz	ft1		;音長 255 OVER
	mov	bx,ax
	mov	[leng],al
	or	[prsok],2	;直前＝加工された音長
	stc
	ret

ft1_r:	mov	word ptr es:[di],0fh*256+255	;音長255＋休符を設定
	inc	di
	inc	di
	jmp	ft2

futen_skip:
	lodsb
	cmp	al,"."
	jz	futen_skip
	dec	si
	ret

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
	cmp	byte ptr [si],"+"
	jz	octss_set
	cmp	byte ptr [si],"-"
	jz	octss_set
	call	lngset
	mov	dl,6
	jc	error
	dec	al
	add	al,[octss]
octs0:	
	cmp	al,8
	mov	dl,26
	jnc	error
	mov	[octave],al
	jmp	olc03
octss_set:
	call	getnum
	mov	[octss],dl
	mov	al,[octave]
	add	al,dl
	jmp	octs0

;==============================================================================
;	COMMAND ">","<" オクターブup/down
;==============================================================================
octup:
	mov	al,[octave]
	inc	al
	jmp	octs0
octdown:
	mov	al,[octave]
	dec	al
	jmp	octs0

;==============================================================================
;	COMMAND	"l"	デフォルト音長の設定
;	COMMAND	"l="	直前の音長の変更
;	COMMAND	"l-"	直前の音長の減算
;	COMMAND	"l^"	直前の音長の乗算
;==============================================================================
lengthset:
	lodsb
	cmp	al,"="
	jz	lngrew
	cmp	al,"-"
	jz	lng_dec
	cmp	al,"+"
	jz	tieset_2
	cmp	al,"^"
	jz	lngmul
	dec	si
	call	lngset2
	mov	dx,"l"*256+6
	jc	error
	test	bh,bh
	mov	dl,8
	jnz	error
	call	lngcal
	call	futen
	mov	dx,"l"*256+8
	jc	error
	mov	[deflng],al
	jmp	olc03

;==============================================================================
;	COMMAND "C" 全音符の長さを設定
;==============================================================================
zenlenset:
	call	lngset
	mov	[zenlen],al
	push	ax
	shr	al,1
	shr	al,1
	mov	[deflng],al
	pop	ax
	jmp	syousetu_lng_set_2

;==============================================================================
;	音長から具体的な長さを得る
;		INPUTS	-- [leng] to 音長
;			-- [zenlen] to 全音符の長さ
;		OUTPUTS	-- al,[leng]
;==============================================================================
lngcal:	mov	al,[leng]
	or	al,al
	mov	dx,21
	jz	error		;LENGTH=0 ... ERROR
	cmp	[calflg],0
	jz	lcl001
	ret

lcl001:	mov	al,[zenlen]
	xor	ah,ah
	div	[leng]
	or	ah,ah
	mov	dx,21
	jnz	error		;音長が全音符の公約数でない
	mov	[leng],al
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
tempoa:
if	efc
	mov	dx,"t"*256+12
	jmp	error	;効果音emlにはテンポは指定出来ない
else
	mov	al,byte ptr [si]
	mov	ah,0fdh		;t±
	cmp	al,"+"
	jz	tempo_ss
	cmp	al,"-"
	jz	tempo_ss
	call	lngset
	cmp	al,18
	mov	dx,"t"*256+2
	jc	error

ife	tempo_old_flag
	mov	ax,0fffch	;t
	stosw
	mov	al,bl
	stosb
	jmp	olc0
else
	call	timerb_get
	mov	al,dl
	jmp	tset
endif
endif

;==============================================================================
;	"T" Command Entry
;==============================================================================

tempob:
if	efc
	mov	dx,"T"*256+12
	jmp	error	;効果音emlにはテンポは指定出来ない
else
	mov	al,byte ptr [si]
	mov	ah,0feh		;T±
	cmp	al,"+"
	jz	tempo_ss
	cmp	al,"-"
	jz	tempo_ss
	call	lngset

tset:
	cmp	al,251		;251～255はエラー
	mov	dx,"t"*256+2
	jnc	error
	mov	dh,0fch
	mov	dl,al
	jmp	parset

tempo_ss:
	mov	al,0fch
	stosw
	call	getnum
	mov	al,dl
	or	al,al
	jz	tss_non
	stosb
	jmp	olc0
tss_non:		;t±0 T±0の時は無視
	dec	di
	dec	di
	jmp	olc02
endif

if	tempo_old_flag
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
	or	ah,ah
	jns	tbg_ret
	dec	dl	;四捨五入
tbg_ret:
	ret
endif

;==============================================================================
;	clock値またはlength値を読み取る
;		input	dh	command name
;		output	al	clock
;==============================================================================
get_clock:
	cmp	byte ptr [si],"l"
	jnz	gcl_no_length
	inc	si
	push	dx
	call	lngset2
	test	bh,bh
	mov	dl,8
	jnz	error
	call	lngcal
	call	futen
	pop	dx
	mov	dl,8
	jc	error
	ret
gcl_no_length:
	call	lngset
	ret

;==============================================================================
;	COMMAND	"q" step-gate time change
;==============================================================================
qset:	cmp	byte ptr [si],","
	jz	qsetb
	mov	dh,"q"
	call	get_clock
	mov	dh,al
	mov	dl,0feh
	mov	es:[di],dx
	inc	di
	inc	di
	cmp	byte ptr [si],"-"
	jnz	qseta

	inc	si
	push	dx
	mov	dh,"q"
	call	get_clock
	mov	dh,al
	mov	dl,0b1h
	pop	ax
	sub	dh,ah
	jnc	qrnd_set
	neg	dh
	or	dh,80h
qrnd_set:
	test	dh,dh
	jz	qseta
	mov	es:[di],dx
	inc	di
	inc	di

qseta:	cmp	byte ptr [si],","
	jnz	olc0
qsetb:	inc	si
	mov	dh,"q"
	call	get_clock
	mov	dl,al
	mov	dh,0b3h
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
	cmp	al,")"
	jz	vss2
	cmp	al,"("
	jz	vss2m
	call	lngset
	add	bl,[volss2]
	cmp	bl,17
	mov	dx,"v"*256+2
	jnc	error

ife	efc
	cmp	[part],pcmpart
	jz	vsetm
	cmp	[ongen],pcm_ex
	jz	vsetm
	cmp	[towns_flg],1
	jnz	vsa_no_towns
	cmp	[part],rhythm2
	jz	vsetm		;TownsのKパートはPCM相当
vsa_no_towns:
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
	test	[volss],80h
	jz	vset3
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
	cmp	[ongen],pcm_ex
	jz	vsetm1
	cmp	[towns_flg],1
	jnz	vset
	cmp	[part],rhythm2
	jz	vsetm1		;TownsのKパートはPCM相当
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
	cmp	[ongen],pcm_ex
	jz	vsetm1
	cmp	[towns_flg],1
	jnz	vset2
	cmp	[part],rhythm2
	jz	vsetm1		;TownsのKパートはPCM相当
endif
	jmp	vset2

;==============================================================================
;	command "v)"/"v(" entry
;==============================================================================
vss2:	inc	si
	call	getnum
	mov	[volss2],dl
	jmp	olc03

vss2m:	inc	si
	call	getnum
	neg	dl
	mov	[volss2],dl
	jmp	olc03

;==============================================================================
;	command	"@"	音色の変更
;==============================================================================
neirochg:
	xor	cx,cx
	cmp	byte ptr [si],"@"
	jnz	nc01
	inc	si
	mov	cx,128
nc01:	push	cx
	call	lngset
	pop	cx
	add	bx,cx
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
	cmp	[ongen],pcm_ex
	jz	repeat_check
	cmp	[part],rhythm2
	jnz	parset
	cmp	[towns_flg],1
	jz	repeat_check		;townsの K = PCM part
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
;	COMMAND "&"	タイ
;	COMMAND "&&"	スラー
;	COMMAND "+"     直前の音長の加算
;==============================================================================
tieset:
	cmp	byte ptr [si],"&"	;スラー?
	jz	sular

tieset_2:
	cmp	[skip_flag],0
	jnz	tie_skip

	call	lngset2
	jc	tie_norm
	test	bh,bh
	mov	dx,"]"*256+8
	jnz	error
	test	[prsok],1	;直前byte = 音長?
	mov	dl,22
	jz	error
	test	bh,bh
	mov	dl,8
	jnz	error

	dec	di
	call	lngcal
	call	futen
	mov	dx,"&"*256+8
	jc	error

	mov	ah,es:[di]
	add	ah,al
	jc	tie_lng_over
	mov	al,ah
	stosb
	or	[prsok],2	;直前 = 加工音長
	jmp	olc02

tie_lng_over:
	inc	di
	test	[prsok],8	;ポルタ?
	mov	dx,"^"*256+8
	jnz	error
ife	efc
	cmp	[part],rhythm
	jz	tlo_r		;R
endif
	mov	byte ptr es:[di],0fbh
	mov	ah,es:-2[di]
	inc	di
	mov	es:[di],ah
	inc	di
	stosb
	mov	[prsok],1	;直前 = 音長
	jmp	olc02
tlo_r:
	mov	byte ptr es:[di],0fh	;休符
	inc	di
	stosb
	mov	[prsok],3	;直前 = 加工音長
	jmp	olc02

tie_norm:
	mov	[tie_flag],1
ife	efc
	cmp	[part],rhythm
	mov	dx,"&"*256+32
	jz	error		;R
endif
	mov	byte ptr es:[di],0fbh
	inc	di
	test	[prsok],1	;直前byte = 音長?
	jz	olc0		;でなければ prsok = 0クリア
	or	[prsok],4	;音長+タイのフラグをセット
	and	[prsok],0feh	;音長のフラグをリセット
	jmp	olc02
tie_skip:
	call	lngset2
	test	bh,bh
	mov	dx,"&"*256+8
	jnz	error
	call	futen_skip
	jmp	olc03

sular:
ife	efc
	cmp	[part],rhythm
	mov	dx,"&"*256+32
	jz	error		;R
endif
	inc	si
	cmp	[skip_flag],0
	jnz	tie_skip

	mov	al,0c1h
	stosb
	push	si
	call	lngset2
	pushf
	test	bh,bh
	mov	dx,"&"*256+8
	jnz	error
	popf
	pop	si
	jc	olc0

	mov	bl,es:-3[di]	;bl=前の音階
	jmp	ots002		;通常音程コマンド発行

;==============================================================================
;	COMMAND "D"	デチューンの設定
;==============================================================================
detset:
	lodsb
	cmp	al,"D"
	jz	detset_2
	cmp	al,"X"
	jz	extdet_set
	cmp	al,"M"
	jz	mstdet_set
	cmp	al,"F"
	jz	vd_fm
	cmp	al,"S"
	jz	vd_ssg
	cmp	al,"P"
	jz	vd_pcm
	cmp	al,"R"
	jz	vd_rhythm
	cmp	al,"Z"
	jz	vd_ppz

	dec	si
	call	getnum

	mov	[detune],bx
	add	bx,[master_detune]
detset_exit:
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
	call	getnum

	mov	byte ptr es:[di],0d5h
	inc	di
	mov	es:[di],bx
	inc	di
	inc	di
	jmp	olc0

;==============================================================================
;	COMMAND "DM"	マスターデチューン指定
;==============================================================================
mstdet_set:
	call	getnum
	mov	[master_detune],bx
	add	bx,[detune]
	jmp	detset_exit

;==============================================================================
;	COMMAND "DX"	拡張デチューン指定
;==============================================================================
extdet_set:
	mov	al,0cch
	stosb
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "DF"/"DS"/"DP"/"DR" 音量ダウン設定
;==============================================================================
vd_fm:	mov	al,0feh
	jmp	vd_main
vd_ssg:	mov	al,0fch
	jmp	vd_main
vd_pcm:	mov	al,0fah
	jmp	vd_main
vd_rhythm:
	mov	al,0f8h
	jmp	vd_main
vd_ppz:
	mov	al,0f5h
vd_main:
	cmp	byte ptr [si],"+"
	jz	vd_main2
	cmp	byte ptr [si],"-"
	jz	vd_main2
	inc	al
vd_main2:
	mov	byte ptr es:[di],0c0h
	inc	di
	stosb

	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	符号付き数値を読む
;		OUTPUTS -- bx[word],dl[byte]
;==============================================================================
getnum:
	lodsb
	cmp	al," "
	jz	getnum
	cmp	al,9
	jz	getnum
	cmp	al,"+"
	jz	plusb
	cmp	al,"-"
	jnz	plusa
	; -
	mov	dh,1
	jmp	gn0	
plusa:	; +
	dec	si
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
	call	lngset
	jnc	edl00
	mov	bl,[loop_def]
	jmp	edl00b
edl00:	test	bh,bh
	mov	dx,"]"*256+2
	jnz	error

;	繰り返し回数セット
edl00b:
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

	or	si,si		;pass2最後のcheck_loopか?
	jnz	olc0
	ret

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
	mov	dx,"L"*256+17
if	efc
	jmp	error		;R
else
	cmp	[part],rhythm
	jz	error		;R
	mov	byte ptr es:[di],0f6h
	inc	di
	mov	[allloop_flag],1
	mov	[length_check1],0
	jmp	olc0
endif

;==============================================================================
;	COMMAND	"_" [転調] , "__" [相対転調] , "_M" [Master転調]
;	"_{" Command[移調設定]
;==============================================================================
oshift:
	cmp	byte ptr [si],"M"
	jz	master_trans_set
	cmp	byte ptr [si],"{"
	jz	def_onkai_set
	cmp	byte ptr [si],"_"
	jnz	osf00
	inc	si
	call	getnum
	mov	dh,0e7h
	jmp	parset		;__ command
osf00:
	call	getnum
	mov	dh,0f5h
	jmp	parset		;_  command

master_trans_set:
	inc	si
	call	getnum
	mov	dh,0b2h
	jmp	parset		;_M  command

def_onkai_set:
	inc	si
	lodsb
	xor	ah,ah
	cmp	al,"="
	jz	dos_main
	mov	ah,+1
	cmp	al,"+"
	jz	dos_main
	mov	ah,-1
	cmp	al,"-"
	mov	dx,"{"*256+2
	jnz	error
dos_main:
	lodsb
	cmp	al,"}"
	jz	olc03
	cmp	al," "
	jz	dos_main
	cmp	al,9
	jz	dos_main
	cmp	al,","
	jz	dos_main

	sub	al,"a"
	jc	error
	cmp	al,7
	jnc	error

	xor	bh,bh
	mov	bl,al
	add	bx,offset def_a
	mov	[bx],ah
	jmp	dos_main

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
	or	al,al
	jz	olc03	;0なら無視
	mov	byte ptr es:[di],0deh
	inc	di
	stosb
	cmp	[skip_flag],0
	jz	olc0
	mov	[acc_adr],di
	jmp	olc0
volup5:
	inc	si
	call	lngset
	or	al,al
	jz	olc03	;0なら無視
	mov	byte ptr es:[di],0deh
	inc	di
	stosb
	cmp	[skip_flag],0
	jz	olc0
	mov	[acc_adr],di
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
	call	ongen_sel_vol
	or	al,al
	jz	olc03	;0なら無視
	mov	byte ptr es:[di],0ddh
	inc	di
	stosb
	cmp	[skip_flag],0
	jz	olc0
	mov	[acc_adr],di
	jmp	olc0
voldown5:
	inc	si
	call	lngset
	or	al,al
	jz	olc03	;0なら無視
	mov	byte ptr es:[di],0ddh
	inc	di
	stosb
	cmp	[skip_flag],0
	jz	olc0
	mov	[acc_adr],di
	jmp	olc0

;==============================================================================
;	COMMAND "M"	lfo set
;==============================================================================
lfoset:
ife	efc
	mov	dx,"M"*256+17
	cmp	[part],rhythm
	jz	error		;R
endif
	lodsb
	cmp	al,"X"
	jz	extlfo_set
	cmp	al,"P"
	jz	portaset
	cmp	al,"D"
	jz	depthset
	cmp	al,"W"
	jz	waveset
	cmp	al,"M"
	jz	lfomask_set

	mov	ah,0bfh
	cmp	al,"B"
	jz	lfoset_main
	mov	ah,0f2h
	cmp	al,"A"
	jz	lfoset_main
	dec	si
lfoset_main:
	mov	byte ptr es:[di],ah
	inc	di

	push	ax		;ah(A/B)保存
	mov	dh,"M"
	call	get_clock	;delay
	mov	es:[di],al
	inc	di
	pop	ax
	lodsb
	cmp	al,","
	jnz	delay_only

	call	getnum		;speed
	mov	es:[di],dl
	inc	di
	lodsb
	cmp	al,","
	mov	dx,"M"*256+6
	jnz	error

	call	getnum		;depth1
	mov	es:[di],dl
	inc	di
	lodsb
	cmp	al,","
	mov	dx,"M"*256+6
	jnz	error

	call	getnum		;depth2
	mov	es:[di],dl
	inc	di

	jmp	olc0

delay_only:
	dec	si
	cmp	ah,0f2h
	jnz	delay_only2
	mov	byte ptr es:-2[di],0c2h
	jmp	olc0
delay_only2:
	mov	byte ptr es:-2[di],0b9h
	jmp	olc0

;==============================================================================
;	COMMAND "MX" LFO Speed Extended Mode Set Ver.4.0m～
;==============================================================================
extlfo_set:
	lodsb
	mov	ah,0bbh
	cmp	al,"B"
	jz	extlfo_set_main
	mov	ah,0cah
	cmp	al,"A"
	jz	extlfo_set_main
	dec	si
extlfo_set_main:
	mov	byte ptr es:[di],ah
	inc	di
	call	getnum
	mov	al,dl
	stosb
	jmp	olc0

;==============================================================================
;	COMMAND "MD" [DEPTH SET] for PMD V3.3-
;	MDa,b
;==============================================================================
depthset:
	lodsb
	mov	ah,0bdh
	cmp	al,"B"
	jz	depthset_main
	mov	ah,0d6h
	cmp	al,"A"
	jz	depthset_main
	dec	si
depthset_main:
	mov	byte ptr es:[di],ah
	inc	di
	push	ax
	call	getnum
	mov	byte ptr es:[di],dl
	inc	di
	or	dl,dl			;0の場合は
	jnz	dps_nextparam
	xor	dl,dl
	cmp	byte ptr [si],","	;値２を省略可
	jnz	dps_param2set
	inc	si
	call	getnum
	jmp	dps_param2set
dps_nextparam:
	cmp	byte ptr [si],","
	mov	dx,"M"*256+6
	jnz	error
	inc	si
	call	getnum
	mov	byte ptr es:[di],dl
	inc	di
	pop	ax
	cmp	byte ptr [si],","
	jnz	olc0
	inc	si

;	値３	(counter)	4.7a～
	mov	al,0b7h
	stosb
	push	ax
	call	getnum
	pop	ax
	or	bl,bl
	mov	dx,"M"*256+2
	js	error
	cmp	ah,0d6h		;A?
	jz	mdc_noa
	or	bl,80h
mdc_noa:
	mov	al,bl
	stosb
	jmp	olc0

dps_param2set:
	mov	byte ptr es:[di],dl
	inc	di
	pop	ax
	jmp	olc0

;==============================================================================
;	COMMAND "MP" [PORTAMENT SET] for PMD V2.3-
;	MPa[,b][,c] = Mb,c,a,255*1 def.b=0,c=1
;==============================================================================
portaset:
	lodsb
	mov	ah,0bfh
	cmp	al,"B"
	jz	portaset_main
	mov	ah,0f2h
	cmp	al,"A"
	jz	portaset_main
	dec	si
portaset_main:
	push	ax
	mov	[bend2],0
	mov	[bend3],1
	mov	byte ptr es:[di],ah
	inc	di
	call	getnum
	mov	[bend1],dl
	cmp	byte ptr [si],","
	jnz	bset
	inc	si
	mov	dh,"M"
	call	get_clock
	mov	[bend2],al
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
	pop	dx
	dec	dh		;0f1h or 0beh
	mov	dl,1
	jmp	parset

;==============================================================================
;	COMMAND "MW" [WAVE SET] for PMD V4.0j～
;==============================================================================
waveset:
	lodsb
	mov	ah,0bch
	cmp	al,"B"
	jz	waveset_main
	mov	ah,0cbh
	cmp	al,"A"
	jz	waveset_main
	dec	si
waveset_main:
	push	ax
	call	getnum
	pop	ax
	mov	dh,ah
	jmp	parset

;==============================================================================
;	COMMAND "MM"	LFO Mask for PMD v4.2～
;==============================================================================
lfomask_set:
	lodsb
	mov	ah,0bah
	cmp	al,"B"
	jz	lfomask_set_main
	mov	ah,0c5h
	cmp	al,"A"
	jz	lfomask_set_main
	dec	si
lfomask_set_main:
	push	ax
	call	getnum
	pop	ax
	mov	dh,ah
	jmp	parset

;==============================================================================
;	COMMAND "*"	lfo switch
;==============================================================================
lfoswitch:
	lodsb

	mov	ah,0f1h
ife	efc
	cmp	[part],rhythm
	jz	lfoswitch_noB		;R part
endif
	mov	ah,0beh
lfoswitch_noB:
	cmp	al,"B"
	jz	lfoswitch_main
	mov	ah,0f1h
	cmp	al,"A"
	jz	lfoswitch_main
	dec	si
lfoswitch_main:
	push	ax
	call	lngset
	pop	bx
	mov	dx,"*"*256+6
	jc	error
	mov	ah,al
	mov	al,bh
	stosw

	cmp	byte ptr [si],","
	jnz	olc0
	inc	si
	lodsb
ife	efc
	cmp	[part],rhythm
	mov	dx,"*"*256+17
	jz	error			;R part
endif
	mov	ah,0f1h
	cmp	al,"A"
	jz	lfoswitch_main2
	mov	ah,0beh
	cmp	al,"B"
	jz	lfoswitch_main2
	dec	si
lfoswitch_main2:
	push	ax
	call	lngset
	pop	bx
	mov	dx,"*"*256+6
	jc	error
	cmp	bh,-2[di]	;対象が同じ?
	jnz	lsm2_0
	sub	si,2		;後半が有効
lsm2_0:	mov	ah,al
	mov	al,bh
	stosw
	jmp	olc0

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
	cmp	bx,4
	mov	dx,"p"*256+2
	jnc	error
	mov	byte ptr es:[di],0ech
	inc	di
	mov	es:[di],bl
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

	mov	dx,"\"*256+6
	jc	error
	mov	dl,2
	cmp	bl,64
	jnc	error

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

	mov	dx,"\"*256+6
	jc	error
	mov	dl,2
	cmp	bl,32
	jnc	error

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
	cmp	[skip_flag],0
	jnz	rs_skip
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
	cmp	[prsok],80h	;直前byte = リズム?
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
	mov	[prsok],80h	;直前byte = リズム
	jmp	olc02

rs_skip:
	pop	cx
	cmp	byte ptr [si],"p"
	jnz	olc03
	inc	si
	jmp	olc03

;==============================================================================
;	MML 変数の使用
;==============================================================================
hscom:
	push	es
	mov	ax,hs_seg
	mov	es,ax
	assume	es:hs_seg

	call	lngset
	jc	hscom3
	test	bh,bh
	mov	dx,"!"*256+2
	jnz	error
;;	jnc	hscom2

;;	lodsb
;;	cmp	al,"!"
;;	jz	hscom3

;;	sub	al,64
;;	mov	dx,"!"*256+7
;;	jc	error
;;	cmp	al,64
;;	jnc	error

;;	xor	ah,ah
;;	add	ax,ax
;;	mov	bx,offset hsbuf
;;	add	bx,ax
;;	jmp	hscom_main

hscom2:
	xor	ah,ah
	add	ax,ax
	mov	bx,offset hsbuf2
	add	bx,ax
	jmp	hscom_main

hscom3:
	cmp	byte ptr [si],"!"
	mov	dx,"!"*256+6
	jc	error
	call	search_hs3
	jnc	hscom_main

	test	dx,dx
	jnz	hscom3_small
	mov	dx,"!"*256+27
	jmp	error
hscom3_small:
	mov	bx,dx

hscom_main:
	mov	ax,es:[bx]
	pop	es
	assume	es:m_seg

	test	ax,ax
	mov	dx,"!"*256+27
	jz	error		;定義されてないってばさ

	push	si

	inc	[hsflag]
	mov	si,ax
	call	olc02	;olc0
	dec	[hsflag]

	pop	si
	jmp	olc03

;==============================================================================
;	可変長変数検索
;		in.	ds:si	mml_buffer
;			es	hs_seg
;		out.	bx	hs3_offset
;			ds:si	next mml_buffer
;			cy=1	no_match	dx=near hs3_offset
;==============================================================================
search_hs3:
	push	di
	xor	ax,ax
	mov	dx,ax
	mov	bx,offset hsbuf3
	lea	di,2[bx]

	mov	cx,256
hscom3_loop:
	push	cx
	push	si
	cmp	word ptr es:[bx],0
	jz	hscom3_next

	mov	cx,hs_length-2
	xor	al,al
hscom3_loop2:
	cmp	byte ptr [si],"!"
	jc	hscom3_chk
	cmp	byte ptr es:[di],0
	jz	hscom3_next2	;変数定義側が先に終わった場合は最小確認
	cmpsb
	jnz	hscom3_next
	inc	al
	loop	hscom3_loop2
hscom3_loop3:
	lodsb
	cmp	al,"!"
	jnc	hscom3_loop3
	dec	si
	jmp	hscom3_found

hscom3_chk:
	cmp	byte ptr es:[di],0
	jz	hscom3_found
	jmp	hscom3_next

hscom3_next2:
	cmp	ah,al
	jnc	hscom3_next
	mov	ah,al
	mov	dx,bx
hscom3_next:
	pop	si
	pop	cx
	add	bx,hs_length
	lea	di,2[bx]
	loop	hscom3_loop
	pop	di
	mov	al,ah
	xor	ah,ah
	add	si,ax
	stc
	ret

hscom3_found:
	pop	ax
	pop	cx
	pop	di
	clc
	ret

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
	call	put_part

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
;	Error,Warning時のパート表示
;==============================================================================
put_part:
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
ife	efc
	cmp	[part],rhythm
	jnz	errmes5_put
endif
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
	ret

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
;	環境の検索
;			input	si	環境変数名+"="
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

;==============================================================================
;	Include Files
;==============================================================================
	include	lc.inc
	include	diskpmd.inc
kankyo_seg	dw	?	;環境のセグメント (cs:)

code	ends

;==============================================================================
;	Error Messages
;==============================================================================
err_seg		segment	word	public	'code'

err_table	dw	err00,err01,err02,err03,err04,err05,err06,err07
		dw	err08,err09,err10,err11,err12,err13,err14,err15
		dw	err16,err17,err18,err19,err20,err21,err22,err23
		dw	err24,err25,err26,err27,err28,err29,err30,err31
		dw	err32,err33,err34,err35

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
err33	db	"The number of defined variable-length MML variables has exceeded 256.",cr,lf,eof
err34	db	"Missing distributed chord start symbol {{",cr,lf,eof
err35	db	"The specification in the distributed chord command is incorrect.",cr,lf,eof

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

fnumdat_seg	ends		;2019/12/28 追加

mml_seg	segment	byte	public

;==============================================================================
;	Work Area
;==============================================================================
warning_mes	db	"Warning ",eof
not_ff_mes	db	": The tone file name is not specified.",cr,lf,eof
ff_readerr_mes	db	": The tone file cannot be read.",cr,lf,eof
not_pmd_mes	db	": PMD is not in residentment.",cr,lf,eof
loop_err_mes	db	": Loop end symbol ] is not enough.",cr,lf,eof
mcopt_err_mes	db	": The description in the environment variable MCOPT is incorrect.",13,10,eof

if	efc
usames		db	"Usage:  EFC [/option] filename[.EML] [filename[.FF]]",cr,lf,cr,lf
		db	"Option: /V  compile with tone datas",cr,lf
		db	"        /VW write Voicefile after compile",cr,lf
		db	"        /N  Compile on OPN Mode (Default)",cr,lf
		db	"        /M  Compile on OPM Mode",cr,lf
		db	"        /L  Compile on OPL Mode",cr,lf,eof

titmes		db	" .EML file --> .EFC file Compiler ver ",ver
		db	cr,lf
		db	"		Programmed by M.Kajihara(KAJA) ",date
		db	cr,lf,cr,lf,eof

else

usames		db	"Usage: MC"
if	hyouka
		db	"H"
endif
		db	" [/options] filename[.MML] [filename[.FF]]",cr,lf,cr,lf
		db	"Options: "
ife	hyouka
		db	"/V  	 Compile with tone data, messages and filename",cr,lf
		db	"        /VW Write tone data after compilation",cr,lf
		db	"        "
endif
		db	"/N  		   OPN   Mode (Default)",cr,lf
		db	"        /L  		    OPL   Mode",cr,lf
ife	hyouka
		db	"        /M  			OPM   Mode",cr,lf
		db	"        /T  			TOWNS Mode",cr,lf
		db	"        /P   play after compiling",cr,lf
		db	"        /S  don't write compiled file & play",cr,lf
endif
		db	"        /A  don't set PCMFile before play",cr,lf
		db	"        /O  don't print title messages before playing",cr,lf
		db	"        /C  calculate & print total length of parts",cr,lf
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

mes_ppzfile	db	"PPZFile  : ",eof
mes_ppsfile	db	"PPSFile  : ",eof
mes_pcmfile	db	"PCMFile  : ",eof

; these is going to be searched, do not translate
user_txt	db	"USER=",0
composer_txt	db	"COMPOSER=",0
arranger_txt	db	"ARRANGER=",0
mcopt_txt	db	"MCOPT=",0
; dnt end

ife	tempo_old_flag
tempo		db	0
endif
timerb		db	0
octave		db	4
leng		db	0
zenlen		db	96
deflng		db	24
deflng_k	db	24
calflg		db	0
hsflag		db	0
lopcnt		db	0
volss		db	0
volss2		db	0
octss		db	0
nowvol		db	0
line		dw	0
linehead	dw	0
length_check1	db	0
length_check2	db	0
allloop_flag	db	0
qcommand	dw	0
acc_adr		dw	0
jump_flag	dw	0

def_a		db	0
def_b		db	0
def_c		db	0
def_d		db	0
def_e		db	0
def_f		db	0
def_g		db	0

master_detune	dw	0
detune		dw	0
alldet		dw	0
bend		db	0
pitch		dw	0

bend1		db	0
bend2		db	0
bend3		db	0

transpose	db	0

fm_voldown		db	0
ssg_voldown		db	0
pcm_voldown		db	0
rhythm_voldown		db	0
ppz_voldown		db	0

fm_voldown_flag		db	0
ssg_voldown_flag	db	0
pcm_voldown_flag	db	0
rhythm_voldown_flag	db	0
ppz_voldown_flag	db	0

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
pcm_ex		equ	4

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

prsok		db	0	;直前のbyte
				; bit 1 ･･･ 音長
				; bit 2 ･･･ 加工
				; bit 3 ･･･ +タイ
				; bit 4 ･･･ ポルタ
				; bit 7 ･･･ リズム

prg_flg		db	0
ff_flg		db	0
x68_flg		db	0
towns_flg	db	0
dt2_flg		db	0
opl_flg		db	0
play_flg	db	0
save_flg	db	0
pmd_flg		db	0
ext_detune	db	0
ext_lfo		db	0
ext_env		db	0
memo_flg	db	0
pcm_flg		db	0
lc_flag		db	0
loop_def	db	0

adpcm_flag	db	-1

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
ge_dep_flag	db	0

skip_flag	db	0
tie_flag	db	0
porta_flag	db	0

fm3_partchr1	db	0
fm3_partchr2	db	0
fm3_partchr3	db	0
fm3_ofsadr	dw	0
pcm_partchr1	db	0
pcm_partchr2	db	0
pcm_partchr3	db	0
pcm_partchr4	db	0
pcm_partchr5	db	0
pcm_partchr6	db	0
pcm_partchr7	db	0
pcm_partchr8	db	0
pcm_ofsadr	dw	0

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

					;分散和音ワーク
bunsan_start	dw	?		;開始オフセット
bunsan_count	db	?		;音符数
bunsan_work	db	16 dup(?)	;音階x16
bunsan_length	db	?		;全体の長さ
bunsan_1cnt	db	?		;一音符の長さ
bunsan_tieflag	db	?		;タイフラグ
bunsan_1loop	db	?		;一ループの長さ
bunsan_gate	db	?		;Gate
bunsan_vol	db	?		;音量±

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
ppzfile_adr	dw	?
ppsfile_adr	dw	?
pcmfile_adr	dw	?
title_adr	dw	?
composer_adr	dw	?
arranger_adr	dw	?
memo_adr	dw	128 dup(?)
composer_seg	dw	?
arranger_seg	dw	?

mml_buf		db	61*1024-1 dup (?)		;max 61k(.mml file)
mmlbuf_end	db	?

mml_seg		ends

hs_seg		segment	word	public

hs_length	equ	32
;;hsbuf	db	2*64 dup (?)
hsbuf2	db	2*256 dup (?)
hsbuf3	db	hs_length*256 dup (?)
hsbuf_end	label	byte

hs_seg		ends

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

stack_seg	segment	stack
		db	1024 dup(?)
stack_seg	ends

end	mc

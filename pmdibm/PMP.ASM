;
;	[PMP]	stop / mset / play
;

	.186

@CODE	SEGMENT	PARA	PUBLIC	'@CODE'
	ASSUME	CS:@CODE,DS:@CODE,ES:@CODE

	ORG	100H

START:	JMP	pmp

	INCLUDE	NEWPMD.INC
	INCLUDE	DISKPMD.INC
	INCLUDE	PCMLOAD.INC

pmp:	mov	ax,cs
	mov	es,ax

	push	ds
	push	es
	mov	ds,ax
	print_mes	pmp_title_mes
	call	check_pmd
	jc	not_resident
	mov	ah,10h
	int	60h
	mov	bx,dx
	mov	bx,ds:-2[bx]
	cmp	ds:_pcm_access[bx],0
	jnz	pcm_access_error
	pop	es
	pop	ds

	mov	ax,ds:[2ch]	;環境segment
	mov	cs:[kankyo_seg],ax

	mov	si,80h
	cmp	byte ptr [si],0
	jz	usage

	inc	si
	call	space_cut

;==============================================================================
; 	コマンドラインから /optionの読みとり
;==============================================================================
	mov	cs:[memo_flg],1
	mov	cs:[pcm_flg],1

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
	cmp	al,"P"
	jz	pmd_play
	cmp	al,"S"
	jz	pmd_stop
	cmp	al,"F"
	jz	pmd_fade
	cmp	al,"A"
	jz	reset_pcmflg
	cmp	al,"O"
	jz	reset_memoflg
	jmp	usage

;==============================================================================
;	/A option ... Non read PCM
;==============================================================================
reset_pcmflg:
	mov	cs:[pcm_flg],0
	jmp	option_loop

;==============================================================================
;	/O option ... Non put Title
;==============================================================================
reset_memoflg:
	mov	cs:[memo_flg],0
	jmp	option_loop

;==============================================================================
;	/P opiton ... play
;==============================================================================
pmd_play:
	mov	ax,cs
	mov	ds,ax
	cmp	[memo_flg],0
	jz	pp_non_pcmfile_put
	call	pcmfile_put
pp_non_pcmfile_put:
	cmp	[pcm_flg],0
	jz	pp_non_pcm_read
	call	pcm_read_main
pp_non_pcm_read:
	pmd	mstart
	print_mes	mstart_mes
	cmp	[memo_flg],0
	jz	pp_non_memo_put
	call	memo_put
pp_non_memo_put:
	msdos_exit

;==============================================================================
;	/S opiton ... stop
;==============================================================================
pmd_stop:
	mov	ax,cs
	mov	ds,ax
	pmd	mstop
	print_mes	mstop_mes
	msdos_exit

;==============================================================================
;	/F opiton ... fadeout
;==============================================================================
pmd_fade:
	mov	ax,cs
	mov	ds,ax
	call	get_comline_number
	jnc	fade
	mov	al,16	;Default 16
fade:
	pmd	fout
	print_mes	fade_mes
	msdos_exit

;
;	コマンドラインから数値を読み込む(0-255)
;	IN. DS:SI to COMMAND_LINE
;	OUT.AL	  to NUMBER
;	    CY	  to Error_Flag
;
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

option_exit:
	dec	si
;==============================================================================
; 	コマンドラインから.mのファイル名の取り込み
;==============================================================================

	xor	ah,ah
	mov	di,offset file_name
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

	mov	ax,"M."
	stosw

mfn_ofs_notset:
	xor	al,al
	stosb

;==============================================================================
; 	.mファイルの読み込み
;==============================================================================

	mov	ax,cs
	mov	ds,ax
	mov	dx,offset file_name	;ds:dx = filename
	mov	es,cs:[kankyo_seg]	;es    = 環境segment
	call	opnhnd
	jc	readerror
	mov	ax,cs
	mov	es,ax

	PMD	MSTOP
	PMD	GET_MUSIC_ADR	;DS:DX = address

	mov	cx,-1		;MAX 65535 bytes
	call	redhnd
	pushf
	call	clohnd
	jc	readerror
	popf
	jc	readerror

	jmp	pmd_play

;==============================================================================
;	PPS/PCMファイルの読み込み
;==============================================================================
pcm_read_main:
	mov	al,-1
	pmd	get_memo
	or	dx,dx
	jz	ppsread_exit
	mov	bx,dx
	cmp	byte ptr ds:[bx],0
	jz	ppsread_exit
	mov	ax,bx			;DS:AX=filename
	call	pps_load		;in PCMLOAD.INC
ppsread_exit:

	xor	al,al
	pmd	get_memo
	or	dx,dx
	jz	pcmread_exit
	mov	bx,dx
	cmp	byte ptr ds:[bx],0
	jz	pcmread_exit
	mov	di,offset pcm_data	;ES:DI=pcm_data_work
	mov	ax,bx			;DS:AX=filename
	call	pcm_all_load		;in PCMLOAD.INC
pcmread_exit:
	mov	ax,cs
	mov	ds,ax
	ret

;==============================================================================
;	#PPSFile / #PCMFileの表示
;==============================================================================
pcmfile_put:
	mov	al,-1
	pmd	get_memo
	or	dx,dx
	jz	non_ppsfile
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],0
	jz	non_ppsfile
	print_mes	mes_ppsfile
	call	put_strings
non_ppsfile:

	xor	al,al
	pmd	get_memo
	or	dx,dx
	jz	non_pcmfile
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],0
	jz	non_pcmfile
	print_mes	mes_pcmfile
	call	put_strings
non_pcmfile:
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	ret

;==============================================================================
;	メモ文字列の表示
;==============================================================================
memo_put:
	mov	al,1
	pmd	get_memo
	or	dx,dx
	jz	non_title
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],0
	jz	non_title
	print_mes	mes_title
	call	put_strings
non_title:

	mov	al,2
	pmd	get_memo
	or	dx,dx
	jz	non_composer
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],0
	jz	non_composer
	print_mes	mes_composer
	call	put_strings
non_composer:

	mov	al,3
	pmd	get_memo
	or	dx,dx
	jz	non_arranger
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],0
	jz	non_arranger
	print_mes	mes_arranger
	call	put_strings
non_arranger:

	mov	al,4
memo_loop:
	pmd	get_memo
	or	dx,dx
	jz	non_memo
	push	cs
	push	ds
	pop	es
	pop	ds
	mov	si,dx
	cmp	byte ptr es:[si],"/"
	jz	non_memo
	push	ax
	print_mes	mes_memo
	call	put_strings
	pop	ax
	inc	al
	jmp	memo_loop
non_memo:

	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	ret

;==============================================================================
;	メモ文字列の１行表示
;		Input	si	M_adr
;==============================================================================
put_strings:
	mov	dl,es:[si]
	or	dl,dl
	jz	ps_exit
	mov	ah,2
	int	21h
	inc	si
	jmp	put_strings
ps_exit:
	print_mes	mes_crlf
	ret

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

;==============================================================================
;	usage
;==============================================================================
USAGE:
	MOV	AX,CS
	MOV	DS,AX
	PRINT_MES	pmp_USAGE_MES
	error_EXIT	1

;==============================================================================
;	Not Resident PMD
;==============================================================================
not_resident:
	MOV	AX,CS
	MOV	DS,AX
	PRINT_MES	notres_mes
	error_EXIT	1

;==============================================================================
;	ADPCM access error
;==============================================================================
pcm_access_error:
	MOV	AX,CS
	MOV	DS,AX
	PRINT_MES	pcm_access_mes
	error_EXIT	1

;==============================================================================
;	read error
;==============================================================================
readerror:
	MOV	AX,CS
	MOV	DS,AX
	PRINT_MES	read_error_mes
	error_EXIT	1

;==============================================================================
;	Datas
;==============================================================================

read_error_mes	db	"File not found.",13,10,"$"

mstart_MES	DB	"Starting playing.",13,10,13,10,"$"

Mstop_MES	DB	"Stopped playing."
mes_crlf	db	13,10,"$"

mes_ppsfile	db	"PPSFile  : $"
mes_pcmfile	db	"PCMFile  : $"
mes_title	db	"Title    : $"
mes_composer	db	"Composer : $"
mes_arranger	db	"Arranger : $"
mes_memo	db	"         : $"

fade_MES	DB	"Starting fadeout.",13,10,"$"

notres_mes	db	"PMD is not staying.",13,10,"$"

pcm_access_mes	db	"ADPCM memory is in access.",13,10,"$"

pmp_USAGE_MES	DB	"Usage:  pmp /{P|S|Fn}",13,10
		db	"     or pmp [/{A|O}] filename[.M]",13,10,13,10
		db	"Option: /P   ... (pcmset/)play(/put)",13,10
		db	"        /S   ... stop",13,10
		db	"        /Fn  ... fadeout (n=speed def.=16)",13,10
		db	"        /A   ... not set PPS/PCM file",13,10
		db	"        /O   ... not put Title Messages",13,10
		db	"   filename  ... stop/load(/pcmset)/play(/put)",13,10
		db	"$"

pmp_title_mes	db	"Professional Music Driver [P.M.D.] player for PMD ver.4.4t -",13,10
		db	"                  Programmed by M.Kajihara 2020/04/06",13,10,13,10,"$"

memo_flg	db	0
pcm_flg		db	0

kankyo_seg	dw	?
memo_strings	db	256 dup(?)
FILE_NAME	DB	128 dup(?)
pcm_data	db	32*1024 dup(?)

@CODE	ENDS
END	START

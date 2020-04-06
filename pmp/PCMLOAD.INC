;==============================================================================
;
;	PPS/PCMファイルの読み込み PCMメモリをWORKに使うVersion / Include用
;	PMDPCM.EXE/PMP.COM/MC.EXE 用
;	x8 bit用に変更 /ver.4.4以降
;	.P86処理を追加 /ver.4.5以降
;	PPZ8用処理を追加 / ver.4.8以降
;	PPZ8ADPCM用処理を追加 / ver.4.8k以降
;
;	DISKPMD.INCを予めincludeさせておくこと。
;	cs:[kankyo_seg]に環境のセグメントを入れておくこと。
;
;==============================================================================

message		equ	1		;エラーメッセージを表示するか否か
ppsdrv		equ	64h		;PPSDRVのVector
p86drv		equ	65h		;P86DRVのVector
ppzvec		equ	7fh		;PPZ8のVector

;==============================================================================
;
;	PPZ(PVI/PZI)ファイルの読み込み
;
;		input	DS:AX	filename	(128byte)
;			CL	読ませるバンク	(1=１つ目 2=２つ目 3=両方)
;		output	cy=1	Not Loaded
;				AX=1	ファイルの読み込み失敗
;				AX=2	データ形式が違う
;				AX=3	メモリが確保できない
;				AX=4	EMSハンドルのマッピングができない
;				AX=5	PPZ8が常駐していない
;				CL	エラーの出たPCM番号(0 or 1)
;		break	ax,cx
;==============================================================================
ppz_load:
	push	bx
	push	dx
	push	si
	push	di
	push	bp
	push	ds
	push	es

	mov	cs:[ppz_bank],cl
	mov	cs:[filename_ofs],ax
	mov	ax,ds
	mov	cs:[filename_seg],ax

	call	ppz_load_main

	pop	es
	pop	ds
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	bx
	ret

;==============================================================================
;	PPZ8 読み込み main
;==============================================================================
ppz_load_main:
	call	ppz8_check
	mov	cl,0
	mov	ax,4
	jc	ppz_load_error

;	PCM２つ読み用追加判別処理
	call	read_ppz8
	jc	plm_exit
	mov	ds,cs:[filename_seg]
	lodsb
	cmp	al,","
	jnz	plm_exit2	;PCMは１つだけ
	mov	cs:[filename_ofs],si
	mov	cl,1
	call	read_ppz8
plm_exit:
	ret
plm_exit2:
	xor	ax,ax
	ret

read_ppz8:
;	拡張子判別 (PVI / PZI)
	lds	si,dword ptr cs:[filename_ofs]
	xor	dx,dx
p8_extcheck_loop:
	lodsb
	call	sjis_check	;in DISKPMD.INC
	jnc	p8_extcheck_nonsjis
	inc	si		;2byte目を飛ばす
	jmp	p8_extcheck_loop
p8_extcheck_nonsjis:
	or	al,al
	jz	p8_extcheck_exit
	cmp	al,","
	jz	p8_extcheck_exit
	cmp	al,"."
	jnz	p8_extcheck_loop
	mov	dx,si
	jmp	p8_extcheck_loop
p8_extcheck_exit:

	dec	si		;si= 00h or "," の位置
	shr	cs:[ppz_bank],1
	jnc	p8_load_skip	;load skip

	mov	ch,1		;PZI load
	test	dx,dx
	jz	p8_load_main	;拡張子省略時 = PZI

	mov	bx,dx
	mov	al,1[bx]
	and	al,11011111b	;小文字＞大文字変換
	cmp	al,"V"
	jnz	p8_load_main
	dec	ch		;PVI load (ch=0)

;	PVI / PZI 読み込み
p8_load_main:
	push	ds:[si]
	mov	byte ptr [si],0		; "," なら 00h に一時的に書き換え
	mov	ax,0300h
	mov	dx,cs:[filename_ofs]
	int	ppzvec			; pcm load
	jnc	p8_load_exit
	cmp	ax,2
	cmc
	jc	p8_load_exit		; file not found or 形式が違うなら
	xor	ch,1			; もう片方の形式も
	mov	ax,0300h
	int	ppzvec			; pcm loadを試してみる
p8_load_exit:
	pop	ds:[si]
	jc	ppz_load_error
p8_load_skip:
	xor	ax,ax
	ret

;	Error処理
ppz_load_error:
	inc	ax
if	message
	mov	bx,ax
	mov	dx,offset exit1z_mes
	dec	bx
	jz	ppz_error_main

	mov	dx,offset exit2z_mes
	dec	bx
	jz	ppz_error_main

	mov	dx,offset exit3z_mes
	dec	bx
	jz	ppz_error_main

	mov	dx,offset exit4z_mes
	dec	bx
	jz	ppz_error_main

	mov	dx,offset exit5z_mes
	jmp	ppz_error_main2

ppz_error_main:
	mov	al,cl
	add	al,"1"
	mov	cs:[banknum],al	;Bank
	push	dx
	mov	dx,offset ppzbank_mes
	call	ppz_error_main2
	pop	dx
ppz_error_main2:
	push	ds
	push	ax
	mov	ax,cs
	mov	ds,ax
	mov	ah,9
	int	21h
	pop	ax
	pop	ds
endif
	stc
	ret

;	PPZ8常駐check
ppz8_check:
	xor	bx,bx
	mov	es,bx
	les	bx,es:[ppzvec*4]
	cmp	word ptr es:2[bx],"PP"
	jnz	no_ppz
	cmp	word ptr es:4[bx],"8Z"
	jnz	no_ppz
	cmp	byte ptr es:6[bx],0
	jnz	no_ppz
	clc
	ret
no_ppz:	stc
	ret

;==============================================================================
;
;	PCM(PPC/P86)ファイルの読み込み
;		P86DRV.COMが常駐していれば .P86を、
;		そうでない場合は .PPCを読む。
;		PMDPPZEが常駐している場合は無条件にPVIをPPZ8に読み込む。
;
;		input	DS:AX	filename	(128byte)
;			ES:DI	pcm_work	(32KB,P86の場合は必要無し)
;		output	cy=1	Not Loaded
;			PMDB2/PMD86の場合
;				AX=1	SPB/ADPCM-RAMかPMDB2がない
;					86B/P86DRV   かPMD86がない
;				AX=2	ファイルがない
;				AX=3	ファイルがPMDのPCMデータではない
;				AX=4	SPB/既に読み込んであるのと同じだった
;					86B/容量OVER
;				AX=5	ファイルが読めない
;				AX=6	PCMメモリがアクセス中だった
;			PMDPPZEの場合
;				AX=1	ファイルの読み込み失敗
;				AX=2	データ形式が違う
;				AX=3	メモリが確保できない
;				AX=4	EMSハンドルのマッピングができない
;				AX=5	PPZ8が常駐していない
;
;	.PPC format:
;		WORK=PMD内PCMWORK , DATA=PCMRAM先頭のWORK , FILE=PCMFILE
;					 123456789012345678901234567890
;		DATA/FILEのみ		"ADPCM DATA for  PMD ver.4.4-  "30bytes
;		WORK/DATA/FILE		1Word		Next START Address
;					2Word*256	START/STOP
;		WORK/DATAのみ		128bytes	FILENAME
;		DATAのみ		32bytes		予備
;
;		PCMRAM_Work		=00000H～00025H
;		PCMRAM_Main_data	=00026H～01FFFH
;
;	.P86 format:
;		"PCM86 DATA",0ah,0	12 byte
;		P86DRVのversion		1  byte
;		全体のサイズ		3  byte
;		音色table		start(3),size(3) * 256 (1536) bytes
;		音色データ		可変
;
;==============================================================================
pcm_all_load	proc

	assume	ds:nothing,es:nothing

	cld
	push	ds
	push	es
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp

	mov	cs:[filename_ofs],ax
	mov	ax,ds
	mov	cs:[filename_seg],ax
	mov	cs:[pcmdata_ofs],di
	mov	ax,es
	mov	cs:[pcmdata_seg],ax
	mov	ah,0eh		;GET_PCM_ADR
	int	60h		;DS:DX=PCMワーク
	mov	cs:[pcmwork_ofs],dx
	mov	ax,ds
	mov	cs:[pcmwork_seg],ax

	call	all_load

	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	es
	pop	ds
	ret

pcm_all_load	endp

;==============================================================================
;
;	PPSファイルの読み込み
;
;		input	DS:AX	filename	(128byte)
;		output	cy=1	AX=1	PPSDRVが常駐していない
;				AX=2	ファイルが無い
;				AX=3	PPSDRVの容量をオーバーした
;				AX=5	ファイルが読めない
;
;	PPSDATA構造
;			2Word*14	Start address/Length
;			以降		PPS Data
;
;==============================================================================
pps_load	proc
	assume	ds:nothing,es:nothing
	cld
	push	ds
	push	es
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	bp

	mov	cs:[filename_ofs],ax
	mov	ax,ds
	mov	cs:[filename_seg],ax

	call	ppsdrv_check
	jc	not_load

pps_load_exec:
	mov	ah,4
	int	ppsdrv
	mov	cs:[pcmdata_ofs],dx
	mov	ax,ds
	mov	cs:[pcmdata_seg],ax
	mov	cs:[pcmdata_size],cx

	call	pps_load_main

not_load:
	pop	bp
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	es
	pop	ds
	ret

pps_load	endp

;==============================================================================
;	pps load
;		in	cs:[filename_ofs/seg]	Filename
;			cs:[pcmdata_ofs/seg]	PPSData位置
;			cs:[pcmdata_size]	PPSData容量
;==============================================================================
pps_load_main	proc
	call	filename_set

;-----------------------------------------------------------------------------
;	File Read
;-----------------------------------------------------------------------------
	mov	bx,offset pps_ext
	call	ext_set		;拡張子 "PPS"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	es,[kankyo_seg]
	call	opnhnd		;Open
	jnc	exec_ppsload

	lds	dx,dword ptr cs:[filename_ofs]
	mov	es,cs:[kankyo_seg]
	call	opnhnd		;Open
	jc	allload_exit2p	;Fileが無い

exec_ppsload:
	lds	dx,dword ptr cs:[pcmdata_ofs]
	mov	cx,cs:[pcmdata_size]
	inc	cx		;1byte余計に読む
	push	cx
	call	redhnd
	pop	cx
	jc	allload_exit5p_close	;fileが読めない
	cmp	ax,cx
	jz	allload_exit3p_close	;容量オーバー

	call	clohnd
	xor	ax,ax
	ret

pps_load_main	endp

;==============================================================================
;	.PPC/.P86 一括load
;		in	cs:[filename_ofs/seg]	Filename
;			cs:[pcmdata_ofs/seg]	PCMData loadarea
;			cs:[pcmwork_ofs/seg]	PMD内PCMwork
;==============================================================================
all_load	proc
;-----------------------------------------------------------------------------
;	読み込むのは.P86か.PPCかどうかを判別
;-----------------------------------------------------------------------------
	call	check_p86drv
	jnc	p86_load
	mov	ah,09h
	int	60h		;board check
	cmp	al,1		;pmdb2
	jz	allload_main1
	cmp	al,4		;pmdppz
	jz	allload_main1
	cmp	al,5		;pmdppze
	jz	allload_ppze
	jmp	allload_exit1

;-----------------------------------------------------------------------------
;	.PPC read Main
;-----------------------------------------------------------------------------
allload_main1:
	call	check_pmdb2
	jc	allload_exit1
	call	filename_set

;-----------------------------------------------------------------------------
;	FileをPMDのワークにヘッダだけ読みこむ
;-----------------------------------------------------------------------------
	mov	bx,offset ppc_ext
	call	ext_set		;拡張子 "PPC"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	es,[kankyo_seg]
	call	opnhnd		;Open
	jnc	exec_ppcload

	lds	dx,dword ptr cs:[filename_ofs]
	mov	es,cs:[kankyo_seg]
	call	opnhnd		;Open
	jnc	exec_ppcload

	mov	bx,offset p86_ext
	call	ext_set		;拡張子 "P86"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	es,[kankyo_seg]
	call	opnhnd		;Open
	jc	allload_exit2
exec_ppcload:
	lds	dx,dword ptr cs:[pcmdata_ofs]
	mov	cx,30		;識別文字列長
	call	redhnd
	jc	allload_exit5_close
	cmp	ax,30		;Headerの長さ=読み込んだ長さか？
	jnz	allload_exit3_close

	lds	bx,dword ptr cs:[pcmdata_ofs]
	cmp	word ptr 0[bx],"VP"	;PV
	jnz	not_pvi
	cmp	word ptr 2[bx],"2I"	;I2
	jnz	not_pvi
	cmp	byte ptr 10[bx],02h	;RAM Type 8bit
	jz	pvi_load
not_pvi:
	cmp	word ptr 0[bx],"DA"	;AD
	jnz	allload_exit3_close		;PMDのPCMデータではない
	cmp	word ptr 2[bx],"CP"	;PC
	jnz	allload_exit3_close		;PMDのPCMデータではない
	cmp	word ptr 4[bx]," M"	;M 
	jnz	allload_exit3_close		;PMDのPCMデータではない

	lds	dx,dword ptr cs:[pcmwork_ofs]
	mov	cx,4*256+2	;Headerの長さ (filenameはない)
	call	redhnd		;Read
	jc	allload_exit5_close
	cmp	ax,4*256+2	;Headerの長さ=読み込んだ長さか？
	jnz	allload_exit3_close

;-----------------------------------------------------------------------------
;	PMDのワークにFilenameを書く
;-----------------------------------------------------------------------------
ppc_load_main:
	call	write_filename_to_pmdwork

;-----------------------------------------------------------------------------
;	PCMRAMのヘッダを読む
;-----------------------------------------------------------------------------
	cmp	cs:[retry_flag],0
	jnz	write_pcm_main		;無条件
	mov	cs:[pcmstart],0
	mov	cs:[pcmstop],25h	;read 25h*32 = 1184(32+256*4+128) bytes
	call	pcmread
	jc	allload_exit6_close

;-----------------------------------------------------------------------------
;	PMDのワークとPCMRAMのヘッダを比較
;-----------------------------------------------------------------------------
	lds	si,dword ptr cs:[pcmdata_ofs]
	les	di,dword ptr cs:[pcmwork_ofs]
	add	si,30		;"ADPCM～"ヘッダを飛ばす
	mov	cx,+(4*256+128+2)/2
rep	cmpsw
	jz	allload_exit4_close	;一致した

;-----------------------------------------------------------------------------
;	PMDのワークをPCMRAM頭に書き込む
;-----------------------------------------------------------------------------
write_pcm_main:
	mov	ax,cs
	mov	ds,ax
	mov	si,offset adpcm_header
	les	di,dword ptr cs:[pcmdata_ofs]
	mov	cx,30/2		;"ADPCM～"ヘッダを書き込み
rep	movsw
	lds	si,dword ptr cs:[pcmwork_ofs]
	mov	cx,+(4*256+128+2)/2
rep	movsw
	mov	cs:[pcmstart],0
	mov	cs:[pcmstop],25h
	call	pcmstore

;-----------------------------------------------------------------------------
;	PCMDATAをPCMRAMに書き込む
;	8000hずつ読み込みながら定義
;-----------------------------------------------------------------------------
if	message
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset allload_mes
	mov	ah,09h
	int	21h		;"ＰＣＭ定義中"の表示
endif
	lds	bx,dword ptr cs:[pcmwork_ofs]
	mov	ax,ds:[bx]	;AX=PCM Next Start Address
	sub	ax,26h		;実際にこれから転送するデータ量に変換

	mov	cs:[pcmstart],26h
	mov	cs:[pcmstop],426h	;400h*32=8000h 一括
allload_loop:
	cmp	ax,401h
	jc	allload_last
	sub	ax,400h

	mov	bp,ax	;Push
	lds	dx,dword ptr cs:[pcmdata_ofs]
	mov	cx,8000h
	call	redhnd		;DISK Read
	jc	allload_exit5_close
	cmp	ax,8000h
	jnz	allload_exit3_close
	call	pcmstore	;PCM Store
	add	cs:[pcmstart],400h
	add	cs:[pcmstop],400h
	mov	ax,bp	;Pop
	jmp	allload_loop

allload_last:
	or	ax,ax
	jz	allload_justend
	mov	bp,ax	;Push
	add	ax,cs:[pcmstart]
	mov	cs:[pcmstop],ax
	lds	dx,dword ptr cs:[pcmdata_ofs]
	mov	cx,8000h
	call	redhnd		;DISK Read
	jc	allload_exit5_close
	mov	bx,bp	;Pop
	add	bx,bx
	add	bx,bx
	add	bx,bx
	add	bx,bx
	add	bx,bx
	cmp	ax,bx
	pushf
	call	pcmstore	;PCM Store
	popf
	jc	allload_exit3_close
allload_justend:
	call	clohnd		;FILE Close

;-----------------------------------------------------------------------------
;	終了
;-----------------------------------------------------------------------------
	xor	ax,ax
	ret

all_load	endp

;==============================================================================
;	.PVI loading
;==============================================================================
pvi_load:
;-----------------------------------------------------------------------------
;	ヘッダ/音色tableの残りを読み込み
;-----------------------------------------------------------------------------
	lds	dx,dword ptr cs:[pcmdata_ofs]
	add	dx,30
	mov	cx,128*4+16-30	;Header 残り
	call	redhnd
	jc	allload_exit5_close
	cmp	ax,128*4+16-30
	jnz	allload_exit3_close

;-----------------------------------------------------------------------------
;	pviの音色情報からpmdへ転送
;-----------------------------------------------------------------------------
	lds	si,dword ptr cs:[pcmdata_ofs]
	add	si,16
	les	di,dword ptr cs:[pcmwork_ofs]
	add	di,2
	xor	bx,bx
	mov	cx,128
	mov	dx,26h
tableset_loop:
	lodsw
	add	ax,dx
	stosw
	lodsw
	or	ax,ax
	jnz	not_null_pcm
	sub	word ptr es:-2[di],dx
	sub	ax,dx
not_null_pcm:
	add	ax,dx
	stosw
	cmp	bx,ax
	jnc	not_set_max
	mov	bx,ax
	inc	bx
not_set_max:
	loop	tableset_loop
	xor	ax,ax
	mov	cx,128*2
rep	stosw		;残り128個は未定義
	mov	di,cs:[pcmwork_ofs]
	mov	es:[di],bx

	jmp	ppc_load_main	;あとはppcと同じ

;==============================================================================
;	PMDPPZEの ADPCM用 load
;==============================================================================
allload_ppze:
	call	ppz8_check
	mov	ax,4
	mov	cl,0
	jc	ppz_load_error	;PPZ8非常駐

	call	filename_set
	mov	bx,offset pvi_ext
	call	ext_set		;拡張子 "PVI"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	cx,0001h	;pvi,buffer 1
	mov	ax,0300h
	int	ppzvec
	jnc	ppze_load_exit
	cmp	ax,2
	jnc	ppz_load_error

	mov	bx,offset pzi_ext
	call	ext_set		;拡張子 "PZI"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	cx,0101h	;pzi,buffer 1
	mov	ax,0300h
	int	ppzvec
	jc	ppz_load_error
ppze_load_exit:
	xor	ax,ax
	ret			;正常終了

;==============================================================================
;	P86 data 一括load
;		in	cs:[filename_ofs/seg]	Filename
;==============================================================================
p86_load	proc
;-----------------------------------------------------------------------------
;	P86drvのcheck
;-----------------------------------------------------------------------------
	mov	ah,-2
	int	p86drv		;INT65H 使用中?
	or	al,al
	jnz	allload_exit6
	mov	ah,-1
	int	p86drv
	cmp	al,10h		;ver.1.0以前?
	jc	allload_exit6

	call	filename_set

;-----------------------------------------------------------------------------
;	P86Data,Size確認
;-----------------------------------------------------------------------------
	mov	bx,offset p86_ext
	call	ext_set		;拡張子 "P86"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	es,[kankyo_seg]
	mov	ah,6
	int	p86drv		;Read
	test	al,al
	jz	p86load_complete

	lds	dx,dword ptr cs:[filename_ofs]
	mov	es,cs:[kankyo_seg]
	mov	ah,6
	int	p86drv		;Read
	test	al,al
	jz	p86load_complete

	mov	bx,offset ppc_ext
	call	ext_set		;拡張子 "PPC"に変更
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset filename_buf
	mov	es,[kankyo_seg]
	mov	ah,6
	int	p86drv		;Read
	test	al,al
	jnz	p86load_error
p86load_complete:
	xor	ax,ax		;正常終了
	ret

p86load_error:
	dec	al
	jz	allload_exit1	;No Resident PMD86
	dec	al
	jz	allload_exit2	;File not found
	dec	al
	jz	allload_exit4pp	;Size Over
	dec	al
	jz	allload_exit3	;Type Missmatch
	dec	al
	jz	allload_exit5	;Read Error
	jmp	allload_exit1	;Other Errors

p86_load	endp

;-----------------------------------------------------------------------------
;	エラーリターン
;-----------------------------------------------------------------------------
allload_exit1:
if	message
	mov	dx,offset exit1_mes
endif
	mov	ax,1	;PCMが定義出来ません。
	jmp	error_exec

allload_exit1p:
if	message
	mov	dx,offset exit1p_mes
endif
	mov	ax,1	;PPSDRVが常駐してない
	jmp	error_exec

allload_exit2:
if	message
	mov	dx,offset exit2_mes
endif
	mov	ax,2	;PCMファイルがない
	jmp	error_exec

allload_exit2p:
if	message
	mov	dx,offset exit2p_mes
endif
	mov	ax,2	;PPSファイルがない
	jmp	error_exec

allload_exit3_close:
	call	clohnd
allload_exit3:
if	message
	mov	dx,offset exit3_mes
endif
	mov	ax,3	;ファイルがPMDのPCMではない
	jmp	error_exec

allload_exit3p_close:
	call	clohnd
if	message
	mov	dx,offset exit3p_mes
endif
	mov	ax,3	;PPSデータ容量オーバー
	jmp	error_exec

allload_exit4_close:
	call	clohnd
if	message
	mov	dx,offset exit4_mes
endif
	mov	ax,4	;データが一致した
	jmp	error_exec

allload_exit4pp:
if	message
	mov	dx,offset exit4pp_mes
endif
	mov	ax,4	;P86容量が足りない
	jmp	error_exec

allload_exit5_close:
	call	clohnd
allload_exit5:
if	message
	mov	dx,offset exit5_mes
endif
	mov	ax,5	;PCMファイルが読めない
	jmp	error_exec

allload_exit5p_close:
	call	clohnd
if	message
	mov	dx,offset exit5p_mes
endif
	mov	ax,5	;PPSファイルが読めない
	jmp	error_exec

allload_exit6_close:
	call	clohnd
allload_exit6:
if	message
	mov	dx,offset exit6_mes
endif
	mov	ax,6	;PCMメモリアクセス中
	jmp	error_exec

error_exec:
if	message
	push	ax
	mov	ax,cs
	mov	ds,ax
	mov	ah,09h
	int	21h
	pop	ax
endif
	stc
	ret

;==============================================================================
;	PMDB2＆ADPCMのCheck
;		output	cy	PMDB2又はADPCMがない
;==============================================================================
check_pmdb2	proc
;-----------------------------------------------------------------------------
;	PMDB2＆ADPCMの搭載CHECK
;-----------------------------------------------------------------------------
	mov	ah,10h
	int	60h		;get_workadr in DS:DX
	mov	bx,dx
	mov	bx,-2[bx]	;ds:bx = open_work
	cmp	_pcm_gs_flag[bx],0
	jnz	cpb_stc_ret	;ERROR Return
	mov	ax,_fm2_port1[bx]
	mov	cs:[port46],ax
	mov	ax,_fm2_port2[bx]
	mov	cs:[port47],ax
	clc
	ret
cpb_stc_ret:
	stc
	ret
check_pmdb2	endp

;==============================================================================
;	P86DRVの常駐Check
;		output	cy	P86DRVがない
;==============================================================================
check_p86drv	proc
	push	es
	push	ax
	xor	ax,ax
	mov	es,ax
	les	bx,es:[p86drv*4]
	cmp	word ptr es:2[bx],"8P"
	jnz	p86drv_not_found
	cmp	byte ptr es:4[bx],"6"
	jnz	p86drv_not_found
	pop	ax
	pop	es
	clc
	ret
p86drv_not_found:
	pop	ax
	pop	es
	stc
	ret

check_p86drv	endp

;==============================================================================
;	PPSDRV 常駐check
;			output	cy=1	常駐してない
;==============================================================================
ppsdrv_check	proc
	xor	ax,ax
	mov	es,ax
	les	bx,es:[ppsdrv*4]
	cmp	word ptr es:2[bx],"MP"
	jnz	allload_exit1p
	cmp	byte ptr es:4[bx],"P"
	jnz	allload_exit1p
	clc
	ret
ppsdrv_check	endp

;==============================================================================
;	Filenameの大文字化＆パス名回避処理
;==============================================================================
filename_set	proc
;-----------------------------------------------------------------------------
;	Filenameを小文字から大文字に変換(SHIFTJIS回避付き)
;-----------------------------------------------------------------------------
	lds	si,dword ptr cs:[filename_ofs]
exbig_loop:
	lodsb
	call	sjis_check	;in DISKPMD.INC
	jnc	exbig_nonsjis
	inc	si		;2byte目を飛ばす
	jmp	exbig_loop
exbig_nonsjis:
	or	al,al
	jz	exbig_exit
	cmp	al,"a"
	jc	exbig_loop
	cmp	al,"z"+1
	jnc	exbig_loop
	and	al,11011111b	;小文字＞大文字変換
	mov	ds:-1[si],al	;して書込み
	jmp	exbig_loop
exbig_exit:

;-----------------------------------------------------------------------------
;	Filename中のパス名を抜いたfilename_ofs2を設定(File名比較用)
;-----------------------------------------------------------------------------
	lds	si,dword ptr cs:[filename_ofs]
	mov	bx,si
yencheck_loop:
	lodsb
	call	sjis_check	;in DISKPMD.INC
	jnc	yencheck_nonsjis
	inc	si	;2byte目を飛ばす
	jmp	yencheck_loop
yencheck_nonsjis:
	or	al,al
	jz	yencheck_exit
	cmp	al,"\"
	jnz	yencheck_loop
	mov	bx,si
	jmp	yencheck_loop
yencheck_exit:
	mov	cs:[filename_ofs2],bx
	mov	ax,ds
	mov	cs:[filename_seg2],ax	;セグメントはfilename_segと一緒

	ret

filename_set	endp

;==============================================================================
;	PMDのワークにFilenameを書く
;==============================================================================
write_filename_to_pmdwork	proc
	lds	si,dword ptr cs:[filename_ofs2]
	les	di,dword ptr cs:[pcmwork_ofs]
	add	di,4*256+2	;ES:DI = PMD内PCM_WORKのFilename格納位置
	mov	cx,128		;byte数
write_filename_loop:
	dec	cx
	movsb
	cmp	byte ptr -1[si],0
	jnz	write_filename_loop
	xor	al,al
rep	stosb			;残りを０で埋める
	ret
write_filename_to_pmdwork	endp

;==============================================================================
;	ＰＣＭメモリへメインメモリからデータを送る (x8,高速/低速選択版)
;
;	INPUTS 	.. cs:[pcmstart]   	to Start Address
;		.. cs:[pcmstop]    	to Stop  Address
;		.. cs:[pcmdata_ofs/seg]	to PCMData_Buffer
;==============================================================================
pcmstore	proc
	call	key_check_reset

	mov	dx,0001h
	call	out46

	mov	dx,1017h	;brdy以外はマスク(=timer割り込みは掛からない)
	call	out46
	mov	dx,1080h
	call	out46
	mov	dx,0060h
	call	out46
	mov	dx,0102h	;x8
	call	out46

	mov	dx,0cffh
	call	out46
	inc	dh
	call	out46

	mov	bx,cs:[pcmstart]
	mov	dh,002h
	mov	dl,bl
	call	out46
	inc	dh
	mov	dl,bh
	call	out46

	mov	dx,04ffh
	call	out46
	inc	dh
	call	out46

	lds	si,dword ptr cs:[pcmdata_ofs]
	mov	cx,cs:[pcmstop]
	sub	cx,cs:[pcmstart]
	add	cx,cx
	add	cx,cx
	add	cx,cx
	add	cx,cx
	add	cx,cx

	mov	dx,cs:[port46]
	mov	bx,cs:[port47]

	cmp	cs:[adpcm_wait],0
	jz	fast_store
	cmp	cs:[adpcm_wait],1
	jz	middle_store

;------------------------------------------------------------------------------
;	低速定義
;------------------------------------------------------------------------------
slow_store:
	cli
o4600z:	in	al,dx
	or	al,al
	js	o4600z

	mov	al,8	;PCMDAT	reg.
	out	dx,al
	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx

	xchg	bx,dx
	lodsb
	out	dx,al	;OUT	data
	sti
	xchg	dx,bx
o4601z:
	in	al,dx
	test	al,8	;BRDY	check
	jz	o4601z
o4601zb:
	test	al,al	;BUSY	check
	jns	o4601zc
	in	al,dx
	jmp	o4601zb
o4601zc:

	mov	al,10h
	cli
	out	dx,al
	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx
	xchg	dx,bx
	mov	al,80h
	out	dx,al	;BRDY	reset
	sti
	xchg	dx,bx

	loop	slow_store

	jmp	pcmst_exit

;------------------------------------------------------------------------------
;	中速定義
;------------------------------------------------------------------------------
middle_store:
	call	cli_sub
o4600y:	in	al,dx
	or	al,al
	js	o4600y
	mov	al,8	;PCMDAT	reg.
	out	dx,al

middle_store_loop:
	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx

	xchg	bx,dx
	lodsb
	out	dx,al	;OUT	data
	xchg	bx,dx
o4601y:
	in	al,dx
	test	al,8	;BRDY	check
	jz	o4601y

	loop	middle_store_loop
	call	sti_sub

	jmp	pcmst_exit

;------------------------------------------------------------------------------
;	高速定義
;------------------------------------------------------------------------------
fast_store:
	call	cli_sub
o4600x:	in	al,dx
	or	al,al
	js	o4600x
	mov	al,8	;PCMDAT	reg.
	out	dx,al
	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx
	xchg	bx,dx

fast_store_loop:
	lodsb
	out	dx,al	;OUT	data
	xchg	bx,dx
o4601x:
	in	al,dx
	test	al,8	;BRDY	check
	jz	o4601x

	xchg	dx,bx
	loop	fast_store_loop
	call	sti_sub

pcmst_exit:
	mov	dx,1000h
	call	out46
	mov	dx,1080h
	call	out46
	mov	dx,0001h
	call	out46

	call	key_check_set
	ret

;------------------------------------------------------------------------------
;	RS-232C以外は割り込みを禁止する
;	(FM音源LSI の ADDRESSの変更をさせない為)
;------------------------------------------------------------------------------
cli_sub:
	push	ax
	push	dx
	cli
	mov	dx,cs:[mmask_port]
	in	al,dx
	mov	cs:[mmask_push],al
	or	al,11101111b		;RSのみ変化させない
	out	dx,al
	sti
	pop	dx
	pop	ax
	ret

;------------------------------------------------------------------------------
;	上のsubroutineで禁止した割り込みを元に戻す
;------------------------------------------------------------------------------
sti_sub:
	push	ax
	push	dx
	cli
	mov	dx,cs:[mmask_port]
	mov	al,cs:[mmask_push]
	out	dx,al
	sti
	pop	dx
	pop	ax
	ret

pcmstore	endp

;==============================================================================
;	ＰＣＭメモリからメインメモリへのデータ取り込み
;
;	Inputs	.. cs:[pcmstart]  	to Start Address
;		.. cs:[pcmstop]   	to Stop  Address
;		.. cs:[pcmdata_ofs/seg]	to PCMDATA_Buffer
;==============================================================================
pcmread	proc
	call	key_check_reset
	jnc	pcmread_exec
	ret

pcmread_exec:
	mov	dx,0001h
	call	out46

	mov	dx,1000h
	call	out46
	mov	dx,1080h
	call	out46
	mov	dx,0020h
	call	out46
	mov	dx,0102h	;x8
	call	out46
	mov	dx,0cffh
	call	out46
	inc	dh
	call	out46
	mov	bx,cs:[pcmstart]
	mov	dh,002h
	mov	dl,bl
	call	out46
	mov	dh,003h
	mov	dl,bh
	call	out46
	mov	dx,04ffh
	call	out46
	inc	dh
	call	out46

	call	pget
	call	pget

	mov	cx,cs:[pcmstop]
	sub	cx,cs:[pcmstart]
	add	cx,cx
	add	cx,cx
	add	cx,cx
	add	cx,cx
	add	cx,cx

	les	di,dword ptr cs:[pcmdata_ofs]

pcr00:	mov	dx,cs:[port46]
	cli
pcr00b:	in	al,dx
	test	al,al
	js	pcr00b
	mov	al,8
	out	dx,al

pcr01:	in	al,dx
	test	al,00001000b
	jz	pcr01

pcr02:	in	al,dx
	or	al,al
	js	pcr02

	mov	dx,cs:[port47]
	in	al,dx
	sti
	stosb

	mov	dx,1080h
	call	out46

	loop	pcr00

	mov	dx,0001h
	call	out46

	call	key_check_set
	ret

;==============================================================================
;	無駄読み用
;==============================================================================
pget:	cli
	mov	dx,cs:[port46]
pg00:	in	al,dx
	test	al,al
	js	pg00
	mov	al,008h
	out	dx,al

	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx

	mov	dx,cs:[port47]
	in	al,dx
	sti
	mov	dx,1080h
	call	out46
	ret

pcmread	endp

;==============================================================================
;	ＯＰＮＡ裏ポートへのデータの書き込み
;
;	Inputs	.. dh to Register
;		.. dl to Data
;==============================================================================
out46	proc
	push	dx
	push	bx
	mov	bx,dx
	mov	dx,cs:[port46]
o4600:	in	al,dx
	or	al,al
	js	o4600
	mov	al,bh
	cli
	out	dx,al
	push	cx
	mov	cx,cs:[wait_clock]
	loop	$
	pop	cx
	mov	dx,cs:[port47]
	mov	al,bl
	out	dx,al
	sti
	pop	bx
	pop	dx
	ret

out46	endp

;==============================================================================
;	PMDの ESC/GRPH入力を効かなくする
;	その他必要なデータをpmdのsegmentから読み取る
;		out	cy	acccess flag on
;==============================================================================
key_check_reset:
	push	ds
	push	ax
	push	bx
	push	dx
	push	di
	mov	ah,10h
	int	60h
	mov	bx,dx
	mov	di,18[bx]
	mov	bx,-2[bx]
	mov	ax,_wait_clock[bx]
	mov	cs:[wait_clock],ax	;get wait_clock
	mov	al,_adpcm_wait[bx]
	mov	cs:[adpcm_wait],al	;get adpcm_wait
	mov	cs:[mmask_port],02h	;master_mask (98)
	cmp	word ptr ds:[84h],"AV"
	jnz	kcr_notva
	mov	cs:[mmask_port],18ah	;master_mask (VA)
kcr_notva:
	cmp	_pcm_access[bx],0	;cf=0
	jnz	kcr_exit
	mov	al,_key_check[bx]
	mov	cs:[key_check_push],al
	mov	_key_check[bx],0
	mov	_pcm_access[bx],1
	mov	_pcmflag[bx],0		;追加 (効果音対策)
	mov	_pcm_effec_num[bx],255	;//
	and	_partmask[di],0fdh	;// bit1をclear
	stc				;cf=1
kcr_exit:
	cmc
	pop	di
	pop	dx
	pop	bx
	pop	ax
	pop	ds
	ret

;==============================================================================
;	PMDの ESC/GRPH入力を元に戻す
;	PCMメモリアクセスフラグをoff
;==============================================================================
key_check_set:
	push	ds
	push	ax
	push	bx
	push	dx
	mov	ah,10h
	int	60h
	mov	bx,dx
	mov	bx,-2[bx]
	mov	al,cs:[key_check_push]
	mov	_key_check[bx],al
	mov	_pcm_access[bx],0
	pop	dx
	pop	bx
	pop	ax
	pop	ds
	ret

;==============================================================================
;	拡張子を設定
;		in.	cs:[filename_ofs]	filename
;			cs:bx			拡張子(3文字)
;		out.	cs:filename_buf		拡張子を変更したfile名
;==============================================================================
ext_set:
	mov	ax,cs
	mov	es,ax				;es:bx = 拡張子
	lds	si,dword ptr cs:[filename_ofs]	;ds:si = file名先頭
	mov	di,offset filename_buf		;es:di = filename_buf先頭

;-----------------------------------------------------------------------------
;	Filename中の拡張子の場所を探す & filename_bufに転送
;-----------------------------------------------------------------------------
	xor	dx,dx
extcheck_loop:
	lodsb
	stosb
	call	sjis_check	;in DISKPMD.INC
	jnc	extcheck_nonsjis
	movsb			;2byte目を飛ばす
	jmp	extcheck_loop
extcheck_nonsjis:
	or	al,al
	jz	extcheck_exit
	cmp	al,"."
	jnz	extcheck_loop
	mov	dx,di
	jmp	extcheck_loop
extcheck_exit:

;-----------------------------------------------------------------------------
;	拡張子を変更
;-----------------------------------------------------------------------------
	or	dx,dx
	jnz	ext_found
	mov	dx,di
	mov	byte ptr es:-1[di],"."	;"."がない = 最終位置
ext_found:
	mov	di,dx		;es:di = 変更される拡張子の位置
	mov	ax,cs
	mov	ds,ax
	mov	si,bx		;ds:si = 変更される拡張子の位置

	movsw
	movsb			;拡張子変更

	ret

;==============================================================================
;	DataArea
;==============================================================================
if	message
allload_mes	db	"The PCM is being defined. Please wait.",13,10,"$"
exit1_mes	db	"The PCM can't be defined there.",13,10,"$"
exit1p_mes	db	"PPSDRV isn't residenting.",13,10,"$"
exit2_mes	db	"PCMFile isn't found.",13,10,"$"
exit2p_mes	db	"PPSFile isn't found.",13,10,"$"
exit3_mes	db	"The PCMFile format is unknown.",13,10,"$"
exit3p_mes	db	"Capacity of the PPSDRV is insufficient.",13,10,"$"
exit4_mes	db	"Because the PCMData is matched, this is not read.",13,10,"$"
exit4pp_mes	db	"Capacity of the P86DRV is insufficient.",13,10,"$"
exit5_mes	db	"The PCMFile cannot be read.",13,10,"$"
exit5p_mes	db	"The PPSFile cannot be read.",13,10,"$"
exit6_mes	db	"Another application is accessing the PCM memory.",13,10,"$"
exit1z_mes	db	"PCMFile isn't found.",13,10,"$"
exit2z_mes	db	"The PCMFile format is unknown.",13,10,"$"
exit3z_mes	db	"Out of memory.",13,10,"$" ; i know, this translation isn't geniue.
exit4z_mes	db	"Unable to map EMS handle.",13,10,"$"
exit5z_mes	db	"PPZ8 isn't residenting.",13,10,"$"
ppzbank_mes	db	"PPZ8("
banknum		db	"?):$"
endif
adpcm_header	db	"ADPCM DATA for  PMD ver.4.4-  " ;30 bytes
pps_ext		db	"PPS"
ppc_ext		db	"PPC"
p86_ext		db	"P86"
pvi_ext		db	"PVI"
pzi_ext		db	"PZI"

retry_flag	db	0
key_check_push	db	0
wait_clock	dw	0
adpcm_wait	db	0
mmask_port	dw	0
mmask_push	db	0

filename_buf	db	128 dup(?)

		even
filename_ofs	dw	?
filename_seg	dw	?
filename_ofs2	dw	?
filename_seg2	dw	?
pcmdata_ofs	dw	?
pcmdata_seg	dw	?
pcmdata_size_s	db	?
pcmdata_size	dw	?
pcmwork_ofs	dw	?
pcmwork_seg	dw	?
port46		dw	?
port47		dw	?
pcmstop		dw	?
pcmstart	dw	?
fhand2		dw	?
ppz_bank	db	?

open_work	struc
_mmlbuf		dw	?		;Musicdataのaddress+1
_tondat		dw	?		;Voicedataのaddress
_efcdat		dw	?		;FM  Effecdataのaddress
_fm1_port1	dw	?		;FM音源 I/O port (表1)
_fm1_port2	dw	?		;FM音源 I/O port (表2)
_fm2_port1	dw	?		;FM音源 I/O port (裏1)
_fm2_port2	dw	?		;FM音源 I/O port (裏2)
_fmint_ofs	dw	?		;FM割り込みフックアドレス offset
_fmint_seg	dw	?		;FM割り込みフックアドレス address
_efcint_ofs	dw	?		;効果音割り込みフックアドレス offset
_efcint_seg	dw	?		;効果音割り込みフックアドレス address
_prgdat_adr	dw	?		;曲データ中音色データ先頭番地
_radtbl		dw	?		;R part offset table 先頭番地
_rhyadr		dw	?		;R part 演奏中番地
_rhythmmask	db	?		;Rhythm音源のマスク x8c/10hのbitに対応
_board		db	?		;FM音源ボードあり／なしflag
_key_check	db	?		;ESC/GRPH key Check flag
_fm_voldown	db	?		;FM voldown 数値
_psg_voldown	db	?		;PSG voldown 数値
_pcm_voldown	db	?		;PCM voldown 数値
_rhythm_voldown	db	?		;RHYTHM voldown 数値
_prg_flg	db	?		;曲データに音色が含まれているかflag
_x68_flg	db	?		;OPM flag
_status		db	?		;status1
_status2	db	?		;status2
_tempo_d	db	?		;tempo (TIMER-B)
_fadeout_speed	db	?		;Fadeout速度
_fadeout_volume	db	?		;Fadeout音量
_tempo_d_push	db	?		;tempo (TIMER-B) / 保存用
_syousetu_lng	db	?		;小節の長さ
_opncount	db	?		;最短音符カウンタ
_TimerAtime	db	?		;TimerAカウンタ
_effflag	db	?		;PSG効果音発声on/off flag
_psnoi		db	?		;PSG noise周波数
_psnoi_last	db	?		;PSG noise周波数(最後に定義した数値)
_fm_effec_num	db	?		;発声中のFM効果音番号
_fm_effec_flag	db	?		;FM効果音発声中flag (1)
_disint		db	?		;FM割り込み中に割り込みを禁止するかflag
_pcmflag	db	?		;PCM効果音発声中flag
_pcmstart	dw	?		;PCM音色のstart値
_pcmstop	dw	?		;PCM音色のstop値
_pcm_effec_num	db	?		;発声中のPCM効果音番号
__pcmstart	dw	?		;PCM効果音のstart値
__pcmstop	dw	?		;PCM効果音のstop値
__voice_delta_n	dw	?		;PCM効果音のdelta_n値
__pcmpan	db	?		;PCM効果音のpan
__pcm_volume	db	?		;PCM効果音のvolume
_rshot_dat	db	?		;リズム音源 shot flag
_rdat		db	6 dup (?)	;リズム音源 音量/パンデータ
_rhyvol		db	?		;リズムトータルレベル
_kshot_dat	dw	?		;ＳＳＧリズム shot flag
_ssgefcdat	dw	?		;PSG Effecdataのaddress
_ssgefclen	dw	?		;PSG Effecdataの長さ
_play_flag	db	?		;play flag
_pause_flag	db	?		;pause flag
_fade_stop_flag	db	?		;Fadeout後 MSTOPするかどうかのフラグ
_kp_rhythm_flag	db	?		;K/RpartでRhythm音源を鳴らすかflag
_TimerBflag	db	?		;TimerB割り込み中？フラグ
_TimerAflag	db	?		;TimerA割り込み中？フラグ
_int60flag	db	?		;INT60H割り込み中？フラグ
_int60_result	db	?		;INT60Hの実行ErrorFlag
_pcm_gs_flag	db	?		;ADPCM使用 許可フラグ (0で許可)
_esc_sp_key	db	?		;ESC +?? Key Code
_grph_sp_key	db	?		;GRPH+?? Key Code
_rescut_cant	db	?		;常駐解除禁止フラグ
_slot_detune1	dw	?		;FM3 Slot Detune値 slot1
_slot_detune2	dw	?		;FM3 Slot Detune値 slot2
_slot_detune3	dw	?		;FM3 Slot Detune値 slot3
_slot_detune4	dw	?		;FM3 Slot Detune値 slot4
_wait_clock	dw	?		;FM ADDRESS-DATA間 Loop $の回数
_wait1_clock	dw	?		;loop $ １個の速度
_ff_tempo	db	?		;早送り時のTimerB値
_pcm_access	db	?		;PCMセット中は 1
_TimerB_speed	db	?		;TimerBの現在値(=ff_tempoならff中)
_fadeout_flag	db	?		;内部からfoutを呼び出した時1
_adpcm_wait	db	?		;ADPCM定義の速度
_revpan		db	?		;PCM86逆走flag
_pcm86_vol	db	?		;PCM86の音量をSPBに合わせるか?
_syousetu	dw	?		;小節カウンタ
_int5_flag	db	?		;FM音源割り込み中？フラグ
_port22h	db	?		;OPN-PORT 22H に最後に出力した値(hlfo)
_tempo_48	db	?		;現在のテンポ(clock=48 tの値)
_tempo_48_push	db	?		;現在のテンポ(同上/保存用)
_rew_sp_key	db	?		;GRPH+?? (rew) Key Code
_intfook_flag	db	?		;int_fookのflag B0:TB B1:TA
_skip_flag	db	?		;normal:0 前方SKIP中:1 後方SKIP中:2
__fm_voldown	db	?		;FM voldown 数値 (保存用)
__ssg_voldown	db	?		;PSG voldown 数値 (保存用)
__pcm_voldown	db	?		;PCM voldown 数値 (保存用)
__rhythm_voldown db	?		;RHYTHM voldown 数値 (保存用)
__pcm86_vol	db	?		;PCM86の音量をSPBに合わせるか? (保存用)
_mstart_flag	db	?		;mstartする時に１にするだけのflag
_mus_filename	db	13 dup(?)	;曲のFILE名バッファ
_mmldat_lng	db	?		;曲データバッファサイズ(KB)
_voicedat_lng	db	?		;音色データバッファサイズ(KB)
_effecdat_lng	db	?		;効果音データバッファサイズ(KB)
_rshot_bd	db	?		;リズム音源 shot inc flag (BD)
_rshot_sd	db	?		;リズム音源 shot inc flag (SD)
_rshot_sym	db	?		;リズム音源 shot inc flag (CYM)
_rshot_hh	db	?		;リズム音源 shot inc flag (HH)
_rshot_tom	db	?		;リズム音源 shot inc flag (TOM)
_rshot_rim	db	?		;リズム音源 shot inc flag (RIM)
_rdump_bd	db	?		;リズム音源 dump inc flag (BD)
_rdump_sd	db	?		;リズム音源 dump inc flag (SD)
_rdump_sym	db	?		;リズム音源 dump inc flag (CYM)
_rdump_hh	db	?		;リズム音源 dump inc flag (HH)
_rdump_tom	db	?		;リズム音源 dump inc flag (TOM)
_rdump_rim	db	?		;リズム音源 dump inc flag (RIM)
_ch3mode	db	?		;ch3 Mode
_ch3mode_push	db	?		;ch3 Mode(効果音発音時用push領域)
_ppz_voldown	db	?		;PPZ8 voldown 数値
__ppz_voldown	db	?		;PPZ8 voldown 数値 (保存用)
_ppz_call_ofs	dw	?		;PPZ8call用 far call address
_ppz_call_seg	dw	?		;seg値はPPZ8常駐checkを兼ねる,0で非常駐
_p86_freq	db	?		;PMD86のPCM再生周波数
_p86_freqtable	dw	?		;PMD86のPCM再生周波数table位置
open_work	ends

part_work	struc
_address	dw	?	; 2 ｴﾝｿｳﾁｭｳ ﾉ ｱﾄﾞﾚｽ
_partloop	dw	?       ; 2 ｴﾝｿｳ ｶﾞ ｵﾜｯﾀﾄｷ ﾉ ﾓﾄﾞﾘｻｷ
_leng		db	?       ; 1 ﾉｺﾘ LENGTH
_qdat		db	?       ; 1 gatetime (q/Q値を計算した値)
_fnum		dw	?       ; 2 ｴﾝｿｳﾁｭｳ ﾉ BLOCK/FNUM
_detune		dw	?       ; 2 ﾃﾞﾁｭｰﾝ
_lfodat		dw	?       ; 2 LFO DATA
_porta_num	dw	?	; 2 ポルタメントの加減値（全体）
_porta_num2	dw	?	; 2 ポルタメントの加減値（一回）
_porta_num3	dw	?	; 2 ポルタメントの加減値（余り）
_volume		db	?       ; 1 VOLUME
_shift		db	?       ; 1 ｵﾝｶｲ ｼﾌﾄ ﾉ ｱﾀｲ
_delay		db	?       ; 1 LFO	[DELAY] 
_speed		db	?       ; 1	[SPEED]
_step		db	?       ; 1	[STEP]
_time		db	?       ; 1	[TIME]
_delay2		db	?       ; 1	[DELAY_2]
_speed2		db	?       ; 1	[SPEED_2]
_step2		db	?       ; 1	[STEP_2]
_time2		db	?       ; 1	[TIME_2]
_lfoswi		db	?       ; 1 LFOSW. B0/tone B1/vol B2/同期 B3/porta
				;          B4/tone B5/vol B6/同期
_volpush	db	? 	; 1 Volume PUSHarea
_mdepth		db	?	; 1 M depth
_mdspd		db	?	; 1 M speed
_mdspd2		db	?	; 1 M speed_2
_envf		db	?       ; 1 PSG ENV. [START_FLAG] / -1でextend
_eenv_count	db	?	; 1 ExtendPSGenv/No=0 AR=1 DR=2 SR=3 RR=4
_eenv_ar	db	?	; 1 		/AR		/旧pat
_eenv_dr	db	?	; 1		/DR		/旧pv2
_eenv_sr	db	?	; 1		/SR		/旧pr1
_eenv_rr	db	?	; 1		/RR		/旧pr2
_eenv_sl	db	?	; 1		/SL
_eenv_al	db	?	; 1		/AL
_eenv_arc	db	?	; 1		/ARのカウンタ	/旧patb
_eenv_drc	db	?	; 1		/DRのカウンタ
_eenv_src	db	?	; 1		/SRのカウンタ	/旧pr1b
_eenv_rrc	db	?	; 1		/RRのカウンタ	/旧pr2b
_eenv_volume	db	?	; 1		/Volume値(0～15)/旧penv
_extendmode	db	?	; 1 B1/Detune B2/LFO B3/Env Normal/Extend
_fmpan		db	? 	; 1 FM Panning + AMD + PMD
_psgpat		db	?       ; 1 PSG PATTERN [TONE/NOISE/MIX]
_voicenum	db	?	; 1 音色番号
_loopcheck	db	?	; 1 ループしたら１ 終了したら３
_carrier	db	?	; 1 FM Carrier
_slot1		db	?       ; 1 SLOT 1 ﾉ TL
_slot3		db	?       ; 1 SLOT 3 ﾉ TL
_slot2		db	?       ; 1 SLOT 2 ﾉ TL
_slot4		db	?       ; 1 SLOT 4 ﾉ TL
_slotmask	db	?	; 1 FM slotmask
_neiromask	db	?	; 1 FM 音色定義用maskdata
_lfo_wave	db	?	; 1 LFOの波形
_partmask	db	?	; 1 PartMask b0:通常 b1:効果音 b2:NECPCM用
				;   b3:none b4:none b5:s0時 b6:m b7:一時
_keyoff_flag	db	?	; 1 KeyoffしたかどうかのFlag
_volmask	db	?	; 1 音量LFOのマスク
_qdata		db	?	; 1 qの値
_qdatb		db	?	; 1 Qの値
_hldelay	db	?	; 1 HardLFO delay
_hldelay_c	db	?	; 1 HardLFO delay Counter
__lfodat	dw	?       ; 2 LFO DATA
__delay		db	?       ; 1 LFO	[DELAY] 
__speed		db	?       ; 1	[SPEED]
__step		db	?       ; 1	[STEP]
__time		db	?       ; 1	[TIME]
__delay2	db	?       ; 1	[DELAY_2]
__speed2	db	?       ; 1	[SPEED_2]
__step2		db	?       ; 1	[STEP_2]
__time2		db	?       ; 1	[TIME_2]
__mdepth	db	?	; 1 M depth
__mdspd		db	?	; 1 M speed
__mdspd2	db	?	; 1 M speed_2
__lfo_wave	db	?	; 1 LFOの波形
__volmask	db	?	; 1 音量LFOのマスク
_mdc		db	?	; 1 M depth Counter (変動値)
_mdc2		db	?	; 1 M depth Counter
__mdc		db	?	; 1 M depth Counter (変動値)
__mdc2		db	?	; 1 M depth Counter
_onkai		db	?	; 1 演奏中の音階データ (0ffh:rest)
_sdelay		db	?	; 1 Slot delay
_sdelay_c	db	?	; 1 Slot delay counter
_sdelay_m	db	?	; 1 Slot delay Mask
_alg_fb		db	?	; 1 音色のalg/fb
_keyon_flag	db	?	; 1 新音階/休符データを処理したらinc
_qdat2		db	?	; 1 q 最低保証値
_fnum2		dw	?	; 2 ppz8/pmd86用fnum値上位
_onkai_def	db	?	; 1 演奏中の音階データ (転調処理前 / ?fh:rest)
_shift_def	db	?	; 1 マスター転調値
_qdat3		db	?	; 1 q Random
		db	?	; dummy
part_work	ends

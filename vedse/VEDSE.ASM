;
;	voice editor
;
code	segment
	assume	cs:code,ds:data,es:data,ss:stack

	include	dos.inc
	include	diskmc.inc

start:

	cld
;==============================================================================
;	title表示
;==============================================================================
	mov	bx,ds
	mov	ax,data
	mov	ds,ax
	mov	es,ax
	print_mes	title_mes
	mov	ds,bx

;==============================================================================
;	最初のスペースを飛ばす
;==============================================================================
	mov	si,offset 80h
	cmp	byte ptr [si],0
	jz	usage

	inc	si
	call	space_cut

;==============================================================================
; 	コマンドラインから.ffのファイル名の取り込み
;==============================================================================

	xor	ah,ah
	mov	di,offset ff_filename
g_ffn_loop:
	lodsb
	cmp	al," "
	jz	g_ffn_next
	cmp	al,13
	jz	g_ffn_next
	cmp	al,"."
	jnz	g_ffn_store
	mov	ah,1
g_ffn_store:
	stosb
	jmp	g_ffn_loop
g_ffn_next:
	dec	si
	or	ah,ah
	jnz	ffn_ofs_notset

	mov	ax,"F."
	stosw
	mov	al,"F"
	stosb
ffn_ofs_notset:
	xor	al,al
	stosb

;==============================================================================
;	Read .FF file
;==============================================================================

	mov	ax,data
	mov	ds,ax

	mov	di,offset ff_buffer
	mov	cx,16*256
	xor	ax,ax
rep	stosw

	mov	ax,offset ff_filename
	mov	dx,offset ff_buffer
	call	DISKREAD
	jnc	rff_00

	mov	si,offset ff_buffer	;新しく作成
	mov	cx,32*256
	xor	al,al
rep	stosb

rff_00:
	mov	si,offset ff_buffer
	mov	di,offset ff_buffer2
	mov	cx,32*256
rep	movsb

;==============================================================================
; 	.ffを.mmlに変更して設定
;==============================================================================

	mov	si,offset ff_filename
	mov	di,offset mml_filename

cv_ff_mml_loop:
	movsb
	cmp	byte ptr -1[si],"."
	jnz	cv_ff_mml_loop

	mov	ax,"MM"
	stosw
	mov	ax,"L"
	stosw

;==============================================================================
;	Board Check
;==============================================================================
	push	es
	call	port_check
	pop	es

;==============================================================================
;	Main
;==============================================================================
main:
	print_mes	cls
	print_mes	screen
	print_mes	base
	print_mes	notice
	print_mes	base
	mov	[notice_flag],0
	mov	[voice_number],0
	mov	[octarb],3
	call	print_octarb
	call	print_allparam

	mov	[cursor],offset table

main_loop:
	mov	di,[cursor]
	cmp	byte ptr [di+1],0
	jnz	ml_00
	mov	di,offset t_fbl
	mov	[cursor],di

ml_00:
	print_mes	reverse
	call	print_param
	print_mes	normal

ml_01:
	mov	ah,1
	int	18h		;input chr
	cmp	bh,1
	jnz	ml_01

	cmp	al,"0"
	jc	ml_02
	cmp	al,"9"+1
	jnc	ml_02
	jmp	param_input

ml_02:
	xor	ah,ah
	int	18h		;input chr

	mov	al,ah

	push	di
	mov	cx,key_length
	mov	di,offset key_table+key_length-1
	std
repnz	scasb
	cld
	pop	di
	jnz	sound

	add	cx,cx
	mov	bx,offset key_jumptable
	add	bx,cx
	jmp	[bx]

sound:
	push	di
	mov	cx,sound_length
	mov	di,offset sound_c_table+sound_length-1
	std
repnz	scasb
	cld
	pop	di
	jnz	ml_00

;==============================================================================
;	Keyon & hold & keyoff
;		input	cx to sound_number
;==============================================================================
	add	cx,cx
	add	cx,cx
	mov	bx,offset sound_buffer
	add	bx,cx

	mov	ax,[bx]
	inc	bx
	inc	bx

	mov	dl,[octarb]
	and	dl,7
	rol	dl,1
	rol	dl,1
	rol	dl,1
	and	ah,7
	or	dl,ah
	mov	dh,0a4h
	call	opnset		;fnum(high)/block

	mov	dh,0a0h
	mov	dl,al
	call	opnset		;fnum(low)

	mov	dx,28f0h
	call	opnset		;keyon

	mov	dl,ds:[bx]	;dl = key group
	inc	bx

hold_loop0:
	mov	cx,3		;リピート対策
hold_loop1:
	call	key_buffer_clear
	mov	ah,4
	mov	al,dl
	int	18h		;キー押下状態のスキャン
	and	ah,ds:[bx]
	jnz	hold_loop0

	push	cx
	mov	cx,400h
key_1ms_wait:
	out	5fh,al		;1ms以上待つ
	loop	key_1ms_wait
	pop	cx

	loop	hold_loop1

	mov	dx,2800h
	call	opnset		;keyoff

	call	key_buffer_clear
	jmp	main_loop

;==============================================================================
;	Keybuffer Clear
;==============================================================================
key_buffer_clear:
	mov	ah,5
	int	18h		;keybuffer check
	or	bh,bh
	jnz	key_buffer_clear
	ret

;==============================================================================
;	Rollup
;==============================================================================
param_oneup:
	call	get_param
	cmp	[di+1],al
	jz	po_00
	inc	al
po_00:
	call	set_param
	jmp	main_loop

;==============================================================================
;	Rolldown
;==============================================================================
param_onedown:
	call	get_param
	or	al,al
	jz	pd_00
	dec	al
pd_00:
	call	set_param
	jmp	main_loop

;==============================================================================
;	Up
;==============================================================================
move_up:
	print_mes	normal
	call	print_param
	cmp	di,offset able_up
	jc	main_loop
	sub	di,table_length*11
	mov	[cursor],di
	jmp	main_loop

;==============================================================================
;	Down
;==============================================================================
move_down:
	print_mes	normal
	call	print_param
	cmp	di,offset able_dw
	jnc	main_loop
	add	di,table_length*11
	mov	[cursor],di
	jmp	main_loop

;==============================================================================
;	Left
;==============================================================================
move_left:
	print_mes	normal
	call	print_param
	cmp	di,offset able_lf
	jc	main_loop
	sub	di,table_length
	mov	[cursor],di
	jmp	main_loop

;==============================================================================
;	Right
;==============================================================================
move_right:
	print_mes	normal
	call	print_param
	cmp	di,offset able_rg
	jnc	main_loop
	add	di,table_length
	mov	[cursor],di
	cmp	byte ptr [di+1],0
	jnz	main_loop
	mov	di,offset able_up
	mov	[cursor],di
	jmp	main_loop

;==============================================================================
;	Return (Input Parameter)
;==============================================================================
param_input:
	call	cursor_move
	print_mes	reverse
	print_mes	space
	call	cursor_move
	print_mes	cursor_on
	mov	dx,offset buffer
	mov	[buffer],4
	mov	ah,0ah
	int	21h		;line input
	print_mes	cursor_off
	print_mes	normal

	mov	dx,offset buffer
	call	get_number
	jc	main_loop

	cmp	al,[di+1]
	jc	pi_00
	mov	al,[di+1]
pi_00:
	call	set_param
	jmp	main_loop

;==============================================================================
;	get_number
;		input	ds:dx to input_buffer offset
;==============================================================================
get_number:
	xor	al,al
	mov	cl,1
	mov	bx,dx
	cmp	byte ptr [bx+1],0
	jz	gn_error
	inc	bx
	inc	bx

gn_loop:
	mov	ah,[bx]
	inc	bx
	cmp	ah,13
	jz	gn_exit
	cmp	ah,"9"+1
	jnc	gn_loop
	cmp	ah,"0"
	jc	gn_loop
	sub	ah,"0"
	add	al,al
	mov	ch,al
	add	al,al
	add	al,al
	add	al,ch	;al*10
	add	al,ah
	xor	cl,cl
	jmp	gn_loop

gn_exit:
	cmp	cl,1
	jz	gn_error
	clc
	ret

gn_error:
	stc
	ret

;==============================================================================
;	f･5 (set voicename)
;==============================================================================
set_vname:
	print_mes	normal
	call	print_param

	mov	di,offset vname
	mov	cx,7
	mov	al," "
rep	stosb

	print_mes	reverse
	print_mes	vname_cursor
	print_mes	vname
	print_mes	vname_cursor

	print_mes	cursor_on
	mov	dx,offset buffer
	mov	[buffer],8
	mov	ah,0ah
	int	21h		;line input
	print_mes	cursor_off
	print_mes	normal

	push	si
	mov	di,si
	add	di,25
	mov	si,offset buffer+2
	cmp	byte ptr [si-1],0
	jz	sv_error

	mov	cx,7
sv_loop:
	xor	al,al
	cmp	byte ptr [si],13
	jz	sv_02
	lodsb
sv_02:
	stosb
	loop	sv_loop

sv_error:
	pop	si

	call	vname_put
	jmp	main_loop

;==============================================================================
;	Octarb Up
;==============================================================================
oct_up:
	mov	al,[octarb]
	cmp	al,7
	jz	main_loop
	inc	al
	mov	[octarb],al
	call	print_octarb
	jmp	main_loop

;==============================================================================
;	Octarb Down
;==============================================================================
oct_down:
	mov	al,[octarb]
	or	al,al
	jz	main_loop
	dec	al
	mov	[octarb],al
	call	print_octarb
	jmp	main_loop

;==============================================================================
;	オクターブの表示
;==============================================================================
print_octarb:
	print_mes	normal
	print_mes	octarb_mes
	mov	al,[octarb]
	inc	al
	call	print_num
	ret

;==============================================================================
;	Push Parameter
;==============================================================================
push_param:
	push	si
	mov	di,offset push_buffer
	mov	cx,25
rep	movsb
	pop	si
	push	si
	mov	si,offset push_buffer
	call	print_allparam_2
	pop	si
	jmp	main_loop

;==============================================================================
;	Pop Parameter
;==============================================================================
pop_param:
	push	si
	mov	di,offset push_buffer
	xchg	si,di
	mov	cx,25
rep	movsb
	pop	si
	call	print_allparam_3
	jmp	main_loop

;==============================================================================
;	Exchange Parameter
;==============================================================================
exchange_param:
	push	si
	mov	di,offset push_buffer
	mov	cx,25
ep_loop:
	mov	al,[si]
	mov	ah,[di]
	mov	[di],al
	mov	[si],ah
	inc	si
	inc	di
	loop	ep_loop
	pop	si
	push	si
	mov	si,offset push_buffer
	call	print_allparam_2
	pop	si
	call	print_allparam_3
	jmp	main_loop

;==============================================================================
;	Pop Parameter 2 ( 変更前の音色に )
;==============================================================================
pop_param_2:
	push	si
	mov	di,si
	add	di,32*256
	xchg	si,di
	mov	cx,32
rep	movsb
	pop	si
	call	print_allparam_3
	jmp	main_loop

;==============================================================================
;	Write	.FF file
;==============================================================================
main_exit:
	mov	di,offset ff_buffer+32*256-1
	mov	cx,32*256
	xor	al,al
	std
repz	scasb
	cld

	dec	cx
	and	cx,0ffe0h
	add	cx,20h

	mov	ax,offset ff_filename
	mov	dx,offset ff_buffer

	call	DISKWRITE
	jc	diskerror2

;==============================================================================
;	終了
;==============================================================================

	print_mes	crt_return
	print_mes	complete_mes
	msdos_exit

;==============================================================================
;	saveせず終了
;==============================================================================
main_exit2:
	print_mes	crt_return
	print_mes	exit_mes
	msdos_exit

;==============================================================================
;	パラメータの変更 & 音色の変更
;		input	di to parameter offset
;			al to parameter
;==============================================================================
set_param:
	cmp	byte ptr [di],-1
	jnz	sp_00
	mov	[voice_number],al
	call	print_allparam
	ret

sp_00:
	mov	bl,[di]
	xor	bh,bh
	mov	ah,[di+1]
	and	al,ah
	mov	cl,[di+2]
	test	cl,cl
	jz	sp_01
	js	sp_03
	rol	al,cl
	rol	ah,cl
sp_01:
	mov	dl,[si+bx]
	not	ah
	and	dl,ah
	or	al,dl
	mov	[si+bx],al
sp_02:
	mov	dh,[di+3]
	mov	dl,al
	call	opnset

	ret

sp_03:			;特殊:SSGEG
	mov	dh,al
	rol	dh,1
	rol	dh,1
	rol	dh,1
	rol	dh,1
	mov	ah,dh
	and	ah,80h
	mov	dl,[si+bx]
	and	dl,7fh
	or	ah,dl
	mov	[si+bx],ah

	rol	dh,1
	mov	ah,dh
	and	ah,80h
	mov	dl,[si+bx+4]
	and	dl,7fh
	or	ah,dl
	mov	[si+bx+4],ah

	mov	ah,dh
	and	ah,60h
	mov	dl,[si+bx+12]
	and	dl,9fh
	or	ah,dl
	mov	[si+bx+12],ah

	jmp	sp_02

;==============================================================================
;	総てのパラメータの表示 & 音色の再設定
;		output	si to voicedata offset
;==============================================================================
print_allparam:
	mov	al,[voice_number]
	xor	ah,ah
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	add	ax,ax
	mov	si,offset ff_buffer
	add	si,ax

print_allparam_3:
	mov	di,offset table

	mov	cx,11*5
pp_loop:
	push	cx

	call	print_param

	mov	al,[di+1]	;numとdummyは飛ばす
	test	al,al
	jz	pp_notset
	js	pp_notset
	call	pp_00		;パラメータ取得
	call	sp_00		;パラメータ設定

pp_notset:
	add	di,table_length
	pop	cx
	loop	pp_loop

vname_put:
	push	si
	add	si,25
	cmp	byte ptr [si],0
	jnz	vp_00
	mov	si,offset nothing
vp_00:
	mov	di,offset vname
	mov	cx,7
rep	movsb
	print_mes	vname_mes
	pop	si
	ret

;==============================================================================
;	パラメータの表示
;		input	di to parameter offset
;==============================================================================
print_param:
	cmp	byte ptr [di+1],0
	jz	pp_exit

	call	cursor_move
	call	get_param
	call	print_num

pp_exit:
	ret

;==============================================================================
;	総てのパラメータの表示 (push版)
;==============================================================================
print_allparam_2:
	mov	di,offset table

	mov	cx,11*5
pp2_loop:
	push	cx

	call	print_param_2

	add	di,table_length
	pop	cx
	loop	pp2_loop
	ret

;==============================================================================
;	パラメータの表示 (push版)
;		input	di to parameter offset
;==============================================================================
print_param_2:
	cmp	byte ptr [di+1],0
	jz	pp2_exit

	call	cursor_move
	print_mes	cursor_down
	call	get_param
	call	print_num

pp2_exit:
	ret

;==============================================================================
;	パラメータの所得
;		input	di to parameter offset
;		output	al to parameter
;==============================================================================
get_param:
	cmp	byte ptr [di],-1
	jnz	pp_00
	mov	al,[voice_number]
	jmp	pp_01
pp_00:
	mov	bl,[di]
	xor	bh,bh
	mov	al,[si+bx]
pp_01:
	mov	cl,[di+2]
	test	cl,cl
	jz	pp_02
	js	pp_03
	ror	al,cl
pp_02:
	mov	ah,[di+1]
	and	al,ah
	ret

pp_03:			;特殊:SSGEG
	mov	ah,al
	xor	al,al
	rol	ah,1
	rcl	al,1
	mov	ah,[si+bx+4]
	rol	ah,1
	rcl	al,1
	mov	ah,[si+bx+12]
	rol	ah,1
	rol	ah,1
	rcl	al,1
	rol	ah,1
	rcl	al,1
	jmp	pp_02

;==============================================================================
;	カーソル位置の移動
;==============================================================================
cursor_move:
	mov	dx,di
	add	dx,4
	mov	ah,9
	int	21h
	ret

;==============================================================================
;	数字の表示(0-255)
;==============================================================================
print_num:
	mov	dl,100
	call	oneset
	mov	dl,10
	call	oneset
	add	al,"0"
	mov	dl,al
	print_chr
	ret
oneset:
	mov	dh,"0"
ons0:	sub	al,dl
	jc	ons1
	inc	dh
	jmp	ons0
ons1:	add	al,dl
	mov	dl,dh
	push	ax
	print_chr
	pop	ax
	ret

;==============================================================================
;	OPN出力
;==============================================================================
opnset:	
	cmp	[board],0
	jz	os_ret
	push	ax
	push	dx
	mov	ax,dx

	cli
	mov	dx,[fm_port1]
	xchg	ah,al
	call	rdychk
	out	dx,al
	mov	dx,[fm_port2]
	xchg	ah,al
	push	cx
	mov	cx,100
	loop	$
	pop	cx
	out	dx,al
	sti

	pop	dx
	pop	ax
os_ret:
	ret

;==============================================================================
;	OPN READY CHECK
;==============================================================================
rdychk:	push	ax
	push	dx
	mov	dx,[fm_port1]
	in	al,dx
opnbsy:	in	al,dx
	test	al,80h
	jnz	opnbsy
	pop	dx
	pop	ax
	ret

;==============================================================================
;	.MML write (全部)
;==============================================================================
write_mml1:
	mov	[mml_mes],0
	jmp	wm_00

write_mml2:
	mov	[mml_mes],1

wm_00:
	print_mes	reverse
	print_mes	mes_start
	print_mes	normal

	mov	bp,offset mml_filename

	mov	cs:[spfook],sp
	call	makhnd		; Make Handle
	jc	diskerror2

	mov	di,offset ff_buffer+32*256-1
	mov	cx,32*256
	xor	al,al
	std
repz	scasb
	cld
	jz	wm_fin

	dec	cx
	and	cx,0ffe0h

	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	inc	cx		; cx = number of datas

	mov	[mml_vnum],0

	push	si
	mov	si,offset ff_buffer

wm_loop:
	push	cx

	call	set_mml

	mov	dx,offset mml_buffer
	mov	cx,di
	sub	cx,dx

	mov	cs:[spfook],sp
	call	wrihnd		; Write Handle
	jc	diskerror2

	inc	[mml_vnum]
	add	si,20h

	pop	cx
	loop	wm_loop

	mov	cs:[spfook],sp
	call	clohnd		; Close Handle
	jc	diskerror2

	pop	si
wm_fin:
	print_mes	mes_fin

	jmp	main_loop

;==============================================================================
;	.MML write (一個)
;			input	si to voice_data_address
;==============================================================================
write_mml3:
	mov	[mml_mes],0
	jmp	wm3_00

write_mml4:
	mov	[mml_mes],1

wm3_00:
	print_mes	reverse
	print_mes	mes_start
	print_mes	normal

	mov	bp,offset mml_filename

	mov	cs:[spfook],sp
	call	makhnd		; Make Handle
	jc	diskerror2

	mov	al,[voice_number]
	mov	[mml_vnum],al

	call	set_mml

	mov	dx,offset mml_buffer
	mov	cx,di
	sub	cx,dx

	mov	cs:[spfook],sp
	call	wrihnd		; Write Handle
	jc	diskerror2

	mov	cs:[spfook],sp
	call	clohnd		; Close Handle
	jc	diskerror2

	print_mes	mes_fin

	jmp	main_loop

;==============================================================================
;	Set Voice to MML_buffer
;		inputs	[mml_vnum]	to number of voice
;			[mml_num]	to DT2 flag
;			si		to voice_data_address
;==============================================================================
set_mml:
	mov	di,offset mml_buffer

	mov	bx,offset mes_1
	call	mes_set

	mov	al,"@"
	stosb

	mov	al,[mml_vnum]
	call	num_set			;tone number set

	mov	bx,offset able_lf
	mov	[mml_param],bx

	mov	cx,2
wm_loop2:
	push	cx
	call	param_set
	pop	cx
	loop	wm_loop2

	cmp	byte ptr 25[si],0
	jz	wm_01b

	mov	ax,0909h
	stosw
	stosw
	mov	al,"="
	stosb
	mov	al,9
	stosb
	mov	bx,si
	add	bx,25
	mov	al,32[si]
	push	ax
	mov	byte ptr 32[si],0
	call	mes_set
	pop	ax
	mov	32[si],al
wm_01b:
	mov	ax,10*256+13
	stosw

	mov	bx,offset able_up
	mov	[mml_param],bx

	mov	bx,offset mes_2a
	cmp	[mml_mes],1
	jnz	wm_01
	mov	bx,offset mes_2b
wm_01:
	call	mes_set

	mov	ax,10*256+13
	stosw

	mov	cx,4
wm_loop4:
	push	cx

	mov	cx,11
wm_loop3:
	push	cx
	cmp	cx,1
	jnz	wm_02
	cmp	[mml_mes],1
	jnz	wm_02a
	mov	bx,[mml_param]
	add	bx,table_length
	mov	[mml_param],bx
	jmp	wm_03
wm_02a:
	mov	ax,"; "
	stosw
wm_02:
	call	param_set
wm_03:
	pop	cx
	loop	wm_loop3

	mov	ax,10*256+13
	stosw

	pop	cx
	loop	wm_loop4

	mov	ax,10*256+13
	stosw

	ret

;==============================================================================
;	Param Set to MML
;==============================================================================
param_set:
	mov	al," "
	stosb
	push	di
	mov	di,[mml_param]
	call	get_param
	add	di,table_length
	mov	[mml_param],di
	pop	di
	call	num_set
	ret

;==============================================================================
;	Message Set to MML
;		input	bx	Mes_offset
;			di	MML_offset
;==============================================================================
mes_set:
	mov	al,[bx]
	or	al,al
	jz	ms_ret
	stosb
	inc	bx
	jmp	mes_set
ms_ret:
	ret

;==============================================================================
;	Number set to MML
;		input	al	Number
;			di	MML_offset
;==============================================================================
num_set:
	mov	dl,100
	call	n_oneset
	mov	dl,10
	call	n_oneset
	add	al,"0"
	stosb
	ret
n_oneset:
	mov	dh,"0"
n_ons0:	sub	al,dl
	jc	n_ons1
	inc	dh
	jmp	n_ons0
n_ons1:	add	al,dl
	mov	[di],dh
	inc	di
	ret

;==============================================================================
;	HELP	key/alg 表示の切替え
;==============================================================================
notice_put:
	xor	[notice_flag],1
	cmp	[notice_flag],1
	jz	np_2
	print_mes	notice
	jmp	main_loop
np_2:
	print_mes	notice2
	jmp	main_loop

;==============================================================================
;	FM音源ポートを調べる
;		output	fm_port1/fm_port2/board
;			cy=1でボード無し
;==============================================================================
port_check:
;------------------------------------------------------------------------------
;	98+NORM の check	(PMD)
;------------------------------------------------------------------------------
	call	check_spb
	jnc	norm_ret
	call	check_86b
	jnc	norm_ret

	mov	ah,4		;088->188->288->388の順にcheck
	mov	dx,088h

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

;------------------------------------------------------------------------------
;	86Bの存在check
;------------------------------------------------------------------------------
check_86b:
;	86B 装着check & MASK
	mov	ax,0fd80h
	mov	es,ax
	cmp	word ptr es:[2],02a27h	;EPSON機？
	jnz	not_epson0
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
	jnz	checkexit_86b

	push	dx
	mov	dx,0a460h	;NEC OPNA ID port
	in	al,dx
	out	5fh,al
	and	al,0fch
	or	al,1
	out	dx,al		;NEC OPNA on
	pop	dx

	jmp	set_port

checkexit_86b:
	dec	ah
	jz	pc_error
	inc	dh
	jmp	checkloop_86b

;------------------------------------------------------------------------------
;	SPBのcheck
;------------------------------------------------------------------------------
check_spb:
;	86B 装着check & MASK
	mov	ax,0fd80h
	mov	es,ax
	cmp	word ptr es:[2],02a27h	;EPSON機？
	jnz	not_epson1
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

;------------------------------------------------------------------------------
;	ポート設定
;------------------------------------------------------------------------------
set_port:
	mov	[fm_port1],dx
	add	dx,2
	mov	[fm_port2],dx
	mov	[board],1
	clc
	ret

;------------------------------------------------------------------------------
;	音源が見つからなかった
;------------------------------------------------------------------------------
pc_error:
	mov	[board],0
	stc
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
usage:
	mov	ax,data
	mov	ds,ax

	print_mes	usage_mes
	error_exit	1

;==============================================================================
;	diskerror
;==============================================================================
diskerror:
	print_mes	disk_errmes
	error_exit	1

diskerror2:
	print_mes	cls
	print_mes	crt_return
	print_mes	disk_errmes
	error_exit	1

code	ends

data	segment

voice_number	db	?
cursor		dw	?

fm_port1	dw	?
fm_port2	dw	?
board		db	?
octarb		db	?

mml_mes		db	?
mml_vnum	db	?
mml_param	dw	?

notice_flag	db	?

key_table	label	byte
	db	00h		;esc
	db	36h		;rollup
	db	37h		;rolldown
	db	3ah		;up
	db	3dh		;down
	db	3bh		;left
	db	3ch		;right
	db	1ch		;cr
	db	10h		;q
	db	38h		;ins
	db	39h		;del
	db	62h		;f1
	db	63h		;f2
	db	64h		;f3
	db	65h		;f4
	db	67h		;f6
	db	68h		;f7
	db	69h		;f8
	db	6ah		;f9
	db	6bh		;f10
	db	3fh		;help
key_length	equ	21

key_jumptable	label	byte
	dw	main_exit
	dw	param_oneup
	dw	param_onedown
	dw	move_up
	dw	move_down
	dw	move_left
	dw	move_right
	dw	param_input
	dw	main_exit2
	dw	oct_up
	dw	oct_down
	dw	push_param
	dw	exchange_param
	dw	pop_param
	dw	pop_param_2
	dw	set_vname
	dw	write_mml3
	dw	write_mml4
	dw	write_mml1
	dw	write_mml2
	dw	notice_put

sound_c_table	db	1dh,29h,1eh,2ah,2bh,20h,2ch,21h,2dh,2eh
		db	23h,2fh,24h,30h,25h,31h,32h,27h,33h,28h
sound_length	equ	20

sound_buffer	label	byte
	dw	03d5h/2	; A-
	db	03h,20h	;a
	dw	0410h/2	; A
	db	05h,02h	;z
	dw	044eh/2	; B-
	db	03h,40h	;s
	dw	048fh/2	; B
	db	05h,04h	;x
	dw	026ah  	; C
	db	05h,08h	;c
	dw	028fh  	; D-
	db	04h,01h	;f
	dw	02b6h  	; D
	db	05h,10h	;v
	dw	02dfh  	; E-
	db	04h,02h	;g
	dw	030bh  	; E
	db	05h,20h	;b
	dw	0339h  	; F
	db	05h,40h	;n
	dw	036ah  	; G-
	db	04h,08h	;j
	dw	039eh  	; G
	db	05h,80h	;m
	dw	03d5h  	; A-
	db	04h,10h	;k
	dw	0410h  	; A
	db	06h,01h	;,
	dw	044eh  	; B-
	db	04h,20h	;l
	dw	048fh  	; B
	db	06h,02h	;.
	dw	026ah*2	; C
	db	06h,04h	;/
	dw	028fh*2	; D-
	db	04h,80h	;:
	dw	02b6h*2	; D
	db	06h,08h	;_
	dw	02dfh*2	; E-
	db	05h,01h	;]

escp		equ	01bh

mes_1		db	"; nm alg fbl",13,10,0
mes_2a		db	"; ar  dr  sr  rr  sl  tl  ks  ml  dt ams   seg",0
mes_2b		db	"; ar  dr  sr  rr  sl  tl  ks  ml  dt ams",0
mes_start	db	escp,"[01;74HProcesing$"
mes_fin		db	escp,"[01;74H      $"

title_mes	db	"Voice Editor for PMD .FF file with SSG-EG ver.1.9",13,10
		db	"      Programmed by M.Kajihara 2020.01.22",13,10
		db	13,10,"$"

usage_mes	db	"Usage: vedse filename[.FF]",13,10,"$"

disk_errmes	db	"File accessing failed.",13,10,"$"

complete_mes	db	escp,"Note: saved and finished.",13,10,"$"
exit_mes	db	escp,"Note: exited without saving.",13,10,"$"

screen	label	byte
	db	escp,"*[[[ PMD Voice Editor ver.1.9 ]]] / Programmed by M.Kajihara 2020.01.22",13,10
	db	escp,"[03;00H=================== Edit Area ==================="
	db	escp,"[25;00H================================================="
	db	escp,"[14;00H=================== Push Area ==================="
	db	escp,"[05;00H$"

base	label	byte
	db	"      NUM ALG FBL",13,10
	db	"      000 000 000",13,10
	db	"       AR  DR  SR  RR  SL  TL  KS  ML  DT AMS SEG",13,10
	db	"slot1 000 000 000 000 000 000 000 000 000 000 000",13,10
	db	"slot2 000 000 000 000 000 000 000 000 000 000 000",13,10
	db	"slot3 000 000 000 000 000 000 000 000 000 000 000",13,10
	db	"slot4 000 000 000 000 000 000 000 000 000 000 000",13,10,"$"

notice	label	byte
	db	escp,"[03;52H========= Key  Instructions ========="
	db	escp,"[04;52H---------- Playback System ----------"
	db	escp,"[05;52HFull key lower 2nd  Keyboard (c is C)"
	db	escp,"[06;52H            INS/DEL      Octave +1/-1"
	db	escp,"[07;52H---------- Editing  System ----------"
	db	escp,"[08;52H↑↓←→                  Cursor Movement"
	db	escp,"[09;52HAnyNumber/LBreak      Number Inputing"
	db	escp,"[10;52HRollUp/RollDown  		  Number +1/-1"
	db	escp,"[11;52HF1              		         ↓Push"
	db	escp,"[12;52HF2		                	↑↓Exchange"
	db	escp,"[13;52HF3              				  ↑Pop"
	db	escp,"[14;52HF4			              		  Undo"
	db	escp,"[15;52HF6			          Change Tone Name"
	db	escp,"[16;52H-------- MML Writing  System --------"
	db	escp,"[17;52HF7	            	   Single with SEG"
	db	escp,"[18;52HF8	            	Single without SEG"
	db	escp,"[19;52HF9	            	      All with SEG"
	db	escp,"[20;52HF10   				   All without SEG"
	db	escp,"[21;52H-------------- Others ---------------"
	db	escp,"[22;52HHELP             	 Key/Alg Switching"
	db	escp,"[23;52HESC		             Save and Quit"
	db	escp,"[24;52HQ                 Quit without Saving"
	db	escp,"[25;52H====================================="
	db	escp,"[16;00H$					 (check key_table)"

notice2	label	byte
	db	escp,"[03;52H========  Algorithms ========"
	db	escp,"[04;52H      ・・                     "
	db	escp,"[05;52H ALG0:・1・・・2・・・3・・・4→       "
	db	escp,"[06;52H      ・・                     "
	db	escp,"[07;52H ALG1:・1・・・3・・・4→           "
	db	escp,"[08;52H       2・・                   "
	db	escp,"[09;52H      ・・                     "
	db	escp,"[10;52H ALG2:・1・・・・・・・4→           "
	db	escp,"[11;52H       2・・・3・・               "
	db	escp,"[12;52H      ・・                     "
	db	escp,"[13;52H ALG3:・1・・・2・・・4→           "
	db	escp,"[14;52H           3・・               "
	db	escp,"[15;52H      ・・                     "
	db	escp,"[16;52H ALG4:・1・・・2→               "
	db	escp,"[17;52H       3・・・4→               "
	db	escp,"[18;52H      ・・ ・・2→               "
	db	escp,"[19;52H ALG5:・1・・・3→               "
	db	escp,"[20;52H         ・・4→       ・・      "
	db	escp,"[21;52H      ・・        ALG7:・1→    "
	db	escp,"[22;52H ALG6:・1・・・2→        2→    "
	db	escp,"[23;52H           3→        3→    "
	db	escp,"[24;52H           4→        4→    "
	db	escp,"[25;52H============================="
	db	escp,"[16;00H$"

octarb_mes	db	escp,"[05;38HOctave: $"
vname_mes	db	escp,"[05;21HName: "
vname		db	"       $"
nothing		db	"???????"
vname_cursor	db	escp,"[05;28H$"
normal		db	escp,"[37m$"
reverse		db	escp,"[47m$"
cls		db	escp,"[>1h",escp,"[>5h",escp,"*$"
crt_return	db	escp,"[>1l",escp,"[>5l$"
cursor_on	db	escp,"[>5l$"
cursor_off	db	escp,"[>5h$"
cursor_down	db	escp,"[11B$"
space		db	"   $"

table	label	byte
table_length	equ	13
;		offset,max,rot,opnadr,locate
	db	-1,255,0,000h,escp,"[06;07H$"	;num
able_lf	db	24,007,0,0b0h,escp,"[06;11H$"	;alg
t_fbl	db	24,007,3,0b0h,escp,"[06;15H$"	;fbl
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy
	db	00,000,0,000h,escp,"[00;00H$"	;dummy

able_up	db	08,031,0,050h,escp,"[08;07H$"	;ar
	db	12,031,0,060h,escp,"[08;11H$"	;dr
	db	16,031,0,070h,escp,"[08;15H$"	;sr
	db	20,015,0,080h,escp,"[08;19H$"	;rr
	db	20,015,4,080h,escp,"[08;23H$"	;sl
	db	04,127,0,040h,escp,"[08;27H$"	;tl
	db	08,003,6,050h,escp,"[08;31H$"	;ks
	db	00,015,0,030h,escp,"[08;35H$"	;ml
	db	00,007,4,030h,escp,"[08;39H$"	;dt
	db	12,001,7,060h,escp,"[08;43H$"	;ams
	db	00,015,-1,090h,escp,"[08;47H$"	;seg

	db	10,031,0,058h,escp,"[09;07H$"	;ar
	db	14,031,0,068h,escp,"[09;11H$"	;dr
	db	18,031,0,078h,escp,"[09;15H$"	;sr
	db	22,015,0,088h,escp,"[09;19H$"	;rr
	db	22,015,4,088h,escp,"[09;23H$"	;sl
	db	06,127,0,048h,escp,"[09;27H$"	;tl
	db	10,003,6,058h,escp,"[09;31H$"	;ks
	db	02,015,0,038h,escp,"[09;35H$"	;ml
	db	02,007,4,038h,escp,"[09;39H$"	;dt
	db	14,001,7,068h,escp,"[09;43H$"	;ams
	db	02,015,-1,098h,escp,"[09;47H$"	;seg

	db	09,031,0,054h,escp,"[10;07H$"	;ar
	db	13,031,0,064h,escp,"[10;11H$"	;dr
	db	17,031,0,074h,escp,"[10;15H$"	;sr
	db	21,015,0,084h,escp,"[10;19H$"	;rr
	db	21,015,4,084h,escp,"[10;23H$"	;sl
	db	05,127,0,044h,escp,"[10;27H$"	;tl
	db	09,003,6,054h,escp,"[10;31H$"	;ks
	db	01,015,0,034h,escp,"[10;35H$"	;ml
	db	01,007,4,034h,escp,"[10;39H$"	;dt
	db	13,001,7,064h,escp,"[10;43H$"	;ams
	db	01,015,-1,094h,escp,"[10;47H$"	;seg

able_dw	db	11,031,0,05ch,escp,"[11;07H$"	;ar
	db	15,031,0,06ch,escp,"[11;11H$"	;dr
	db	19,031,0,07ch,escp,"[11;15H$"	;sr
	db	23,015,0,08ch,escp,"[11;19H$"	;rr
	db	23,015,4,08ch,escp,"[11;23H$"	;sl
	db	07,127,0,04ch,escp,"[11;27H$"	;tl
	db	11,003,6,05ch,escp,"[11;31H$"	;ks
	db	03,015,0,03ch,escp,"[11;35H$"	;ml
	db	03,007,4,03ch,escp,"[11;39H$"	;dt
	db	15,001,7,06ch,escp,"[11;43H$"	;ams
able_rg	db	03,015,-1,09ch,escp,"[11;47H$"	;seg

push_buffer	db	25 dup(0)

buffer		db	128 dup(?)
ff_filename	db	128 dup(?)
mml_filename	db	128 dup(?)
mml_buffer	db	512 dup(?)
ff_buffer	db	32*256 dup(?)
ff_buffer2	db	32*256 dup(?)

data	ends

stack	segment	stack

	db	512 dup(?)

stack	ends

end	start

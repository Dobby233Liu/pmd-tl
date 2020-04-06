;==============================================================================
;	音長計算用 include file
;		in.al	print_flag (0で非表示)
;==============================================================================
_print_mes	macro	ofs
local	exit
	cmp	[print_flag],0
	jz	exit
	print_mes	ofs
exit:
	endm

lc	proc
	push	ds
	push	es

	mov	dx,m_seg
	mov	ds,dx

	mov	dx,cs
	mov	es,dx

	call	calc_start

	pop	es
	pop	ds
	ret

	assume	cs:code,ds:m_seg,es:code

;==============================================================================
;	計算開始
;==============================================================================
calc_start:
	mov	[print_flag],al

	mov	[part_chr],"A"
	mov	bp,offset m_buf

;==============================================================================
;	パート毎のループ
;==============================================================================
part_loop:
	mov	si,ds:[bp]
	add	si,offset m_buf
	inc	bp
	inc	bp
part_loop2:
	mov	[all_length],0
	mov	[all_length+2],0
	mov	[loop_length],-1
	mov	[loop_length+2],-1
	mov	[loop_flag],0

;==============================================================================
;	(Part Aの場合) 拡張のFM3ch目があるか調べる
;==============================================================================
	cmp	[part_chr],"A"
	jnz	check_j
	cmp	byte ptr [si],0c6h
	jnz	check_j
	inc	si

	push	di
	push	es
	mov	ax,cs
	mov	es,ax
	mov	di,offset fm3_adr1
	mov	cx,3
rep	movsw
	pop	es
	pop	di

;==============================================================================
;	(Part Jの場合) 拡張のPCMパートがあるか調べる
;==============================================================================
check_j:
	cmp	[part_chr],"J"
	jnz	com_loop
	cmp	byte ptr [si],0b4h
	jnz	com_loop
	inc	si

	push	di
	push	es
	mov	ax,cs
	mov	es,ax
	mov	di,offset pcm_adr1
	mov	cx,8
rep	movsw
	pop	es
	pop	di

;==============================================================================
;	コマンド毎のループ
;==============================================================================
com_loop:
	lodsb
	cmp	al,80h
	jz	part_ends
	jnc	cl_00
	lodsb
	xor	ah,ah
	add	[all_length],ax
	adc	[all_length+2],0
	jmp	com_loop
cl_00:
	call	command_exec
	cmp	[loop_flag],0
	jnz	part_ends
	jmp	com_loop

;==============================================================================
;	パート終了
;==============================================================================
part_ends:
	call	print_length

	inc	[part_chr]
	cmp	[part_chr],"K"
	jc	part_loop

	push	di
	push	bx

	mov	di,offset fm3_adr1	;in cs
	mov	bx,offset _fm3_partchr1	;in cs
	mov	cx,3+8

extend_check_loop:
	mov	si,cs:[di]
	or	si,si
	jz	extend_check_next
	add	si,offset m_buf
	mov	al,cs:[bx]
	mov	[part_chr],al
	mov	word ptr cs:[di],0
	pop	bx
	pop	di
	jmp	part_loop2

extend_check_next:
	inc	di
	inc	di
	inc	bx
	loop	extend_check_loop
	pop	bx
	pop	di

	jmp	partk_start

;==============================================================================
;	Part	K
;==============================================================================
partk_start:
	mov	[part_chr],"K"
	mov	[all_length],0
	mov	[all_length+2],0
	mov	[loop_length],-1
	mov	[loop_length+2],-1
	mov	[loop_flag],0

	mov	si,ds:[bp]
	add	si,offset m_buf
	inc	bp
	inc	bp
	mov	bx,ds:[bp]
	add	bx,offset m_buf	; bx= R table 先頭番地

;==============================================================================
;	Kpart/コマンド毎のループ
;==============================================================================
kcom_loop:
	lodsb
	cmp	al,80h
	jz	kpart_end
	jnc	kl_00
	xor	ah,ah
	add	ax,ax
	push	si
	push	bx
	add	bx,ax
	mov	si,[bx]
	add	si,offset m_buf
	call	rcom_loop
	pop	bx
	pop	si
	cmp	[loop_flag],0
	jnz	kpart_end
	jmp	kcom_loop

;==============================================================================
;	Kpart/各種特殊コマンド
;==============================================================================
kl_00:
	push	bx
	call	command_exec
	pop	bx
	cmp	[loop_flag],0
	jnz	kpart_end
	jmp	kcom_loop

;==============================================================================
;	Kpart/計算終了
;==============================================================================
kpart_end:
	call	print_length
	ret

;==============================================================================
;	Rpart/コマンド毎のループ
;==============================================================================
rcom_loop:
	lodsb
	cmp	al,0ffh
	jz	rpart_end
	cmp	al,0c0h
	jnc	rl_00
	or	al,al
	jns	rl_01
	inc	si
rl_01:
	lodsb
	xor	ah,ah
	add	[all_length],ax
	adc	[all_length+2],0
	jmp	rcom_loop
	
;==============================================================================
;	Rpart/各種特殊コマンド処理
;==============================================================================
rl_00:
	call	command_exec
	cmp	[loop_flag],0
	jnz	rpart_end
	jmp	rcom_loop

;==============================================================================
;	Rpart/計算終了
;==============================================================================
rpart_end:
	ret

;==============================================================================
;	各種コマンド
;==============================================================================
command_exec:
	not	al
	xor	ah,ah
	add	ax,ax
	add	ax,offset jumptable
	mov	bx,ax
	mov	ax,cs:[bx]
	jmp	ax

jump16:	add	si,10
jump6:	inc	si
jump5:	inc	si
jump4:	inc	si
jump3:	inc	si
jump2:	inc	si
jump1:	inc	si
jump0:	ret

;==============================================================================
;	tempo
;==============================================================================
_tempo:
	lodsb
	cmp	al,251
	jc	tempo_ret
	inc	si	;相対
tempo_ret:
	ret

;==============================================================================
;	ポルタメント
;==============================================================================
porta:
	inc	si
	inc	si
	lodsb
	xor	ah,ah
	add	[all_length],ax
	adc	[all_length+2],0
	ret

;==============================================================================
;	L command
;==============================================================================
loop_set:
	mov	ax,[all_length]
	mov	[loop_length],ax
	mov	ax,[all_length+2]
	mov	[loop_length+2],ax
	ret

;==============================================================================
;	[ command
;==============================================================================
loop_start:
	lodsw
	mov	bx,ax
	add	bx,offset m_buf+1
	mov	byte ptr [bx],0
	ret

;==============================================================================
;	] command
;==============================================================================
loop_end:
	lodsb
	or	al,al
	jz	loop_fset	;無条件loopがあった
	mov	ah,al
	inc	byte ptr [si]
	lodsb
	cmp	ah,al
	jnz	reloop
	inc	si
	inc	si
	ret

reloop:	lodsw
	add	ax,offset m_buf+2
	mov	si,ax
	ret

loop_fset:
	mov	[loop_flag],1
	ret

;==============================================================================
;	: command
;==============================================================================
loop_exit:
	lodsw
	mov	bx,ax
	add	bx,offset m_buf
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
;	0c0h + ?? special control
;==============================================================================
special_0c0h:
	lodsb
	cmp	al,2
	jc	spc0_ret
	not	al
	xor	ah,ah
	add	ax,ax
	add	ax,offset jumptable_0c0h
	mov	bx,ax
	mov	ax,cs:[bx]
	jmp	ax
spc0_ret:
	ret

;==============================================================================
;	長さを表示
;==============================================================================
print_length:
	push	ds
	mov	ax,cs
	mov	ds,ax
	assume	ds:code

	mov	ax,[all_length]
	or	ax,[all_length+2]
	jz	pe_01		;データ無し
	_print_mes	part_mes
	mov	ax,[all_length]
	mov	dx,[all_length+2]

	mov	bx,[max_all]
	mov	cx,[max_all+2]
	sub	bx,ax
	sbb	cx,dx
	jnc	not_over_all
	mov	[max_all],ax
	mov	[max_all+2],dx
not_over_all:
	call	print_32

	cmp	[loop_flag],1
	jnz	pe_loop
	_print_mes	loop_mes2
	jmp	pe_01

pe_loop:
	mov	dx,[loop_length+2]
	mov	ax,[loop_length]
	add	ax,1
	adc	dx,0
	or	ax,dx
	jz	pe_00

	_print_mes	loop_mes
	mov	ax,[all_length]
	mov	dx,[all_length+2]
	sub	ax,[loop_length]
	sbb	dx,[loop_length+2]

	mov	bx,[max_loop]
	mov	cx,[max_loop+2]
	sub	bx,ax
	sbb	cx,dx
	jnc	not_over_loop
	mov	[max_loop],ax
	mov	[max_loop+2],dx
not_over_loop:
	call	print_32
pe_00:
	_print_mes	_crlf_mes
pe_01:
	pop	ds
	assume	ds:m_seg
	ret

;==============================================================================
;	Print DX:AX (32 bit)
;==============================================================================
print_32:
	cmp	[print_flag],0
	jz	p32_ret

	push	ax
	push	dx
	xor	bh,bh
	mov	cx,9
	mov	si,offset num_data
p32_loop:
	call	sub_pr
	add	si,4
	loop	p32_loop
	mov	dl,al
	add	dl,"0"
	mov	ah,2
	int	21h
	pop	dx
	pop	ax
p32_ret:
	ret	

sub_pr:
	mov	bl,"0"
sub_pr_loop:
	inc	bl
	sub	ax,[si]
	sbb	dx,[si+2]
	jnc	sub_pr_loop
	add	ax,[si]
	adc	dx,[si+2]
	dec	bl

	cmp	bl,"0"
	jnz	sub_pr_prt
	or	bh,bh
	jz	sub_pr_ret
sub_pr_prt:
	mov	bh,1
	push	ax
	push	dx
	mov	dl,bl
	mov	ah,2
	int	21h
	pop	dx
	pop	ax
sub_pr_ret:
	ret

num_data	dd	1000000000
		dd	100000000
		dd	10000000
		dd	1000000
		dd	100000
		dd	10000
		dd	1000
		dd	100
		dd	10

jumptable	dw	jump1		;0ffh
		dw	jump1
		dw	jump1
		dw	_tempo
		dw	jump0
		dw	jump2
		dw	loop_start
		dw	loop_end	;0f8h
		dw	loop_exit
		dw	loop_set
		dw	jump1
		dw	jump0
		dw	jump0
		dw	jump4
		dw	jump1
		dw	jump4		;0f0h
		dw	jump2
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1		;0e8h
		dw	jump1
		dw	jump1
		dw	jump2
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1		;0e0h
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	porta
		dw	jump1
		dw	jump1		;0d8h
		dw	jump1
		dw	jump2
		dw	jump2
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1		;0d0h
		dw	jump1
		dw	jump6
		dw	jump5
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump3		;0c8h
		dw	jump3
		dw	jump6
		dw	jump1
		dw	jump1
		dw	jump2
		dw	jump1
		dw	jump0
		dw	special_0c0h	;0c0h
		dw	jump4
		dw	jump1
		dw	jump2
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump2		;0b8h
		dw	jump1
		dw	jump1
		dw	jump2
		dw	jump16		;0b4h
		dw	jump1		;0b3h
		dw	jump1		;0b2h
		dw	jump1		;0b1h

jumptable_0c0h	dw	jump1		;0ffh
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1
		dw	jump1		;0f8h
		dw	jump1
		dw	jump1
		dw	jump1

part_mes	db	"Part "
part_chr	db	" "
		db	9,"Length: $"
loop_mes	db	9,"/ Loop: $"
loop_mes2	db	9,"/ Found infinite local loop!"
_crlf_mes	db	13,10,"$"

print_flag	db	0
all_length	dw	0
		dw	0
loop_length	dw	0
		dw	0
max_all		dw	0
		dw	0
max_loop	dw	0
		dw	0
fm3_adr1	dw	0
fm3_adr2	dw	0
fm3_adr3	dw	0
pcm_adr1	dw	0
pcm_adr2	dw	0
pcm_adr3	dw	0
pcm_adr4	dw	0
pcm_adr5	dw	0
pcm_adr6	dw	0
pcm_adr7	dw	0
pcm_adr8	dw	0
loop_flag	db	0
_fm3_partchr1	db	0
_fm3_partchr2	db	0
_fm3_partchr3	db	0
_pcm_partchr1	db	0
_pcm_partchr2	db	0
_pcm_partchr3	db	0
_pcm_partchr4	db	0
_pcm_partchr5	db	0
_pcm_partchr6	db	0
_pcm_partchr7	db	0
_pcm_partchr8	db	0

lc	endp

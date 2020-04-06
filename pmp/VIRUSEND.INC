;
;	ViruschkŒã‚É‚»‚ÌŽ|•\Ž¦‚·‚é
;
	mov	dx,cs
	mov	ds,dx

	mov	dx,offset virus_mes
	dec	ax
	jz	vprint_end
	mov	dx,offset rename_mes
	jmp	vprint_end

rename_mes	db	"NOTICE: The executable file name has been renamed.",13,10,"$"
virus_mes	db	"WARNING: This program may have been infected by a virus.",13,10,"$"

vprint_end:
	mov	ah,9
	int	21h

include sys.inc

.model tiny
.code
.386
locals

org 100h


do_startup proc
    finit
    
    mov     ax, cs
    mov     ds, ax
    mov     es, ax

    call    alloc_seg
    or      ax, ax
    jz      quit_me
    mov     buffer_seg, ax

    call    timer_setup

    mov     ax, 13h
    int     10h
    ret
quit_me:
    mov     ah, 4ch
    int     21h
endp

do_shutdown proc
    mov     ax, 3h
    int     10h
    mov     ax, buffer_seg
    call    free_seg

    call    timer_shutdown

    mov     ah, 4ch
    int     21h
endp

copy_buffer proc

comment #
      ; copy via coprocessor
    push    ds
    push    es
    mov     ds, buffer_seg
    xor     si, si
    mov     ax, 0a000h
    mov     es, ax
    xor     di, di
    mov     cx, 64000/8
cb_copy:
    fld     qword ptr [si]
    add     si, 8
    fstp    qword ptr es:[di]
    add     di, 8
    dec     cx
    jnz     cb_copy
    pop     ds
    pop     es
#

    push    ds
    push    es
    mov     ds, buffer_seg
    xor     si, si
    mov     ax, 0a000h
    mov     es, ax
    xor     di, di
    mov     cx, 16000
    cld
    rep     movsd
    pop     es
    pop     ds

    ret
endp

clear_buffer proc
    push    es
    mov     es, buffer_seg
    xor     di, di
    xor     eax, eax
    mov     cx, 16000
    cld
    rep     stosd
    pop     es
    ret
endp

wait_for_vsync proc
    mov     dx, 03dah
r1:
    in      al, dx
    test    al, 8
    jz      r1
r2:
    in      al, dx
    test    al, 8
    jnz     r2
    ret
endp

;------------------------------------------------------------
;    in:    si - offset to palette
;    out:    none
;------------------------------------------------------------

set_palette proc
    mov     dx, 03c8h
    xor     ax, ax
    out     dx, al
    inc     dx
    mov     cx, 768
    cld
    rep     outsb
    ret
endp

;------------------------------------------------------------
;    in:    di - offset to palette
;    out:    none
;------------------------------------------------------------

get_palette proc
    mov     dx, 03c7h
    xor     ax, ax
    out     dx, al
    add     dx, 2
    mov     cx, 768
    cld
    rep     insb
    ret
endp

;------------------------------------------------------------
;    in:    none
;    out:    ax - segment number (0 if error occured)
;------------------------------------------------------------

alloc_seg proc
    mov     ah, 4ah
    mov     bx, 1000h
    int     21h
    mov     ah, 48h
    mov     bx, 1000h
    int     21h
    jc      as_no_mem
    ret
as_no_mem:
    xor     ax, ax
    ret
endp

;------------------------------------------------------------
;    in:    ax - segment number
;    out:    none
;------------------------------------------------------------

free_seg proc
    push    es
    mov     es, ax
    mov     ah, 49h
    int     21h
    pop     es
    ret
endp

init_font proc
    push    bp
    push    ds
    push    es

    mov     ax, 01130h
    mov     bh, 03h
    int     10h

    mov     ax, es
    mov     ds, ax
    mov     si, bp

    mov     ax, cs
    mov     es, ax
    mov     di, offset font_data

    mov     cx, 2048/4
    cld
    rep     movsd

    pop     es
    pop     ds
    pop     bp
    ret
endp

;------------------------------------------------------------
;    in:    si - offset to null-terminated string
;        al - color
;        cx - x
;        dx - y
;    out:    none
;------------------------------------------------------------

put_string proc
    push    es
    mov     es, buffer_seg

    mov     di, dx
    shl     di, 6
    shl     dx, 8
    add     di, dx
    add     di, cx

    mov     ah, al
ps_char:
    lodsb
    or      al, al
    jz      ps_quit

      ; draw letter
    push    di
    mov     dl, ah
    movzx   bx, al
    shl     bx, 3
    add     bx, offset font_data

    mov     ch, 8
ps_hor:
    mov     cl, 8
    mov     al, byte ptr [bx]
ps_ver:
    rcl     al, 1
    jae     ps_next
    mov     byte ptr es:[di], dl
ps_next:
    inc     di
    dec     cl
    jnz     ps_ver
    inc     bx
    add     di, 312
    inc     dl
    dec     ch
    jnz     ps_hor
    pop     di

      ; next letter
    add     di, 8
    jmp     ps_char
ps_quit:
    pop     es
    ret
endp

;************************************************************
;
;       Timer routines
;
;************************************************************

TIMES_FASTER equ 15
DOS_DIVISOR equ 65535
MY_DIVISOR equ DOS_DIVISOR / TIMES_FASTER

TIMER_WAIT_TICKS equ 6


timer_wait proc
@@wait_loop:
    mov     eax, timer_now
    cmp     eax, timer_stop
    jg      @@wait_break
    hlt
    jmp     @@wait_loop

@@wait_break:
    mov     eax, TIMER_WAIT_TICKS
    add     eax, timer_now
    mov     timer_stop, eax
    ret
endp

timer_setup proc
    push    es
    mov     ax, 351ch
    int     21h
    mov     word ptr [dos_timer_interrupt], bx
    mov     word ptr [dos_timer_interrupt+2], es
    pop     es

    push    ds
    mov     dx, offset timer_interrupt
    mov     ax, 251ch
    int     21h
    pop     ds

    mov     dx, 43h
    mov     al, 34h
    out     dx, al
    mov     dx, 40h
    mov     al, 11h ; MY_DIVISOR & 0xff
    out     dx, al
    mov     al, 11h ; ( MY_DIVISOR >> 8 ) & 0xff
    out     dx, al

    ret
endp

timer_shutdown proc
    push    ds
    mov     dx, word ptr [dos_timer_interrupt]
    mov     ax, word ptr [dos_timer_interrupt+2]
    mov     ds, ax
    mov     ax, 251ch
    int     21h
    pop     ds
   
    mov     dx, 43h
    mov     al, 34h
    out     dx, al
    mov     dx, 40h
    mov     al, -1
    out     dx, al
    out     dx, al

    ret
endp

timer_interrupt proc
    pushad
    push    cs
    pop     ds

    mov     eax, timer_now
    inc     eax
    mov     timer_now, eax

    mov     eax, timer_dos
    inc     eax
    cmp     eax, TIMES_FASTER
    jb      @@skip_old_interrupt
    xor     eax, eax
    mov     timer_dos, eax
    pushf
    call    dword ptr [dos_timer_interrupt]

@@skip_old_interrupt:

    popad
    iret
endp

;************************************************************
;
;       Frame saver
;
;************************************************************

save_palette proc
    push    si
    push    di
    mov     di, offset saved_palette
    mov     cx, 256

@@iter_color:
    lodsb
    shl     al, 2
    push    ax
    lodsb
    shl     al, 2
    push    ax
    lodsb
    shl     al, 2
    stosb
    pop     ax
    stosb
    pop     ax
    stosb
    xor     al, al
    stosb
    dec     cx
    jnz     @@iter_color
    pop     di
    pop     si
    ret
endp

; -> ax = value to convert
; -> di = offset to convert buffer
integer_to_string proc
    push    ax
    cmp     ax, 10
    jb      @@fill_below_10
    cmp     ax, 100
    jb      @@fill_below_100
    cmp     ax, 1000
    jb      @@fill_below_1000
    cmp     ax, 10000
    jb      @@fill_below_10000
    jmp     @@fill_below_100000

@@fill_below_10:
    mov     cx, 6
    jmp     @@fill
@@fill_below_100:
    mov     cx, 5
    jmp     @@fill
@@fill_below_1000:
    mov     cx, 4
    jmp     @@fill
@@fill_below_10000:
    mov     cx, 3
    jmp     @@fill
@@fill_below_100000:
    mov     cx, 2
@@fill:
    mov     al, '0'
    cld
    rep     stosb
    pop     ax

@@convert:
    mov     bx, 10
    xor     cx, cx

@@icon:
    xor     dx, dx
    div     bx
    push    dx
    inc     cx
    or      ax, ax
    jnz     @@icon

@@imake:
    pop     ax
    add     al, '0'
    stosb
    dec     cx
    jnz     @@imake
    ret
endp

write_buffer_to_file proc
    pusha

    mov     ax, word ptr [file_counter]
    inc     ax
    mov     word ptr [file_counter], ax
    mov     di, offset generate_filename + 1
    call    integer_to_string

    ; Create and close file
    mov     ah, 3ch
    xor     cx, cx
    mov     dx, offset generate_filename
    int     21h
    jc      @@error_creating_file
    mov     bx, ax
    mov     ah, 3eh
    int     21h

    ; Open file for writing
    mov     ah, 3dh
    mov     al, 1
    push    cs
    pop     ds
    mov     dx, offset generate_filename
    int     21h
    jc      @@error_opening_file
    push    ax
    push    ax

    ; Write to file
    pop     bx
    mov     ah, 40h
    mov     dx, offset bmp_header
    mov     cx, 54
    int     21h

    mov     ah, 40h
    mov     dx, offset saved_palette
    mov     cx, 1024
    int     21h

    mov     ax, word ptr [buffer_seg]
    push    ds
    mov     ds, ax
    mov     si, 64000 - 320
    mov     cx, 200
@@write_bmp:
    mov     dx, si
    mov     ah, 40h
    push    cx
    mov     cx, 320
    int     21h
    sub     si, 320
    pop     cx
    dec     cx
    jnz     @@write_bmp

;    mov     ah, 40h
;    mov     dx, offset generate_filename
;    mov     cx, 64000
;    int     21h
    pop     ds

    ; Close file
    mov     ah, 3eh
    pop     bx
    int     21h
    popa
    mov     ax, 1
    ret

@@error_creating_file: 
    mov     dx, offset error_create_txt
    jmp     @@error_exit

@@error_opening_file: 
    mov     dx, offset error_open_txt

@@error_exit:
    popa
    mov     ax, 0
    ret
endp

.data

timer_dos dd 0
timer_now dd 0
timer_stop dd TIMER_WAIT_TICKS

error_create_txt db 'Cannot create file$'
error_open_txt db 'Cannot open file$'

file_counter dw 0
generate_filename db 'f', 7 dup(?), '.bmp', 0

bmp_header db 66, 77, 54, 254, 0, 0, 0, 0, 0, 0, 54, 4, 0, 0, 40, 0, 0, 0, 64, 1, 0, 0, 200, 0, 0, 0, 1, 0, 8, 0, 0, 0, 0, 0, 0, 254, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

.data?

dos_timer_interrupt dd ?

font_data db 2048 dup(?)
buffer_seg dw ?

saved_palette db 1024 dup(?)

end

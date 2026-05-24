section .rodata
    SYS_EXIT        equ 60
    SYS_WRITE       equ 1
    STD_OUT_FD      equ 1

section .bss
    align 8
    target_n resq 1

section .text
global _start

_start:
    ; Wczytanie parametru n
    mov rbp, [rsp]      ; if(argc != 2)
    cmp rbp, 2          ;   exit(1)
    jne .exit_error

    mov rbp, [rsp + 16] ; argv[1]
    xor rcx, rcx        ; byte index of n ; i = 0
    xor rdi, rdi        ; result_n = 0
.parse_n_loop:
    movzx rbx, byte [rbp + rcx] ; bl = argv[1][i]

    test bl, bl         ; test end of word
    jz .parse_n_done

    cmp bl, '0'         ; if (c < '0')
    jb .exit_error      ;   exit(1)

    cmp bl, '9'         ; if (c > '9')
    ja .exit_error      ;   exit(1)

    sub rbx, '0'

    imul rdi, 10        ; result_n *= 10
    add  rdi, rbx       ; add current  digit to result

    inc rcx             ; ++i
    jmp .parse_n_loop

.parse_n_done:
    mov [rel target_n], rdi ; Save n in global variable


.exit:
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall


.exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
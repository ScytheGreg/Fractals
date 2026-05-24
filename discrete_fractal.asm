section .rodata
    SYS_EXIT        equ 60
    SYS_READ        equ 0
    STD_IN_FD       equ 0
    SYS_WRITE       equ 1
    STD_OUT_FD      equ 1
    SYS_MMAP        equ 9

    PROT_FLAGS      equ 3      ; PROT_READ | PROT_WRITE
    MAP_FLAFS       equ 0x22   ; MAP_PRIVATE | MAP_ANONYMOUS

section .bss
    align 8
    target_n resq 1

    read_buf    resq 1      ; Read buffer beggining pointer
    read_size   resq 1      ; Input length

section .text
global _start

_start:
;%%%%% PARSE 'n' PARAMETER %%%%%
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

    imul edi, 10        ; result_n *= 10
    jc   .exit_error    ; overflow
    add  edi, ebx       ; add current  digit to result
    jc   .exit_error    ; overflow

    inc rcx                 ; ++i
    jmp .parse_n_loop

.parse_n_done:
    mov [rel target_n], rdi ; Save n in a global variable


;%%%% READ INPUT to READ BUFFER %%%%%

    ; Init read buffer
    xor rbx, rbx            ; Size of allocated memory for read buffer

.read_loop:

    ; Make space for


    mov rax, SYS_READ
    mov rdi, STD_IN_FD
    lea rsi, [rel read_buf]
    mov rdx, 4              ; Max number of read characters - just for tests
    syscall

    test rax, rax           ; if EOF
    jz .read_done           ;   break

    cmp rax, -4095          ; Read error
    jae .exit_error         ;   exit(1)

    add [rel read_size], rax ; Add number of read digits to string length
    jmp .read_loop

.read_done:
    mov rax, [rel read_size]

.exit:
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall


.exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
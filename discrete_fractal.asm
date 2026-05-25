section .rodata
    SYS_EXIT        equ 60
    SYS_READ        equ 0
    STD_IN_FD       equ 0
    SYS_WRITE       equ 1
    STD_OUT_FD      equ 1
    SYS_MMAP        equ 9
    SYS_MUNMAP      equ 11

    PROT_FLAGS      equ 3      ; PROT_READ | PROT_WRITE
    MAP_FLAGS       equ 0x22   ; MAP_PRIVATE | MAP_ANONYMOUS

section .bss
    align 8
    target_n resq 1

    read_buf        resq 1      ; Read buffer beggining pointer
    read_cup        resq 1      ; Read buffer cup
    read_len        resq 1      ; Input length
    first_line_len  resq 1      ; Length of first line

    ; Pattern array
    ;typedef struct pattern_node{
    ;      size_t pointer
    ;      size_t length
    ;}
    ; Every supported ascii number (from 33 to 126) takes two qwords

    pattern     resq 188    ; (126 - 32) * 2



section .text

default rel

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
    mov [target_n], rdi ; Save n in a global variable


;%%%% READ INPUT to READ BUFFER %%%%%

    ; Init read buffer
    xor rbx, rbx            ; Size of allocated memory for read buffer
    mov r13, 1024           ; This amount we want to be allocated
    xor r12, r12            ; Writing lenght

.read_loop:
    ; Make space for data
    cmp rbx, r13
    jae .space_buf_ok
    ; No space for input

    ; MMAP
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, r13            ; This amount we want to allocata
    mov rdx, PROT_FLAGS
    mov r8, -1              ; Requiered for anonymous
    xor r9, r9              ; Offset = 0
    mov r10, MAP_FLAGS
    syscall

    cmp rax, -4095          ; Handle errors
    jae .exit_error

    mov rbp, rax            ; Save read buffer

    test rbx, rbx           ; If nothing to copy, skip
    jz .copy_done

    ; Copy old
    mov rdi, rax            ; Destination
    mov rsi, [read_buf]     ; Source
    mov rcx, r12            ; Reps (Current read length)
    rep movsb               ; Chunk fast copy

    ; Free old
    mov rax, SYS_MUNMAP
    mov rdi, [read_buf]     ; Source
    mov rsi, rbx            ; Length
    syscall

    cmp rax, -4095          ; Handle errors
    jae .exit_error

.copy_done:
    mov [read_buf], rbp             ; Save read buffer adress
    mov rbx, r13                    ; Update amount of allocated memory

.space_buf_ok:
    mov rax, SYS_READ
    mov rdi, STD_IN_FD
    mov rsi, [read_buf]
    add rsi, r12
    mov rdx, rbx                    ; Max number of read characters - remaining space
    sub rdx, r12
    syscall

    cmp rax, -4095                  ; Handle errors
    jae .exit_error                 ;   exit(1)

    test rax, rax                   ; if EOF
    jz .read_done                   ;   break

    add r12, rax                    ; Add number of read digits to string length

    cmp rbx, r12                    ; If no whole memory is used
    jne .read_loop                  ;       do not double memory
    shl r13, 1                      ; Double needed memory
    jmp .read_loop

.read_done:
    mov [read_len], r12
    mov [read_cup], rbx

;%%%% PARSE INPUT %%%%

    ; Find newline
    mov rdi, [read_buf]         ; Sign pointer
    lea rsi, [rdi + r12]        ; Bound
.first_line_loop:
    cmp rdi, rsi                ; Test bounds
    ja .exit_error              ; Out of bound - no newline found

    movzx bl, [rdi]             ; Load sign
    inc rdi;                    ; index ++

    cmp bl, '\n'                ; Check for newline
    je .first_line_end          ;

    jmp .first_line_loop

.first_line_end:


.exit:
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall


.exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
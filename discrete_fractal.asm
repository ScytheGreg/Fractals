section .rodata
    SYS_EXIT        equ 60
    SYS_READ        equ 0
    STD_IN_FD       equ 0
    SYS_WRITE       equ 1
    STD_OUT_FD      equ 1
    SYS_MMAP        equ 9
    SYS_MUNMAP      equ 11

    NEW_LINE        equ 10

    PROT_FLAGS      equ 3      ; PROT_READ | PROT_WRITE
    MAP_FLAGS       equ 0x22   ; MAP_PRIVATE | MAP_ANONYMOUS

section .bss
    align 8
    target_n resq 1

    read_buf        resq 1      ; Read buffer beggining pointer
    read_cup        resq 1      ; Read buffer cup - end of allocated memory
    read_end        resq 1      ; Read input end pointer
    first_line_end  resq 1      ; Length of first line

    ; Pattern array
    ;typedef struct pattern_node{
    ;      size_t start
    ;      size_t end
    ;}
    ; Every supported ascii number (from 33 to 126) takes two qwords

    patterns        resq 188     ; (126 - 32) * 2



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

    ; Registers:
    ; rbp                   - read buffer start pointer
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
    lea rcx, [rbp + r12]
    mov [read_end], rcx
    lea rcx, [rbp + rbx]
    mov [read_cup], rcx

;%%%% PARSE INPUT %%%%

    ; Find newline
    mov rdi, [read_buf]         ; Sign pointer
    mov rsi, [read_end]         ; Bound
.first_line_loop:
    cmp rdi, rsi                ; Test bounds
    ja .exit_error              ; Out of bound - no newline found

    movzx ebx, byte [rdi]        ; Load sign
    inc rdi;                     ; index ++

    cmp bl, NEW_LINE            ; Check for newline
    je .first_line_end          ;

    jmp .first_line_loop

.first_line_end:
    mov [first_line_end], rdi

.read_pattern:
    cmp rdi, rsi                ; Test bound
    ja .input_parse_done        ; End of patterns - done

    movzx ebx, byte [rdi]       ; Load sign
    inc rdi                     ; index++

    cmp bl, 33                  ; Lowwerbound
    jb .exit_error

    cmp bl, 126                 ; Upperbound
    ja .exit_error

    sub bl, 33                  ; Normalize sign for array indexing
    movzx rax, bl               ; rax will keep the sign we pattern
    mov rdx, rdi                ; rdx will keep the start position of pattern
    inc rdx

; For given sign read swap characters
.read_rule_loop:
    cmp rdi, rsi                ; Test bound
    ja .exit_error              ; No new line at the end of the rule

    movzx ebx, byte [rdi]       ; Load sign
    inc rdi                     ; index++

    cmp bl, NEW_LINE            ; End of the rule
    je .rule_found

    jmp .read_rule_loop

.rule_found:
    lea rcx, [patterns]
    shl rax, 4                  ; 2^4 = 16 - frame size of pattern_nodo
    mov [rcx + rax], rdx        ; pattern_node.start
    mov [rcx + rax + 8] , rdi   ; pattern_node.end

    jmp .read_pattern

.input_parse_done:


.exit:
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall


.exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
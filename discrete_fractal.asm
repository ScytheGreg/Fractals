section .rodata
    SYS_READ        equ 0
    SYS_WRITE       equ 1
    SYS_MMAP        equ 9
    SYS_MUNMAP      equ 11
    SYS_EXIT        equ 60

    STD_IN_FD       equ 0
    STD_OUT_FD      equ 1
    NEW_LINE        equ 10

    PROT_FLAGS      equ 3      ; PROT_READ | PROT_WRITE
    MAP_FLAGS       equ 0x22   ; MAP_PRIVATE | MAP_ANONYMOUS

section .bss
    align 8
    target_n resq 1

    read_buf        resq 1      ; Read buffer start
    read_cup        resq 1      ; Read buffer cup - the size of allocated memory
    read_end        resq 1      ; Read input end

    first_line_end  resq 1      ; Length of first line

    write_buf       resq 1      ; Write buffer start
    write_end       resq 1      ; Write buffer end

    stack_buf       resq 1      ; Stack buffer start
    stack_end       resq 1      ; Stack buffer end

    ; Pattern array and stack structure:
    ; typedef struct pattern_node (stack_node) {
    ;       size_t start
    ;       size_t end
    ; }
    ; Every supported ascii number (from 33 to 126) takes two qwords

    patterns        resq 188     ; (126 - 32) * 2

section .text
default rel
global _start

memory_cleanup:
    ; Read buffer cleanup
    mov rax, SYS_MUNMAP
    mov rdi, [read_buf]         ; Source
    mov rsi, [read_cup]         ; Length
    syscall

    xor rdi, rdi
    cmp rax, -4095              ; Set rdi to exit syscall (error in case of
    seta dil                    ;     munmap error)

    mov rax, SYS_MUNMAP
    mov rdi, [write_buf]        ; Source
    mov rsi, [stack_end]        ; Length = stack_end - write_buf
    sub rsi,  rdi               ;     (those were allocated together)
    syscall

    cmp rax, -4095              ; Set rdi to exit syscall in case any
    seta cl                     ;     munmap has failed
    and dil, cl                 ;     (and previous rdi, and current posible error)
    ret

_start:
;%%%%% PARSE 'n' PARAMETER %%%%%
    mov rbp, [rsp]              ; if(argc != 2)
    cmp rbp, 2                  ;     exit(1)
    jne .exit_error

    mov rbp, [rsp + 16]         ; argv[1]
    xor rcx, rcx                ; byte index of n ; i = 0
    xor rdi, rdi                ; result_n = 0
.parse_n_loop:
    movzx rbx, byte [rbp + rcx] ; bl = argv[1][i]

    test bl, bl                 ; test end of word
    jz .parse_n_done

    cmp bl, '0'                 ; if (c < '0')
    jb .exit_error              ;     exit(1)

    cmp bl, '9'                 ; if (c > '9')
    ja .exit_error              ;     exit(1)

    sub rbx, '0'

    imul edi, 10                ; result_n *= 10
    jc   .exit_error            ; overflow
    add  edi, ebx               ; add current  digit to result
    jc   .exit_error            ; overflow

    inc rcx                     ; ++i
    jmp .parse_n_loop

.parse_n_done:
    mov [target_n], rdi         ; Save n in a global variable

;%%%% READ INPUT to READ BUFFER %%%%%
    ; Registers:
    ; rbp                       - read buffer start pointer
    xor rbx, rbx                ; Size of allocated memory for read buffer
    mov r13, 1024               ; This amount we want to be allocated
    xor r12, r12                ; Writing lenght

.read_loop:
    ; Make space for data
    cmp rbx, r13                ; Check required memory is allocated
    jae .space_buf_ok
    ; No space for input
    ; MMAP
    mov rax, SYS_MMAP
    xor rdi, rdi
    mov rsi, r13                ; This amount we want to allocate
    mov rdx, PROT_FLAGS
    mov r8, -1                  ; Requiered for anonymous
    xor r9, r9                  ; Offset = 0
    mov r10, MAP_FLAGS
    syscall

    cmp rax, -4095              ; Handle errors
    jae .exit_error

    mov rbp, rax                ; Save read buffer

    test rbx, rbx               ; If nothing to copy, skip
    jz .copy_done

    ; Copy old
    mov rdi, rax                ; Destination
    mov rsi, [read_buf]         ; Source
    mov rcx, r12                ; Reps (Current read length)
    rep movsb                   ; Chunk fast copy

    ; Free old
    mov rax, SYS_MUNMAP
    mov rdi, [read_buf]         ; Source
    mov rsi, rbx                ; Length
    syscall

    cmp rax, -4095              ; Handle errors
    jae .exit_error

.copy_done:
    mov [read_buf], rbp         ; Save read buffer adress
    mov rbx, r13                ; Update amount of allocated memory

.space_buf_ok:
    ; Read from standard input
    mov rax, SYS_READ
    mov rdi, STD_IN_FD
    mov rsi, [read_buf]
    add rsi, r12
    mov rdx, rbx                ; Max number of read characters -
    sub rdx, r12                ;     remaining space = space - busy space
    syscall

    cmp rax, -4095              ; Handle errors
    jae .exit_error             ;     exit(1)

    test rax, rax               ; if EOF
    jz .read_done               ;     break

    add r12, rax                ; Add number of read digits to string length

    cmp rbx, r12                ; If no whole memory is used
    jne .read_loop              ;     do not double memory
    shl r13, 1                  ; Double needed memory
    jmp .read_loop

.read_done:
    lea rcx, [rbp + r12]
    mov [read_end], rcx

    mov [read_cup], rbx

;%%%% PARSE INPUT %%%%
    ; Find newline
    mov rdi, [read_buf]         ; Sign pointer
    mov rsi, [read_end]         ; Bound
.first_line_loop:
    cmp rdi, rsi                ; Test bounds
    ja .exit_error              ; Out of bound - no newline found

    movzx ebx, byte [rdi]       ; Load sign
    inc rdi;                    ; index++

    cmp bl, NEW_LINE            ; Check for newline
    je .first_line_end          ;

    cmp bl, 33                  ; Lowerbound
    jb .exit_error

    cmp bl, 126                 ; Upperbound
    ja .exit_error

    jmp .first_line_loop

.first_line_end:
    dec rdi                     ; Save pointer to newline
    mov [first_line_end], rdi   ; (not next one)
    inc rdi

    ; Read patterns table
    lea rcx, [patterns]         ; rcx will keep patterns table pointer

.read_pattern:
    cmp rdi, rsi                ; Test bound
    jae .input_parse_done       ; End of patterns - done

    movzx ebx, byte [rdi]       ; Load sign
    inc rdi                     ; index++

    cmp bl, 33                  ; Lowerbound
    jb .exit_error

    cmp bl, 126                 ; Upperbound
    ja .exit_error

    sub bl, 33                  ; Normalize sign for array indexing
    movzx rax, bl               ; rax will keep the sign we pattern
    mov rdx, rdi                ; rdx will keep the start position of pattern

; For given sign read swap characters
.read_rule_loop:
    cmp rdi, rsi                ; Test bound
    ja .exit_error              ; No new line at the end of the rule

    movzx ebx, byte [rdi]       ; Load sign
    inc rdi                     ; index++

    cmp bl, NEW_LINE            ; End of the rule
    je .rule_found

    cmp bl, 33                  ; Validate sign lowerbound
    jb .exit_error

    cmp bl, 126                 ; Validate sign upperbound
    ja .exit_error

    jmp .read_rule_loop

.rule_found:
    shl rax, 4                  ; 2^4 = 16 - frame size of pattern_node

    mov r8, [rcx + rax]         ; Test whether there already
    test r8, r8;                ;     is a pattern for that sign
    jnz .exit_error             ; there should be none

    mov [rcx + rax], rdx        ; pattern_node.start
    mov rdx, rdi;
    dec rdx                     ; Calculate end pointer
    mov [rcx + rax + 8] , rdx   ; pattern_node.end

    jmp .read_pattern

.input_parse_done:

;%%%% MAIN DFS LOOP %%%%

    ; Allocate write buffer (4 kB) and stack_space (n * 16 B)
    mov rsi, [target_n]
    inc rsi                     ; For n = 0 allocate at least one
    shl rsi, 4                  ; Calculate stack_space
    ; MMAP
    mov rax, SYS_MMAP
    xor rdi, rdi
    add rsi, 4096               ; stack_space + write buffer
    mov rdx, PROT_FLAGS
    mov r8, -1                  ; Requiered for anonymous
    xor r9, r9                  ; Offset = 0
    mov r10, MAP_FLAGS
    syscall

    cmp rax, -4095              ; Handle errors
    ja .exit_error

    mov [write_buf], rax        ; write buf start
    add rax, 4097
    mov [write_end], rax        ; write buf end

    mov [stack_buf], rax        ; stack buf start
    add rax, rsi
    sub rax, 4096
    mov [stack_end], rax        ; stack buf end

; Main loop
    mov r8,  [target_n]         ; Iterations to go
    mov r9,  [read_buf]         ; Start of processed string
    mov r10, [first_line_end]   ; End of processed string
    mov r12, [write_buf]        ; Write position
    mov r13, [write_end]        ; Write end bound
    dec r13                     ; Decrease bound to have space for last newline
    mov r14, [stack_buf]        ; Stack position

    lea rbx, [patterns]         ; Stable reference to patterns
    mov r15, r8                 ; Stable iterations number to detect end of all epochs

    mov [r14], r9               ; Start position of zero iteration
    mov [r14 + 8], r10          ; End   position of zero iteration

.process_epoch:
    mov r9,  [r14]              ; Set start and end of processed string
    mov r10, [r14 + 8]

    test r8, r8;                ; Check if last iteration
    jz  .write_to_buffer
.write_done:                    ; After write there will be epoch descrease
    cmp r9, r10                 ; Test if every sign from epoch has been processed
    jae .decrease_epoch
; Increase epoch
    mov rcx, [r14]              ; Increase start position of current string
    inc rcx
    mov [r14], rcx

    add r14, 16                  ; Increase stack position
    dec r8                       ; Decrease epochs to go

    movzx rax, byte [r9]         ; Load sign
    sub rax, 33                  ; Normalize to array index
    shl rax, 4                   ; Multiply by frame size of patterns

    mov rcx, [rbx + rax]         ; Load start of next pattern through rcx...
    test rcx, rcx                ; Check if rule exists
    jz .no_rule_found
    mov [r14], rcx               ;     ...to next epoch start

    mov rcx, [rbx + rax + 8]     ; Load end of next pattern through rcx
    mov [r14 + 8], rcx           ;     to next epoch end

    jmp .process_epoch

.no_rule_found:
    mov [r14], r9               ; Save pointer to current char
    inc r9                      ; End pointer one position
    mov [r14 + 8], r9           ;     behind that char
    jmp .process_epoch

.decrease_epoch:
    sub r14, 16                 ; Decrease stack position
    inc r8                      ; Increase iterations to go

    cmp r8, r15                 ; Check end of everything condition
    ja  .final_flush_write      ; Final flush

    jmp .process_epoch

.write_to_buffer:
    cmp r12, r13;               ; Test write_buf bounds
    jae .flush_write

    cmp r9, r10                 ; Test string bounds
    jae .write_done

    movzx rax, byte [r9]        ; Load char to ebx
    mov [r12], al               ; Save char to write buffer
    inc r9                      ; string_index++
    inc r12                     ; write_index++

    jmp .write_to_buffer

.final_flush_write:
    mov [r12], byte NEW_LINE    ; Add new line at the end
    inc r12

.flush_write:   
    mov rax, SYS_WRITE
    mov rdi, STD_OUT_FD         ; File descriptor
    mov rsi, [write_buf]        ; Start of write
    mov rdx, r12                ; Number of bytes to write
    sub rdx, rsi                ;     = position - start
    syscall

    cmp r8, r15                 ; Check end of everything
    ja .exit

    mov r12, rsi                ; reset write position
    jmp .write_to_buffer        ; Continue writing

.exit:
    call memory_cleanup
    ; rdi is already set by memory_cleanup
    mov rax, SYS_EXIT
    syscall

.exit_error:
    call memory_cleanup
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall

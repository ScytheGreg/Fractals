; argument.asm
;
; kompilacja:
; nasm -f elf64 argument.asm
; ld -o argument argument.o
;
; uruchomienie:
; ./argument AlaMaKota

section .data
    prefix db "Argument: "
    prefix_len equ $ - prefix

    noarg db "Brak argumentu",10
    noarg_len equ $ - noarg

    nl db 10

section .bss
    heap_ptr resq 1
    arg_len  resq 1

section .text
global _start

_start:

; argc
    mov rax, [rsp]
    cmp rax, 2
    jl no_argument

; argv[1]
    mov rsi, [rsp+16]

; ===== strlen(argv[1]) =====

    xor rcx, rcx

strlen_loop:
    cmp byte [rsi+rcx], 0
    je alloc
    inc rcx
    jmp strlen_loop

alloc:

    mov [arg_len], rcx

; ===== brk(0) =====

    mov rax, 12
    xor rdi, rdi
    syscall

    mov [heap_ptr], rax

; ===== brk(stary + długość + 1) =====

    mov rdi, rax
    add rdi, rcx
    inc rdi

    mov rax, 12
    syscall

; ===== kopiowanie argv -> heap =====

    mov rdi, [heap_ptr]
    mov rsi, [rsp+16]

copy_loop:

    mov al, [rsi]
    mov [rdi], al

    inc rsi
    inc rdi

    test al, al
    jnz copy_loop

; ===== write("Argument: ") =====

    mov rax, 1
    mov rdi, 1
    mov rsi, prefix
    mov rdx, prefix_len
    syscall

; ===== write(argument) =====

    mov rax, 1
    mov rdi, 1
    mov rsi, [heap_ptr]
    mov rdx, [arg_len]
    syscall

; ===== newline =====

    mov rax, 1
    mov rdi, 1
    mov rsi, nl
    mov rdx, 1
    syscall

; ===== read(stdin, heap, 1) =====
; demonstracja użycia read

    mov rax, 0
    mov rdi, 0
    mov rsi, [heap_ptr]
    mov rdx, 1
    syscall

; ===== exit(0) =====

    mov rax, 60
    xor rdi, rdi
    syscall


no_argument:

    mov rax, 1
    mov rdi, 1
    mov rsi, noarg
    mov rdx, noarg_len
    syscall

    mov rax, 60
    mov rdi, 1
    syscall
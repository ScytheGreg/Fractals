;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Program: discrete_fractal (Wersja Ultra-Kompaktowa: .bss = 0, .rodata = 0)
; Opis: Maksymalnie zoptymalizowany pod kątem rozmiaru sekcji .text.
; Architektura: x86-64 Linux (NASM)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

default rel
section .text
global _start

; Mapowanie zmiennych stanu na ramkę stosu
%define target_n    rbp - 8
%define input_buf   rbp - 16
%define input_cap   rbp - 24
%define input_len   rbp - 32
%define start_ptr   rbp - 40
%define start_len   rbp - 48
%define out_buf     rbp - 56
%define out_len     rbp - 64
%define stack_buf   rbp - 72
%define stack_cap   rbp - 80
%define rules_buf   rbp - 88
%define rules_cap   rbp - 96
%define rules_count rbp - 104
STATE_SIZE equ 104

_start:
    mov     rbp, rsp
    sub     rsp, STATE_SIZE

    ; Zerowanie ramki stosu
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, 13
    rep stosq

    ; Walidacja argc == 2
    cmp     qword [rbp], 2
    jne     error_exit

    ; Parsowanie parametru n
    mov     rsi, [rbp + 16]             ; rsi = argv[1]
    xor     rax, rax
.parse_loop:
    xor     ecx, ecx
    mov     cl, [rsi]
    inc     rsi
    test    cl, cl
    jz      .parse_done
    sub     cl, '0'
    cmp     cl, 9
    ja      error_exit                  ; Łapie też znaki < '0' przez overflow

mov     edx, 429496729
    cmp     rax, rdx
    ja      error_exit                  ; Powyżej progu = błąd
    jb      .safe_multiply              ; Poniżej progu = bezpieczne, omijamy test cyfry

    cmp     cl, 5                       ; Limit dla ostatniej cyfry to 5
    ja      error_exit                  ; Jeśli więcej niż 5, mamy przepełnienie

.safe_multiply:
    imul    rax, 10
    movzx   rcx, cl
    add     rax, rcx
    jmp     .parse_loop

.parse_done:
    mov     rsi, [rbp + 16]
    cmp     byte [rsi], 0
    je      error_exit
    mov     [target_n], rax

    ; Alokacja input_buf (1MB)
    xor     edi, edi
    mov     esi, 1048576
    mov     edx, 3                      ; PROT_READ | PROT_WRITE
    mov     r10d, 0x22                  ; MAP_PRIVATE | MAP_ANONYMOUS
    or      r8, -1                      ; r8 = -1
    xor     r9d, r9d
    push    9
    pop     rax                         ; sys_mmap
    syscall
    cmp     rax, -4095
    jae     error_exit
    mov     [input_buf], rax
    mov     qword [input_cap], 1048576

    ; Alokacja rules_buf (4KB)
    xor     edi, edi
    mov     esi, 4096
    mov     edx, 3
    mov     r10d, 0x22
    or      r8, -1
    xor     r9d, r9d
    push    9
    pop     rax                         ; sys_mmap
    syscall
    cmp     rax, -4095
    jae     error_exit
    mov     [rules_buf], rax
    mov     qword [rules_cap], 4096

    ; Wczytywanie stdin
.read_loop:
    xor     edi, edi                    ; stdin = 0
    mov     rsi, [input_buf]
    add     rsi, [input_len]
    mov     rdx, [input_cap]
    sub     rdx, [input_len]
    xor     eax, eax                    ; sys_read = 0
    syscall
    cmp     rax, 0
    je      .read_done
    jl      error_exit

    add     [input_len], rax
    mov     rcx, [input_len]
    cmp     rcx, [input_cap]
    jne     .read_loop

    ; Dynamiczne powiększenie input_buf przez sys_mremap
    mov     rdi, [input_buf]
    mov     rsi, [input_cap]
    shl     rsi, 1
    mov     rdx, rsi
    mov     rsi, [input_cap]
    push    1
    pop     r10                         ; MREMAP_MAYMOVE
    push    25
    pop     rax                         ; sys_mremap
    syscall
    cmp     rax, -4095
    jae     error_exit
    mov     [input_buf], rax
    shl     qword [input_cap], 1
    jmp     .read_loop

.read_done:
    mov     rsi, [input_buf]
    mov     rdi, rsi
    add     rdi, [input_len]
    mov     rbx, rsi

.find_start_nl:
    cmp     rbx, rdi
    jae     error_exit
    mov     al, [rbx]
    cmp     al, 10                      ; '\n'
    je      .found_start_nl
    cmp     al, 33
    jb      error_exit
    cmp     al, 126
    ja      error_exit
    inc     rbx
    jmp     .find_start_nl

.found_start_nl:
    mov     rdx, rbx
    sub     rdx, rsi
    mov     [start_len], rdx
    mov     [start_ptr], rsi
    inc     rbx

.parse_rules_loop:
    cmp     rbx, rdi
    jae     .parsing_finished

    mov     rcx, rdi
    sub     rcx, rbx
    cmp     rcx, 1
    jne     .not_trailing_nl
    cmp     byte [rbx], 10
    je      .parsing_finished

.not_trailing_nl:
    mov     al, [rbx]
    cmp     al, 33
    jb      error_exit
    cmp     al, 126
    ja      error_exit

    ; Sprawdzenie unikalności za pomocą Pointer Trackingu
    mov     r13, [rules_buf]
    mov     rcx, [rules_count]
    test    rcx, rcx
    jz      .uniq_ok
.check_uniq_loop:
    cmp     [r13], al
    je      error_exit
    add     r13, 24
    dec     rcx
    jnz     .check_uniq_loop

.uniq_ok:
    lea     rcx, [rbx + 1]
.find_rule_nl:
    cmp     rcx, rdi
    jae     error_exit
    mov     r9b, [rcx]
    cmp     r9b, 10
    je      .found_rule_nl
    cmp     r9b, 33
    jb      error_exit
    cmp     r9b, 126
    ja      error_exit
    inc     rcx
    jmp     .find_rule_nl

.found_rule_nl:
    lea     r8, [rbx + 1]
    mov     r10, rcx
    sub     r10, r8

    ; Kontrola pamięci tablicy reguł
    mov     rax, [rules_count]
    inc     rax
    imul    rax, 24
    cmp     rax, [rules_cap]
    jbe     .rules_space_ok

    push    rax
    push    r8
    push    r10
    push    rbx
    push    rdi
    push    rsi
    mov     rdi, [rules_buf]
    mov     rsi, [rules_cap]
    shl     rsi, 1
    mov     rdx, rsi
    mov     rsi, [rules_cap]
    push    1
    pop     r10
    push    25
    pop     rax
    syscall
    pop     rsi
    pop     rdi
    pop     rbx
    cmp     rax, -4095
    jae     error_exit
    mov     [rules_buf], rax
    shl     qword [rules_cap], 1

.rules_space_ok:
    mov     rax, [rules_count]
    imul    rax, 24
    add     rax, [rules_buf]

    movzx   r11, byte [rbx]
    mov     [rax], r11
    mov     [rax + 8], r8
    mov     [rax + 16], r10

    inc     qword [rules_count]
    mov     rbx, rcx
    inc     rbx
    jmp     .parse_rules_loop

.parsing_finished:
    ; Alokacja bufora wyjściowego (64KB)
    xor     edi, edi
    mov     esi, 65536
    mov     edx, 3
    mov     r10d, 0x22
    or      r8, -1
    xor     r9d, r9d
    push    9
    pop     rax
    syscall
    cmp     rax, -4095
    jae     error_exit
    mov     [out_buf], rax

    ; Alokacja bufora stosu DFS (1MB)
    xor     edi, edi
    mov     esi, 1048576
    mov     edx, 3
    mov     r10d, 0x22
    or      r8, -1
    xor     r9d, r9d
    push    9
    pop     rax
    syscall
    cmp     rax, -4095
    jae     error_exit
    mov     [stack_buf], rax
    mov     qword [stack_cap], 1048576

    ; Przygotowanie pierwszej ramki stosu DFS
    mov     r15, rax
    mov     rax, [start_ptr]
    mov     [r15], rax
    add     rax, [start_len]
    mov     [r15 + 8], rax
    mov     rcx, [target_n]
    mov     [r15 + 16], rcx
    mov     r12, 24

.stack_loop:
    test    r12, r12
    jz      .generation_done

    mov     rax, r12
    sub     rax, 24

    mov     r15, [stack_buf]
    mov     rsi, [r15 + rax]
    mov     rdi, [r15 + rax + 8]
    mov     rdx, [r15 + rax + 16]

    cmp     rsi, rdi
    jne     .process_char

    mov     r12, rax
    jmp     .stack_loop

.process_char:
    movzx   rbx, byte [rsi]
    inc     rsi
    mov     r15, [stack_buf]
    mov     [r15 + rax], rsi

    test    rdx, rdx
    jz      .output_char

    ; Wyszukiwanie reguły za pomocą Pointer Trackingu
    mov     r13, [rules_buf]
    mov     rcx, [rules_count]
    test    rcx, rcx
    jz      .output_char
.lookup_rule_loop:
    cmp     [r13], bl
    je      .lookup_found
    add     r13, 24
    dec     rcx
    jnz     .lookup_rule_loop
    jmp     .output_char

.lookup_found:
    mov     r8, [r13 + 8]
    mov     r9, [r13 + 16]

    mov     rax, r12
    add     rax, 24
    cmp     rax, [stack_cap]
    jbe     .stack_space_ok

    push    r8
    push    r9
    push    rdx
    mov     rdi, [stack_buf]
    mov     rsi, [stack_cap]
    shl     rsi, 1
    mov     rdx, rsi
    mov     rsi, [stack_cap]
    push    1
    pop     r10
    push    25
    pop     rax
    syscall
    pop     rdx
    pop     r9
    pop     r8
    cmp     rax, -4095
    jae     error_exit
    mov     [stack_buf], rax
    shl     qword [stack_cap], 1

.stack_space_ok:
    mov     r15, [stack_buf]
    mov     [r15 + r12], r8
    add     r8, r9
    mov     [r15 + r12 + 8], r8
    dec     rdx
    mov     [r15 + r12 + 16], rdx
    add     r12, 24
    jmp     .stack_loop

.output_char:
    mov     rax, [out_len]
    mov     rcx, [out_buf]
    mov     [rcx + rax], bl
    inc     rax
    mov     [out_len], rax

    cmp     rax, 65536
    jne     .stack_loop

    xor     r14, r14
.flush_loop:
    cmp     r14, [out_len]
    jae     .flush_done
    push    1
    pop     rdi                         ; stdout = 1
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14
    push    1
    pop     rax                         ; sys_write = 1
    syscall
    cmp     rax, 0
    jle     error_exit
    add     r14, rax
    jmp     .flush_loop

.flush_done:
    mov     qword [out_len], 0
    jmp     .stack_loop

.generation_done:
    mov     rdx, [out_len]
    test    rdx, rdx
    jz      .write_newline

    xor     r14, r14
.final_flush_loop:
    cmp     r14, [out_len]
    jae     .write_newline
    push    1
    pop     rdi
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14
    push    1
    pop     rax
    syscall
    cmp     rax, 0
    jle     error_exit
    add     r14, rax
    jmp     .final_flush_loop

.write_newline:
    push    1
    pop     rdi
    push    10                          ; '\n' na stos
    mov     rsi, rsp
    push    1
    pop     rdx
    push    1
    pop     rax
    syscall
    pop     rcx
    cmp     rax, 1
    jne     error_exit
    jmp     normal_exit

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Zunifikowana sekwencja wyjścia programu (Normalna i błędy)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
normal_exit:
    xor     edi, edi                    ; Kod sukcesu = 0
    jmp     do_exit
error_exit:
    push    1
    pop     rdi                         ; Kod błędu = 1
do_exit:
    push    rdi                         ; Zachowanie kodu wyjścia

    ; Czyszczenie mmapów (sys_munmap = 11)
    mov     rdi, [input_buf]
    test    rdi, rdi
    jz      .f2
    mov     rsi, [input_cap]
    push    11
    pop     rax
    syscall
.f2:
    mov     rdi, [rules_buf]
    test    rdi, rdi
    jz      .f3
    mov     rsi, [rules_cap]
    push    11
    pop     rax
    syscall
.f3:
    mov     rdi, [out_buf]
    test    rdi, rdi
    jz      .f4
    mov     rsi, 65536
    push    11
    pop     rax
    syscall
.f4:
    mov     rdi, [stack_buf]
    test    rdi, rdi
    jz      .f_done
    mov     rsi, [stack_cap]
    push    11
    pop     rax
    syscall
.f_done:
    pop     rdi                         ; Przywrócenie kodu wyjścia
    push    60
    pop     rax                         ; sys_exit = 60
    syscall
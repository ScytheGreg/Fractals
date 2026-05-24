;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Program: discrete_fractal (Wersja zoptymalizowana: BSS = 0 bajtów)
; Opis: Generuje L-systemy za pomocą stosu DFS. Tablica reguł jest dynamiczna,
;        a wszystkie zmienne stanu zostały przeniesione na stos (0 bajtów w .bss).
; Architektura: x86-64 Linux (NASM)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

default rel

section .text
global _start

; Mapowanie zmiennych stanu na ramkę stosu (zamiast sekcji .bss)
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
    ; Sprawdzenie liczby argumentów (argc musi wynosić dokładnie 2)
    mov     rbp, rsp                    ; rbp = punkt odniesienia do argumentów (i nowej ramki)
    cmp     qword [rbp], 2              ; Sprawdzenie argc
    jne     error_exit_no_free          ; Błąd jeśli argc != 2

    ; Alokacja 104 bajtów na zmienne stanu bezpośrednio na stosie
    sub     rsp, STATE_SIZE

    ; Bezpieczne wyzerowanie ramki stosu (13 kwadratów * 8 bajtów = 104 bajty)
    mov     rdi, rsp
    xor     rax, rax
    mov     rcx, 13
    rep stosq

    ; Parsowanie parametru n (argv[1] znajduje się na [rbp + 16])
    mov     rsi, [rbp + 16]             ; rsi = argv[1]
    xor     rax, rax                    ; rax będzie przechowywać wartość n
    xor     rcx, rcx                    ; czyszczenie rejestru pomocniczego

.parse_loop:
    mov     cl, [rsi]                   ; Pobranie kolejnego znaku napisu
    test    cl, cl                      ; Sprawdzenie końca napisu (\0)
    jz      .parse_done
    cmp     cl, '0'
    jb      error_cleanup_exit          ; Znak poniżej '0' -> błąd
    cmp     cl, '9'
    ja      error_cleanup_exit          ; Znak powyżej '9' -> błąd
    sub     cl, '0'                     ; Konwersja ASCII na cyfrę

    ; Kontrola przepełnienia 32-bitowego przed mnożeniem
    mov     rdx, [max_n_limit]
    cmp     rax, rdx
    ja      error_cleanup_exit
    jne     .multiply
    cmp     rcx, [max_n_digit]
    ja      error_cleanup_exit

.multiply:
    mov     rdx, rax
    shl     rdx, 3                      ; rdx = rax * 8
    shl     rax, 1                      ; rax = rax * 2
    add     rax, rdx                    ; rax = rax * 10
    add     rax, rcx                    ; Dodanie nowej cyfry

    inc     rsi                         ; Przejście do kolejnego znaku
    jmp     .parse_loop

.parse_done:
    mov     rsi, [rbp + 16]
    cmp     byte [rsi], 0
    je      error_cleanup_exit

    mov     [target_n], rax             ; Zapisanie docelowej liczby iteracji

    ; Alokacja początkowego bufora na całe wejście (1MB) za pomocą sys_mmap
    mov     rdi, 0
    mov     rsi, [initial_buf_size]     ; 1MB
    mov     rdx, [prot_rw]
    mov     r10, [map_priv_anon]
    mov     r8, -1
    mov     r9, 0
    mov     rax, [sys_mmap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [input_buf], rax
    mov     rcx, [initial_buf_size]
    mov     [input_cap], rcx

    ; Alokacja początkowego dynamicznego bufora na reguły (4KB)
    mov     rdi, 0
    mov     rsi, [initial_rules_cap]
    mov     rdx, [prot_rw]
    mov     r10, [map_priv_anon]
    mov     r8, -1
    mov     r9, 0
    mov     rax, [sys_mmap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [rules_buf], rax
    mov     rcx, [initial_rules_cap]
    mov     [rules_cap], rcx

    ; Pętla wczytywania całego standardowego wejścia
.read_loop:
    mov     rdi, [stdin_fd]
    mov     rsi, [input_buf]
    add     rsi, [input_len]
    mov     rdx, [input_cap]
    sub     rdx, [input_len]
    mov     rax, [sys_read_num]
    syscall

    cmp     rax, 0
    je      .read_done
    jl      error_cleanup_exit

    add     [input_len], rax

    mov     rcx, [input_len]
    cmp     rcx, [input_cap]
    jne     .read_loop

    mov     rdi, [input_buf]
    mov     rsi, [input_cap]
    shl     rsi, 1
    mov     rdx, rsi
    mov     rsi, [input_cap]
    mov     r10, [mremap_maymove]
    mov     rax, [sys_mremap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit

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
    jae     error_cleanup_exit
    mov     al, [rbx]
    cmp     al, [char_lf]
    je      .found_start_nl
    cmp     al, [min_ascii]
    jb      error_cleanup_exit
    cmp     al, [max_ascii]
    ja      error_cleanup_exit
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
    mov     al, [char_lf]
    cmp     [rbx], al
    je      .parsing_finished

.not_trailing_nl:
    xor     eax, eax
    mov     al, [rbx]
    cmp     al, [min_ascii]
    jb      error_cleanup_exit
    cmp     al, [max_ascii]
    ja      error_cleanup_exit

    ; Sprawdzenie unikalności reguły
    mov     r13, [rules_buf]
    xor     r14, r14
.check_uniq_loop:
    cmp     r14, [rules_count]
    jae     .uniq_ok

    mov     r15, r14
    shl     r15, 4
    mov     r11, r14
    shl     r11, 3
    add     r15, r11                    ; r15 = r14 * 24

    mov     rcx, [r13 + r15]
    cmp     cl, al
    je      error_cleanup_exit
    inc     r14
    jmp     .check_uniq_loop

.uniq_ok:
    lea     rcx, [rbx + 1]
.find_rule_nl:
    cmp     rcx, rdi
    jae     error_cleanup_exit
    mov     r9b, [rcx]
    cmp     r9b, [char_lf]
    je      .found_rule_nl
    cmp     r9b, [min_ascii]
    jb      error_cleanup_exit
    cmp     r9b, [max_ascii]
    ja      error_cleanup_exit
    inc     rcx
    jmp     .find_rule_nl

.found_rule_nl:
    lea     r8, [rbx + 1]
    mov     r10, rcx
    sub     r10, r8

    ; Kontrola i ewentualne rozszerzenie pamięci tablicy reguł
    mov     r14, [rules_count]
    lea     rax, [r14 + 1]
    mov     r15, rax
    shl     r15, 4
    shl     rax, 3
    add     r15, rax                    ; r15 = (count + 1) * 24

    cmp     r15, [rules_cap]
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
    mov     r10, [mremap_maymove]
    mov     rax, [sys_mremap_num]
    syscall

    pop     rsi
    pop     rdi
    pop     rbx
    pop     r10
    pop     r8
    pop     rax
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [rules_buf], rax
    shl     qword [rules_cap], 1

.rules_space_ok:
    mov     r13, [rules_buf]
    mov     r14, [rules_count]
    mov     r15, r14
    shl     r15, 4
    shl     r14, 3
    add     r15, r14                    ; r15 = rules_count * 24

    xor     eax, eax
    mov     al, [rbx]

    mov     [r13 + r15], rax            ; Klucz
    mov     [r13 + r15 + 8], r8         ; Wskaźnik zamiany
    mov     [r13 + r15 + 16], r10       ; Długość zamiany

    inc     qword [rules_count]

    mov     rbx, rcx
    inc     rbx
    jmp     .parse_rules_loop

.parsing_finished:
    ; Alokacja bufora wyjściowego (64 KB)
    mov     rdi, 0
    mov     rsi, [out_buf_size]
    mov     rdx, [prot_rw]
    mov     r10, [map_priv_anon]
    mov     r8, -1
    mov     r9, 0
    mov     rax, [sys_mmap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [out_buf], rax

    ; Alokacja początkowego bufora na jawny stos DFS (1MB)
    mov     rdi, 0
    mov     rsi, [initial_buf_size]
    mov     rdx, [prot_rw]
    mov     r10, [map_priv_anon]
    mov     r8, -1
    mov     r9, 0
    mov     rax, [sys_mmap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [stack_buf], rax
    mov     rcx, [initial_buf_size]
    mov     [stack_cap], rcx

    ; Przygotowanie pierwszej ramki stosu DFS
    mov     r15, [stack_buf]
    mov     rax, [start_ptr]
    mov     [r15], rax
    add     rax, [start_len]
    mov     [r15 + 8], rax
    mov     rcx, [target_n]
    mov     [r15 + 16], rcx
    mov     r12, [frame_size]           ; r12 = stack_top (offset = 24)

.stack_loop:
    test    r12, r12
    jz      .generation_done

    mov     rax, r12
    sub     rax, [frame_size]

    mov     r15, [stack_buf]
    mov     rsi, [r15 + rax]            ; curr_ptr
    mov     rdi, [r15 + rax + 8]        ; end_ptr
    mov     rdx, [r15 + rax + 16]       ; depth

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

    ; Przeszukiwanie tablicy reguł
    mov     r13, [rules_buf]
    xor     r14, r14
.lookup_rule_loop:
    cmp     r14, [rules_count]
    jae     .output_char

    mov     r15, r14
    shl     r15, 4
    mov     r11, r14
    shl     r11, 3
    add     r15, r11

    mov     rcx, [r13 + r15]
    cmp     cl, bl
    je      .lookup_found

    inc     r14
    jmp     .lookup_rule_loop

.lookup_found:
    mov     r8, [r13 + r15 + 8]
    mov     r9, [r13 + r15 + 16]

    ; Push nowej ramki na stos DFS
    mov     rax, r12
    add     rax, [frame_size]
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
    mov     r10, [mremap_maymove]
    mov     rax, [sys_mremap_num]
    syscall
    pop     rdx
    pop     r9
    pop     r8
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [stack_buf], rax
    shl     qword [stack_cap], 1

.stack_space_ok:
    mov     r15, [stack_buf]
    mov     [r15 + r12], r8
    add     r8, r9
    mov     [r15 + r12 + 8], r8
    dec     rdx
    mov     [r15 + r12 + 16], rdx
    add     r12, [frame_size]
    jmp     .stack_loop

.output_char:
    mov     rax, [out_len]
    mov     rcx, [out_buf]
    mov     [rcx + rax], bl
    inc     rax
    mov     [out_len], rax

    cmp     rax, [out_buf_size]
    jne     .stack_loop

    xor     r14, r14
.flush_loop:
    cmp     r14, [out_len]
    jae     .flush_done
    mov     rdi, [stdout_fd]
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14
    mov     rax, [sys_write_num]
    syscall
    cmp     rax, 0
    jle     error_cleanup_exit
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
    mov     rdi, [stdout_fd]
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14
    mov     rax, [sys_write_num]
    syscall
    cmp     rax, 0
    jle     error_cleanup_exit
    add     r14, rax
    jmp     .final_flush_loop

.write_newline:
    mov     rax, [sys_write_num]
    mov     rdi, [stdout_fd]
    push    qword [char_lf_qword]
    mov     rsi, rsp
    mov     rdx, 1
    syscall
    pop     rcx
    cmp     rax, 1
    jne     error_cleanup_exit

    call    free_all_buffers
    mov     rax, [sys_exit_num]
    mov     rdi, 0
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Procedury oczyszczania zasobów
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

free_all_buffers:
    mov     rdi, [input_buf]
    test    rdi, rdi
    jz      .free_rules
    mov     rsi, [input_cap]
    mov     rax, [sys_munmap_num]
    syscall
.free_rules:
    mov     rdi, [rules_buf]
    test    rdi, rdi
    jz      .free_out
    mov     rsi, [rules_cap]
    mov     rax, [sys_munmap_num]
    syscall
.free_out:
    mov     rdi, [out_buf]
    test    rdi, rdi
    jz      .free_stack
    mov     rsi, [out_buf_size]
    mov     rax, [sys_munmap_num]
    syscall
.free_stack:
    mov     rdi, [stack_buf]
    test    rdi, rdi
    jz      .done
    mov     rsi, [stack_cap]
    mov     rax, [sys_munmap_num]
    syscall
.done:
    ret

error_exit_no_free:
    mov     rax, [sys_exit_num]
    mov     rdi, 1
    syscall

error_cleanup_exit:
    call    free_all_buffers
    mov     rax, [sys_exit_num]
    mov     rdi, 1
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sekcja danych (.rodata) - stałe programu pozostają niezmienione
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .rodata
align 8
sys_read_num:       dq 0
sys_write_num:      dq 1
sys_mmap_num:       dq 9
sys_munmap_num:     dq 11
sys_mremap_num:     dq 25
sys_exit_num:       dq 60

stdin_fd:           dq 0
stdout_fd:          dq 1

initial_buf_size:   dq 1048576
initial_rules_cap:  dq 4096
out_buf_size:       dq 65536
frame_size:         dq 24

prot_rw:            dq 3
map_priv_anon:      dq 0x22
mremap_maymove:     dq 1
max_errno:          dq -4095

max_n_limit:        dq 429496729
max_n_digit:        dq 5

min_ascii:          db 33
max_ascii:          db 126
char_lf:            db 10
char_lf_qword:      dq 10

; SEKCJA .BSS ZOSTAŁA CAŁKOWICIE USUNIĘTA
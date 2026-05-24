;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Program: discrete_fractal
; Opis: Generuje dyskretne fraktale (L-systemy) przy użyciu jawnego stosu (DFS).
;        Rozwiązanie eliminuje wykładniczy wzrost pamięci poprzez strumieniowanie
;        wyniku bezpośrednio na stdout za pomocą bufora o stałym rozmiarze.
; Architektura: x86-64 Linux (NASM)
; Rejestry globalne w pętli głównej (.stack_loop):
;    r12 - aktualny wskaźnik wierzchołka stosu (stack_top jako offset bajtowy)
;    rbx - aktualnie przetwarzany znak (rozszerzony do 64-bitów)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

default rel

section .text
global _start

_start:
    ; Sprawdzenie liczby argumentów (argc musi wynosić dokładnie 2)
    mov     rbp, [rsp]                  ; rbp = argc
    cmp     rbp, [required_argc]
    jne     error_exit_no_free          ; Błąd jeśli argc != 2

    ; Parsowanie parametru n (argv[1])
    mov     rsi, [rsp + 16]             ; rsi = argv[1]
    xor     rax, rax                    ; rax będzie przechowywać wartość n
    xor     rcx, rcx                    ; czyszczenie rejestru pomocniczego

.parse_loop:
    mov     cl, [rsi]                   ; Pobranie kolejnego znaku napisu
    test    cl, cl                      ; Sprawdzenie końca napisu (\0)
    jz      .parse_done
    cmp     cl, '0'
    jb      error_exit_no_free          ; Znak poniżej '0' -> błąd
    cmp     cl, '9'
    ja      error_exit_no_free          ; Znak powyżej '9' -> błąd
    sub     cl, '0'                     ; Konwersja ASCII na cyfrę

    ; Kontrola przepełnienia 32-bitowego przed mnożeniem (max n = 4294967295)
    mov     rdx, [max_n_limit]
    cmp     rax, rdx
    ja      error_exit_no_free          ; rax > 429496729 -> przepełnienie po mnożeniu
    jne     .multiply
    cmp     rcx, [max_n_digit]
    ja      error_exit_no_free          ; rax == 429496729 i nowa cyfra > 5 -> przepełnienie

.multiply:
    ; Szybkie mnożenie rax * 10 (rax * 8 + rax * 2)
    mov     rdx, rax
    shl     rdx, 3                      ; rdx = rax * 8
    shl     rax, 1                      ; rax = rax * 2
    add     rax, rdx                    ; rax = rax * 10
    add     rax, rcx                    ; Dodanie nowej cyfry

    inc     rsi                         ; Przejście do kolejnego znaku
    jmp     .parse_loop

.parse_done:
    ; Sprawdzenie czy podany argument nie był pustym ciągiem
    mov     rsi, [rsp + 16]
    cmp     byte [rsi], 0
    je      error_exit_no_free

    mov     [target_n], rax             ; Zapisanie docelowej liczby iteracji

    ; Alokacja początkowego bufora na całe wejście (1MB) za pomocą sys_mmap
    mov     rdi, 0                      ; System wybiera adres
    mov     rsi, [initial_buf_size]     ; Rozmiar początkowy = 1MB
    mov     rdx, [prot_rw]              ; PROT_READ | PROT_WRITE
    mov     r10, [map_priv_anon]        ; MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1                      ; Brak pliku
    mov     r9, 0                       ; Offset = 0
    mov     rax, [sys_mmap_num]         ; sys_mmap
    syscall
    cmp     rax, [max_errno]
    jae     error_exit_no_free          ; Błąd alokacji
    mov     [input_buf], rax
    mov     rcx, [initial_buf_size]
    mov     [input_cap], rcx
    mov     qword [input_len], 0

    ; Pętla wczytywania całego standardowego wejścia
.read_loop:
    mov     rdi, [stdin_fd]             ; Stdin
    mov     rsi, [input_buf]
    add     rsi, [input_len]            ; Adres zapisu = początek + aktualny rozmiar
    mov     rdx, [input_cap]
    sub     rdx, [input_len]            ; rdx = pozostała pojemność bufora
    mov     rax, [sys_read_num]         ; sys_read
    syscall

    cmp     rax, 0
    je      .read_done                  ; EOF (koniec danych)
    jl      error_cleanup_exit          ; Błąd odczytu

    add     [input_len], rax            ; Zaktualizowanie rozmiaru danych

    ; Sprawdzenie czy bufor się zapełnił - jeśli tak, podwajamy pojemność przez mremap
    mov     rcx, [input_len]
    cmp     rcx, [input_cap]
    jne     .read_loop

    mov     rdi, [input_buf]            ; Stary adres
    mov     rsi, [input_cap]            ; Stary rozmiar
    shl     rsi, 1                      ; Nowy rozmiar = stary * 2
    mov     rdx, rsi                    ; Przekazanie do rdx jako new_size
    mov     rsi, [input_cap]            ; Ponowne załadowanie old_size do rsi
    mov     r10, [mremap_maymove]       ; MREMAP_MAYMOVE
    mov     rax, [sys_mremap_num]       ; sys_mremap
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit          ; Błąd powiększania pamięci

    mov     [input_buf], rax
    shl     qword [input_cap], 1        ; Podwojenie zapisanej pojemności
    jmp     .read_loop

.read_done:
    ; Parsowanie danych wejściowych z bufora
    mov     rsi, [input_buf]            ; rsi = początek danych
    mov     rdi, rsi
    add     rdi, [input_len]            ; rdi = koniec danych
    mov     rbx, rsi                    ; rbx = wskaźnik przetwarzania linii

    ; Wyznaczenie i walidacja pierwszej linii (napis początkowy)
.find_start_nl:
    cmp     rbx, rdi
    jae     error_cleanup_exit          ; Brak znaku nowej linii -> błąd
    mov     al, [rbx]
    cmp     al, [char_lf]               ; Czy to '\n'?
    je      .found_start_nl
    cmp     al, [min_ascii]
    jb      error_cleanup_exit          ; Niepoprawny symbol (< 33)
    cmp     al, [max_ascii]
    ja      error_cleanup_exit          ; Niepoprawny symbol (> 126)
    inc     rbx
    jmp     .find_start_nl

.found_start_nl:
    mov     rdx, rbx
    sub     rdx, rsi                    ; rdx = długość napisu początkowego
    mov     [start_len], rdx
    mov     [start_ptr], rsi
    inc     rbx                         ; Przejście za znak '\n'

    ; Parsowanie kolejnych linii zawierających reguły zamiany
.parse_rules_loop:
    cmp     rbx, rdi
    jae     .parsing_finished           ; Koniec danych w buforze

    ; Ignorowanie ewentualnego pojedynczego znaku nowej linii na samym końcu pliku
    mov     rcx, rdi
    sub     rcx, rbx
    cmp     rcx, 1
    jne     .not_trailing_nl
    mov     al, [char_lf]
    cmp     [rbx], al
    je      .parsing_finished

.not_trailing_nl:
    ; Pobranie symbolu, który ma być zastępowany
    xor     eax, eax
    mov     al, [rbx]
    cmp     al, [min_ascii]
    jb      error_cleanup_exit
    cmp     al, [max_ascii]
    ja      error_cleanup_exit

    ; Sprawdzenie unikalności reguły (maksymalnie jedna reguła na symbol)
    mov     r13, rax
    shl     r13, 4                      ; Indeksowanie tablicy (16 bajtów na wpis)
    lea     r14, [rules_table]
    add     r14, r13
    cmp     qword [r14], 0              ; Sprawdzenie czy wskaźnik jest już ustawiony
    jne     error_cleanup_exit          ; Zmienione bne -> jne

    ; Szukanie końca linii reguły
    lea     rcx, [rbx + 1]              ; Start ciągu zastępującego
.find_rule_nl:
    cmp     rcx, rdi
    jae     error_cleanup_exit          ; Brak domykającego '\n' -> błąd
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
    lea     r8, [rbx + 1]               ; r8 = wskaźnik na ciąg zastępujący
    mov     r10, rcx
    sub     r10, r8                     ; r10 = długość ciągu zastępującego

    ; Zapisanie reguły w tabeli
    mov     [r14], r8                   ; Zapis adresu mapowania
    mov     [r14 + 8], r10              ; Zapis długości mapowania

    mov     rbx, rcx
    inc     rbx                         ; Przejście do następnej linii
    jmp     .parse_rules_loop

.parsing_finished:
    ; Alokacja stałego bufora wyjściowego (64 KB) - optymalny rozmiar dla sys_write
    mov     rdi, 0
    mov     rsi, [out_buf_size]         ; 65536
    mov     rdx, [prot_rw]
    mov     r10, [map_priv_anon]
    mov     r8, -1
    mov     r9, 0
    mov     rax, [sys_mmap_num]
    syscall
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [out_buf], rax
    mov     qword [out_len], 0

    ; Alokacja początkowego bufora na jawny stos DFS (1MB)
    mov     rdi, 0
    mov     rsi, [initial_buf_size]     ; 1MB pojemności początkowej
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

    ; Pobieramy adres zwracanego bufora mmap do r15 i na niego zapisujemy ramkę
    mov     r15, [stack_buf]
    mov     rax, [start_ptr]
    mov     [r15], rax                  ; frame.curr_ptr = start_ptr
    add     rax, [start_len]
    mov     [r15 + 8], rax              ; frame.end_ptr = start_ptr + start_len
    mov     rcx, [target_n]
    mov     [r15 + 16], rcx             ; frame.depth = n
    mov     r12, [frame_size]           ; r12 = stack_top (offset kolejnej wolnej ramki = 24)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Główna pętla sterująca jawnym stosem DFS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.stack_loop:
    test    r12, r12
    jz      .generation_done            ; Jeśli stos jest pusty, kończymy generowanie

    ; Podejrzenie ramki na wierzchołku stosu (offset: r12 - 24)
    mov     rax, r12
    sub     rax, [frame_size]

    ; Ładujemy rzeczywisty wskaźnik na bufor stosu do rejestru bazowego r15
    mov     r15, [stack_buf]
    mov     rsi, [r15 + rax]            ; rsi = curr_ptr
    mov     rdi, [r15 + rax + 8]        ; rdi = end_ptr
    mov     rdx, [r15 + rax + 16]       ; rdx = depth

    ; Jeśli curr_ptr == end_ptr, oznacza to, że przetworzyliśmy całą sekwencję w ramce
    cmp     rsi, rdi
    jne     .process_char

    ; Zdjęcie ramki ze stosu (pop) i powrót na początek pętli
    mov     r12, rax
    jmp     .stack_loop

.process_char:
    ; Pobranie bieżącego znaku i inkrementacja wskaźnika w ramce stosu
    movzx   rbx, byte [rsi]             ; rbx = aktualny znak c
    inc     rsi

    ; Bezpieczny zapis zaktualizowanego adresu curr_ptr przez rejestr bazowy r15
    mov     r15, [stack_buf]
    mov     [r15 + rax], rsi

    ; Sprawdzenie, czy depth == 0. Jeśli tak, nie schodzimy głębiej.
    test    rdx, rdx
    jz      .output_char

    ; Sprawdzenie czy existe reguła zamiany dla znaku rbx
    mov     rcx, rbx
    shl     rcx, 4                      ; rbx * 16 (indeksowanie tabeli)

    ; Pobieramy adres bazowy tabeli relatywnie (RIP-relative),
    ; a przesunięcie indeksu dodajemy jawnie instrukcją add.
    lea     r10, [rules_table]
    add     r10, rcx
    mov     r8, [r10]                   ; r8 = wskaźnik na ciąg zastępujący
    mov     r9, [r10 + 8]               ; r9 = długość ciągu zastępującego

    test    r8, r8
    jz      .output_char                ; Brak reguły -> traktuj znak jako stałą (wypisz)

    ; Reguła istnieje i depth > 0 -> Wypchnięcie nowej ramki na stos (push)
    ; Sprawdzenie, czy na stosie jest wolne miejsce (wymagane kolejne 24 bajty)
    mov     rax, r12
    add     rax, [frame_size]           ; rax = potencjalny nowy wierzchołek stosu
    cmp     rax, [stack_cap]
    jbe     .stack_space_ok

    ; Dynamiczne powiększenie stosu w razie skomplikowanych i głębokich fraktali
    push    r8
    push    r9
    push    rdx
    mov     rdi, [stack_buf]
    mov     rsi, [stack_cap]            ; old_size
    shl     rsi, 1                      ; new_size = old_size * 2
    mov     rdx, rsi                    ; rdx = new_size
    mov     rsi, [stack_cap]            ; rsi = old_size
    mov     r10, [mremap_maymove]
    mov     rax, [sys_mremap_num]       ; sys_mremap
    syscall                             ; clobbers: rax, rcx, r11
    pop     rdx
    pop     r9
    pop     r8
    cmp     rax, [max_errno]
    jae     error_cleanup_exit
    mov     [stack_buf], rax
    shl     qword [stack_cap], 1        ; Podwojenie zanotowanej pojemności stosu

.stack_space_ok:
    ; Zapisanie nowej ramki na wierzchu stosu poprzez załadowany uprzednio wskaźnik r15
    mov     r15, [stack_buf]
    mov     [r15 + r12], r8             ; nowa ramka.curr_ptr = rule_ptr
    add     r8, r9
    mov     [r15 + r12 + 8], r8         ; nowa ramka.end_ptr = rule_ptr + rule_len
    dec     rdx                         ; nowa ramka.depth = depth - 1
    mov     [r15 + r12 + 16], rdx
    add     r12, [frame_size]           ; Oficjalne, bezpieczne przesunięcie wskaźnika
    jmp     .stack_loop

.output_char:
    ; Dopisanie znaku z rbx do stałego bufora wyjściowego
    mov     rax, [out_len]
    mov     rcx, [out_buf]
    mov     [rcx + rax], bl
    inc     rax
    mov     [out_len], rax

    ; Jeśli bufor osiągnął maksymalny rozmiar, opróżniamy go na stdout
    cmp     rax, [out_buf_size]
    jne     .stack_loop

    ; Opróżnianie bufora (flush) na standardowe wyjście
    xor     r14, r14                    ; r14 = liczba bajtów już wypisanych
.flush_loop:
    cmp     r14, [out_len]
    jae     .flush_done
    mov     rdi, [stdout_fd]            ; Stdout
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14                    ; Pozostałe bajty do wysłania
    mov     rax, [sys_write_num]        ; sys_write
    syscall
    cmp     rax, 0
    jle     error_cleanup_exit          ; Błąd zapisu
    add     r14, rax
    jmp     .flush_loop

.flush_done:
    mov     qword [out_len], 0          ; Reset długości danych w buforze wyjściowym
    jmp     .stack_loop

.generation_done:
    ; Wypisanie pozostałości z bufora wyjściowego (jeśli coś zostało)
    mov     rdx, [out_len]
    test    rdx, rdx
    jz      .write_newline

    xor     r14, r14
.final_flush_loop:
    cmp     r14, [out_len]
    jae     .write_newline
    mov     rdi, [stdout_fd]            ; Stdout
    mov     rsi, [out_buf]
    add     rsi, r14
    mov     rdx, [out_len]
    sub     rdx, r14
    mov     rax, [sys_write_num]        ; sys_write
    syscall
    cmp     rax, 0
    jle     error_cleanup_exit
    add     r14, rax
    jmp     .final_flush_loop

.write_newline:
    ; Wypisanie obowiązkowego znaku nowej linii na końcu działania programu
    mov     rax, [sys_write_num]        ; sys_write
    mov     rdi, [stdout_fd]            ; Stdout
    push    qword [char_lf_qword]       ; Kod znaku '\n' na stos jako qword
    mov     rsi, rsp                    ; Wskazanie na szczyt stosu jako bufor danych
    mov     rdx, 1
    syscall
    pop     rcx                         ; Czyszczenie stosu procesora
    cmp     rax, 1
    jne     error_cleanup_exit

    ; Poprawne zakończenie działania programu z kodem 0
    call    free_all_buffers            ; Jawne zwolnienie wszystkich zasobów systemowych
    mov     rax, [sys_exit_num]         ; sys_exit
    mov     rdi, 0                      ; Kod wyjścia = 0
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Procedury obsługi błędów i czyszczenia
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

free_all_buffers:
    ; Zwolnienie bufora wejściowego
    mov     rdi, [input_buf]
    test    rdi, rdi
    jz      .free_out
    mov     rsi, [input_cap]
    mov     rax, [sys_munmap_num]       ; sys_munmap
    syscall
.free_out:
    ; Zwolnienie stałego bufora wyjściowego
    mov     rdi, [out_buf]
    test    rdi, rdi
    jz      .free_stack
    mov     rsi, [out_buf_size]
    mov     rax, [sys_munmap_num]       ; sys_munmap
    syscall
.free_stack:
    ; Zwolnienie bufora stosu DFS
    mov     rdi, [stack_buf]
    test    rdi, rdi
    jz      .done
    mov     rsi, [stack_cap]
    mov     rax, [sys_munmap_num]       ; sys_munmap
    syscall
.done:
    ret

error_exit_no_free:
    ; Wywoływane przed jakąkolwiek alokacją pamięci
    mov     rax, [sys_exit_num]         ; sys_exit
    mov     rdi, 1                      ; Kod błędu = 1
    syscall

error_cleanup_exit:
    ; Gwarantuje jawne zwolnienie pamięci w przypadku jakiegokolwiek błędu w trakcie działania
    call    free_all_buffers
    mov     rax, [sys_exit_num]         ; sys_exit
    mov     rdi, 1                      ; Kod błędu = 1
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sekcja danych tylko do odczytu (.rodata)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .rodata
align 8
; Numery wywołań systemowych (Syscalls)
sys_read_num:       dq 0
sys_write_num:      dq 1
sys_mmap_num:       dq 9
sys_munmap_num:     dq 11
sys_mremap_num:     dq 25
sys_exit_num:       dq 60

; Deskryptory standardowych strumieni
stdin_fd:           dq 0
stdout_fd:          dq 1

; Konfiguracja rozmiarów buforów
initial_buf_size:   dq 1048576          ; Początkowy rozmiar bufora (1MB)
out_buf_size:       dq 65536            ; Rozmiar stałego bufora wyjściowego (64KB)
frame_size:         dq 24               ; Rozmiar pojedynczej ramki stosu DFS (3 * 8 bajtów)

; Flagi i stałe jądra Linux
prot_rw:            dq 3                ; PROT_READ | PROT_WRITE
map_priv_anon:      dq 0x22             ; MAP_PRIVATE | MAP_ANONYMOUS
mremap_maymove:     dq 1                ; MREMAP_MAYMOVE
max_errno:          dq -4095            ; Granica błędu zwracanego przez kernel

; Stałe walidacji parsowania liczby n oraz argumentów
required_argc:      dq 2
max_n_limit:        dq 429496729        ; Próg zabezpieczający przed przepełnieniem
max_n_digit:        dq 5

; Stałe znakowe i granice ASCII
min_ascii:          db 33               ; Pierwszy drukowalny znak ('!')
max_ascii:          db 126              ; Ostatni drukowalny znak ('~')
char_lf:            db 10               ; Kod znaku nowej linii '\n' (bajt)
char_lf_qword:      dq 10               ; Kod znaku nowej linii '\n' (qword dla push)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sekcja danych niezainicjalizowanych (.bss)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .bss
align 8
target_n:    resq 1                      ; Docelowa liczba iteracji n obliczona ze strumienia wejściowego

input_buf:   resq 1                      ; Adres bufora na surowe wejście ze stdin
input_cap:   resq 1                      ; Pojemność bufora wejściowego
input_len:   resq 1                      ; Rozmiar wczytanych danych ze stdin

start_ptr:   resq 1                      ; Wskaźnik na początek ciągu startowego wewnątrz bufora wejściowego
start_len:   resq 1                      ; Długość ciągu startowego

out_buf:     resq 1                      ; Adres stałego bufora wyjściowego (64KB)
out_len:     resq 1                      ; Liczba nieopróżnionych bajtów w buforze wyjściowym

stack_buf:   resq 1                      ; Adres dynamicznego bufora dla jawnego stosu DFS
stack_cap:   resq 1                      ; Aktualna pojemność bufora stosu w bajtach

; Tablica asocjacyjna reguł zamiany: kod ASCII (0-255) -> struktura {wskaźnik, długość}.
; Rozmiar: 256 wpisów * 16 bajtów = 4096 bajtów.
rules_table: resq 512
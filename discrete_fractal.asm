;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Program: discrete_fractal
; Opis: Generuje dyskretne fraktale (L-systemy) na podstawie reguł zamiany ASCII.
; Architektura: x86-64 Linux (NASM)
; Rejestry globalne (w pętli głównej):
;   r12 - liczba pozostałych iteracji (n)
;   r13 - aktualny indeks w przetwarzanym napisie źródłowym
;   r14 - długość napisu źródłowego
;   r15 - wskaźnik na początek napisu źródłowego
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

default rel

section .text
global _start

_start:
    ; Sprawdzenie liczby argumentów (argc musi wynosić dokładnie 2)
    mov     rbp, [rsp]                  ; rbp = argc
    cmp     rbp, 2
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

    ; Kontrola przepełnienia 32-bitowego przed mnożeniem (max n = 4294967295) ; To chyba można usunąć
    mov     rdx, 429496729
    cmp     rax, rdx
    ja      error_exit_no_free          ; rax > 429496729 -> przepełnienie po mnożeniu
    jne     .multiply
    cmp     rcx, 5
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

    mov     r12, rax                    ; r12 = n (liczba iteracji)

    ; Alokacja początkowego bufora na wejście (1MB) za pomocą sys_mmap
    mov     rdi, 0                      ; System wybiera adres
    mov     rsi, 1048576                ; Rozmiar początkowy = 1MB
    mov     rdx, 3                      ; PROT_READ | PROT_WRITE
    mov     r10, 0x22                   ; MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1                      ; Brak pliku
    mov     r9, 0                       ; Offset = 0
    mov     rax, 9                      ; sys_mmap
    syscall
    cmp     rax, -4095
    jae     error_exit_no_free          ; Błąd alokacji
    mov     [input_buf], rax
    mov     qword [input_cap], 1048576
    mov     qword [input_len], 0

    ; Pętla wczytywania całego standardowego wejścia (minimalizacja syscalli)
.read_loop:
    mov     rdi, 0                      ; Stdin
    mov     rsi, [input_buf]
    add     rsi, [input_len]            ; Adres zapisu = początek + aktualny rozmiar
    mov     rdx, [input_cap]
    sub     rdx, [input_len]            ; rdx = pozostała pojemność bufora
    mov     rax, 0                      ; sys_read
    syscall

    cmp     rax, 0
    je      .read_done                  ; EOF (koniec danych)
    jl      error_cleanup_exit          ; Błąd odczytu

    add     [input_len], rax            ; Zaktualizowanie rozmiaru danych

    ; Sprawdzenie czy bufor się zapełnił - jeśli tak, podwajamy pojemność
    mov     rcx, [input_len]
    cmp     rcx, [input_cap]
    jne     .read_loop

    mov     rdi, [input_buf]            ; Stary adres
    mov     rsi, [input_cap]            ; Stary rozmiar
    shl     rsi, 1                      ; Nowy rozmiar = stary * 2
    mov     rdx, rsi                    ; Przekazanie do rdx jako new_size
    mov     rsi, [input_cap]            ; Ponowne załadowanie old_size do rsi
    mov     r10, 1                      ; MREMAP_MAYMOVE
    mov     rax, 25                     ; sys_mremap
    syscall
    cmp     rax, -4095
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
    cmp     rbx, rdi                    ; Co tu się dzieje???
    jae     error_cleanup_exit          ; Brak znaku nowej linii -> błąd
    cmp     byte [rbx], 10              ; Czy to '\n'?
    je      .found_start_nl
    mov     al, [rbx]
    cmp     al, 33
    jb      error_cleanup_exit          ; Niepoprawny symbol (< 33)
    cmp     al, 126
    ja      error_cleanup_exit          ; Niepoprawny symbol (> 126)
    inc     rbx
    jmp     .find_start_nl

.found_start_nl:
    mov     rdx, rbx
    sub     rdx, rsi                    ; rdx = długość napisu początkowego
    mov     [bufA_len], rdx
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
    cmp     byte [rbx], 10
    je      .parsing_finished

.not_trailing_nl:
    ; Pobranie symbolu, który ma być zastępowany
    xor     eax, eax
    mov     al, [rbx]
    cmp     al, 33
    jb      error_cleanup_exit
    cmp     al, 126
    ja      error_cleanup_exit

    ; Sprawdzenie unikalności reguły (maksymalnie jedna reguła na symbol)
    mov     r13, rax
    shl     r13, 4                      ; Indeksowanie tablicy struktur (16 bajtów na wpis)
    lea     r14, [rules_table]
    add     r14, r13
    cmp     qword [r14], 0              ; Sprawdzenie czy wskaźnik jest już ustawiony
    jne     error_cleanup_exit          ; Powtórzona reguła -> błąd

    ; Szukanie końca linii reguły
    lea     rcx, [rbx + 1]              ; Start ciągu zastępującego
.find_rule_nl:
    cmp     rcx, rdi
    jae     error_cleanup_exit          ; Brak domykającego '\n' -> błąd
    cmp     byte [rcx], 10
    je      .found_rule_nl
    mov     r9b, [rcx]
    cmp     r9b, 33
    jb      error_cleanup_exit
    cmp     r9b, 126
    ja      error_cleanup_exit
    inc     rcx
    jmp     .find_rule_nl

.found_rule_nl:
    lea     r8, [rbx + 1]               ; r8 = wskaźnik na ciąg zastępujący
    mov     r10, rcx
    sub     r10, r8                     ; r10 = długość ciągu zastępującego

    ; Zapisanie reguły w tabeli rozproszonej
    mov     [r14], r8                   ; Zapis adresu
    mov     [r14 + 8], r10              ; Zapis długości

    mov     rbx, rcx
    inc     rbx                         ; Przejście do następnej linii
    jmp     .parse_rules_loop

.parsing_finished:
    ; Dobór optymalnego rozmiaru alokacji dla buforów roboczych A i B
    mov     rsi, 1048576                ; Domyślnie 1MB
    cmp     rsi, [bufA_len]
    jae     .alloc_buffers
    mov     rsi, [bufA_len]             ; Jeśli napis początkowy jest większy, rezerwujemy więcej

.alloc_buffers:
    mov     [bufA_cap], rsi
    mov     [bufB_cap], rsi

    ; Alokacja bufora A
    mov     rdi, 0
    mov     rdx, 3
    mov     r10, 0x22
    mov     r8, -1
    mov     r9, 0
    mov     rax, 9
    syscall
    cmp     rax, -4095
    jae     error_cleanup_exit
    mov     [bufA_ptr], rax

    ; Alokacja bufora B
    mov     rdi, 0
    mov     rsi, [bufB_cap]
    mov     rdx, 3
    mov     r10, 0x22
    mov     r8, -1
    mov     r9, 0
    mov     rax, 9
    syscall
    cmp     rax, -4095
    jae     error_cleanup_exit
    mov     [bufB_ptr], rax

    ; Skopiowanie napisu początkowego do bufora A
    mov     rsi, [input_buf]
    mov     rdi, [bufA_ptr]
    mov     rcx, [bufA_len]
    rep movsb                           ; Wydajne kopiowanie blokowe

    ; Główna pętla wykonująca n iteracji przekształceń fraktala


.iteration_loop:
    test    r12, r12
    jz      .generation_done            ; Jeśli n == 0, pomijamy pętlę

    mov     r15, [bufA_ptr]             ; r15 = źródło (src_ptr)
    mov     r14, [bufA_len]             ; r14 = długość źródła (src_len)
    xor     r13, r13                    ; r13 = aktualny indeks źródła = 0
    mov     qword [bufB_len], 0         ; Wyczyszczenie długości bufora docelowego

.src_char_loop:
    cmp     r13, r14
    jae     .src_char_loop_done         ; Koniec przetwarzania bieżącego napisu

    xor     eax, eax
    mov     al, [r15 + r13]             ; al = aktualnie badany znak c

    ; Sprawdzenie istnienia reguły dla znaku c
    shl     rax, 4                      ; c * 16 (przesunięcie w tabeli reguł)
    lea     rbx, [rules_table]
    add     rbx, rax
    mov     r8, [rbx]                   ; r8 = adres zamiennika
    mov     r9, [rbx + 8]               ; r9 = długość zamiennika

    test    r8, r8
    jnz     .apply_rule                 ; Reguła istnieje

    ; Brak reguły -> znak przechodzi niezmieniony (zamiana na samego siebie)
    lea     r8, [r15 + r13]             ; Adres oryginalnego znaku jako zamiennik
    mov     r9, 1                       ; Długość = 1

.apply_rule:
    ; Sprawdzenie czy bufor docelowy (B) pomieści dane
    mov     rcx, [bufB_len]
    add     rcx, r9                     ; rcx = wymagany rozmiar po dodaniu
    cmp     rcx, [bufB_cap]
    jbe     .capacity_ok                ; Miejsce jest wystarczające

    ; Dynamiczne powiększenie bufora docelowego (podwojenie lub dopasowanie do zapotrzebowania)
    mov     rsi, [bufB_cap]
    shl     rsi, 1
    cmp     rsi, rcx
    jae     .grow_b
    mov     rsi, rcx                    ; Jeśli podwojenie to za mało, weź dokładnie tyle, ile trzeba

.grow_b:
    push    r8                          ; Zachowanie wskaźników przed syscall_mremap
    push    r9
    mov     rdi, [bufB_ptr]
    mov     rdx, rsi                    ; rdx = new_size
    mov     rsi, [bufB_cap]             ; rsi = old_size
    mov     r10, 1                      ; MREMAP_MAYMOVE
    mov     rax, 25                     ; sys_mremap
    syscall
    pop     r9
    pop     r8
    cmp     rax, -4095
    jae     error_cleanup_exit

    mov     [bufB_ptr], rax
    mov     [bufB_cap], rdx             ; Aktualizacja pojemności

.capacity_ok:
    ; Kopiowanie ciągu zastępującego do bufora docelowego
    mov     rsi, r8                     ; Źródło (r8)
    mov     rdi, [bufB_ptr]
    add     rdi, [bufB_len]             ; Cel = początek bufora + bieżąca długość
    mov     rcx, r9                     ; Liczba bajtów (r9)
    rep movsb

    add     [bufB_len], r9              ; Zwiększenie licznika długości celu
    inc     r13                         ; Przejście do następnego znaku źródła
    jmp     .src_char_loop

.src_char_loop_done:
    ; Zamiana buforów miejscami (A staje się B, B staje się A na kolejną iterację)
    mov     rax, [bufA_ptr]
    mov     rbx, [bufB_ptr]
    mov     [bufA_ptr], rbx
    mov     [bufB_ptr], rax

    mov     rax, [bufA_cap]
    mov     rbx, [bufB_cap]
    mov     [bufA_cap], rbx
    mov     [bufB_cap], rax

    mov     rax, [bufB_len]
    mov     [bufA_len], rax

    dec     r12                         ; Zmniejszenie licznika n
    jnz     .iteration_loop             ; Kolejna iteracja

.generation_done:
    ; Wypisanie końcowego napisu na standardowe wyjście (sys_write)
    mov     rsi, [bufA_ptr]
    mov     rdx, [bufA_len]
    xor     rbx, rbx                    ; rbx = liczba bajtów już zapisanych

.write_loop:
    cmp     rbx, rdx
    jae     .write_done                 ; Zapisano cały ciąg
    
    mov     rdi, 1                      ; Stdout
    mov     rsi, [bufA_ptr]
    add     rsi, rbx                    ; Przesunięcie o już wysłane dane
    mov     rdx, [bufA_len]
    sub     rdx, rbx                    ; Liczba pozostałych bajtów do wysłania
    mov     rax, 1                      ; sys_write
    syscall
    cmp     rax, 0
    jle     error_cleanup_exit          ; Błąd zapisu
    
    add     rbx, rax                    ; Zwiększenie licznika wysłanych danych
    mov     rdx, [bufA_len]
    jmp     .write_loop

.write_done:
    ; Wypisanie obowiązkowego znaku nowej linii na końcu działania programu
    mov     rax, 1                      ; sys_write
    mov     rdi, 1                      ; Stdout
    push    10                          ; Umieszczenie kodu '\n' na stosie
    mov     rsi, rsp                    ; Wskazanie na stos jako bufor danych
    mov     rdx, 1                      ; 1 bajt
    syscall
    pop     rcx                         ; Przywrócenie porządku na stosie
    cmp     rax, 1
    jne     error_cleanup_exit

    ; Poprawne zakończenie działania programu z kodem 0
    call    free_all_buffers            ; Jawne zwolnienie zasobów
    mov     rax, 60                     ; sys_exit
    mov     rdi, 0                      ; Kod powrotu = 0
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Funkcje pomocnicze, obsługa błędów i sprzątanie pamięci
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

free_all_buffers:
    ; Zwolnienie bufora wejściowego
    mov     rdi, [input_buf]
    test    rdi, rdi
    jz      .free_A
    mov     rsi, [input_cap]
    mov     rax, 11                     ; sys_munmap
    syscall
.free_A:
    ; Zwolnienie bufora roboczego A
    mov     rdi, [bufA_ptr]
    test    rdi, rdi
    jz      .free_B
    mov     rsi, [bufA_cap]
    mov     rax, 11                     ; sys_munmap
    syscall
.free_B:
    ; Zwolnienie bufora roboczego B
    mov     rdi, [bufB_ptr]
    test    rdi, rdi
    jz      .done
    mov     rsi, [bufB_cap]
    mov     rax, 11                     ; sys_munmap
    syscall
.done:
    ret

error_exit_no_free:
    ; Wywoływane przed jakąkolwiek alokacją pamięci
    mov     rax, 60                     ; sys_exit
    mov     rdi, 1                      ; Kod błędu = 1
    syscall

error_cleanup_exit:
    ; Wywoływane w przypadku błędu po alokacji - gwarantuje jawne zwolnienie pamięci
    call    free_all_buffers
    mov     rax, 60                     ; sys_exit
    mov     rdi, 1                      ; Kod błędu = 1
    syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Sekcja danych niezainicjalizowanych (.bss) - automatycznie zerowana przez system
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
section .bss
align 8
input_buf:   resq 1                     ; Wskaźnik na bufor wejściowy danych
input_cap:   resq 1                     ; Całkowita pojemność bufora wejściowego
input_len:   resq 1                     ; Rozmiar faktycznie wczytanych danych ze stdin

bufA_ptr:    resq 1                     ; Wskaźnik na dynamiczny bufor roboczy A
bufA_cap:    resq 1                     ; Pojemność bufora A
bufA_len:    resq 1                     ; Długość napisu w buforze A

bufB_ptr:    resq 1                     ; Wskaźnik na dynamiczny bufor roboczy B
bufB_cap:    resq 1                     ; Pojemność bufora B
bufB_len:    resq 1                     ; Długość napisu w buforze B

; Tablica reguł zamiany mapująca kody ASCII (0-255) na pary struktur {wskaźnik, długość}.
; Rozmiar: 256 elementów * 16 bajtów = 4096 bajtów.
rules_table: resq 512
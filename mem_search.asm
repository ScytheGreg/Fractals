section .data
    msg db "Maksymalna zaalokowana pamiec wirtualna (bajty): ", 0
    msg_len equ $ - msg
    newline db 10

section .bss
    buffer resb 21         ; Bufor do konwersji liczby na tekst (max ~20 cyfr)

section .text
    global _start

_start:
    ; Inicjalizacja zakresu wyszukiwania binarnego (w stronach 4KB)
    mov rbx, 0              ; low = 0
    ; Maksymalna bezpieczna liczba stron, aby rozmiar w bajtach zmieścił się w 64 bitach
    mov rbp, 0xFFFFFFFFFFFFF ; high = (2^64 - 1) >> 12
    xor r12, r12            ; best_size = 0 (tu zapiszemy najlepszy udany wynik)

binary_search_loop:
    cmp rbx, rbp
    jg search_done          ; Jeśli low > high, kończymy wyszukiwanie

    ; mid = (low + high) / 2
    mov rax, rbx
    add rax, rbp
    shr rax, 1              ; rax = mid (liczba stron)
    mov r13, rax            ; r13 = kopia mid

    ; Obliczenie rozmiaru w bajtach: len = mid * 4096
    mov rsi, r13
    shl rsi, 12             ; rsi = len (bajtów)
    jz try_next_low         ; Jeśli len == 0, pomiń mmap i zwiększ low

    ; Wywołanie systemowe sys_mmap
    ; mmap(NULL, len, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
    mov rax, 9              ; nr sys_mmap dla x86_64
    xor rdi, rdi            ; addr = NULL (OS sam wybiera adres)
    ; rsi jest już ustawione na len
    xor rdx, rdx            ; prot = PROT_NONE (0) - najbezpieczniejsze do samych testów alokacji
    mov r10, 0x22           ; flags = MAP_PRIVATE (0x02) | MAP_ANONYMOUS (0x20)
    mov r8, -1              ; fd = -1
    xor r9, r9              ; offset = 0
    syscall

    ; Sprawdzenie wyniku (błędy w Linuksie są zwracane jako wartości z zakresu -4095 do -1)
    cmp rax, -4095
    jae mmap_failed         ; Jeśli rax >= -4095 (w sensie unsigned), mmap się nie powiódł

    ; Sukces! Zapisujemy ten rozmiar jako dotychczasowy najlepszy
    mov r12, r13
    shl r12, 12             ; r12 = aktualny sukces w bajtach

    ; Musimy natychmiast zwolnić tę pamięć (munmap), aby nie blokować kolejnych prób
    mov rdi, rax            ; addr (zwrócony przez mmap)
    mov rsi, r13
    shl rsi, 12             ; len
    mov rax, 11             ; nr sys_munmap
    syscall

    ; low = mid + 1
    mov rbx, r13
    inc rbx
    jmp binary_search_loop

try_next_low:
    mov rbx, r13
    inc rbx
    jmp binary_search_loop

mmap_failed:
    ; Porażka (np. ENOMEM) -> high = mid - 1
    mov rbp, r13
    dec rbp
    jmp binary_search_loop

search_done:
    ; Wypisanie komunikatu tekstowego
    mov rax, 1              ; nr sys_write
    mov rdi, 1              ; stdout
    mov rsi, msg
    mov rdx, msg_len
    syscall

    ; Wypisanie wyniku liczbowego (w bajtach) zapisanego w r12
    mov rax, r12
    call print_uint64

    ; Wypisanie znaku nowej linii
    mov rax, 1
    mov rdi, 1
    mov rsi, newline
    mov rdx, 1
    syscall

    ; Zakończenie programu
    mov rax, 60             ; nr sys_exit
    xor rdi, rdi            ; status = 0
    syscall


; --- Funkcja pomocnicza: Wypisanie liczby 64-bitowej w formacie dziesiętnym ---
print_uint64:
    mov rbx, 10
    mov rcx, buffer + 20    ; Zaczynamy od końca bufora

.convert_loop:
    xor rdx, rdx
    div rbx                 ; rax = iloraz, rdx = reszta
    add dl, '0'             ; Konwersja na ASCII
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .convert_loop

    ; rcx wskazuje teraz na początek tekstu liczby. Obliczamy długość:
    mov rsi, rcx
    mov rdx, buffer + 20
    sub rdx, rcx            ; rdx = długość ciągu

    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    syscall
    ret
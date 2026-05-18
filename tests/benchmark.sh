#!/usr/bin/env bash

# Kolory do wypisywania statusów
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

EXE="./discrete_fractal"
ASM_SRC="discrete_fractal.asm"

echo -e "${BLUE}[1/4] Kompilacja programu...${NC}"
nasm -f elf64 "$ASM_SRC" -o discrete_fractal.o
if [ $? -ne 0 ]; then
    echo -e "${RED}Błąd kompilacji NASM!${NC}"
    exit 1
fi

ld discrete_fractal.o -o discrete_fractal
if [ $? -ne 0 ]; then
    echo -e "${RED}Błąd linkowania!${NC}"
    exit 1
fi
rm discrete_fractal.o
echo -e "${GREEN}Skompilowano pomyślnie.${NC}\n"

# Funkcja pomocnicza do uruchamiania testu z pomiarem czasu i RAMu
run_bench() {
    local title="$1"
    local n_val="$2"
    local input_data="$3"

    echo -e "${BLUE}=== TEST: $title (n = $n_val) ===${NC}"

    # Wykorzystujemy /usr/bin/time do przechwycenia czasu i pamięci (RSS)
    # Wyjście przekierowujemy do /dev/null, żeby mierzyć czysty algorytm, a nie prędkość terminala
    /usr/bin/time -v $EXE "$n_val" <<< "$input_data" > /dev/null 2> .time_err

    if [ $? -ne 0 ]; then
        echo -e "${RED}[X] Program zakończył się błędem!${NC}"
        cat .time_err | grep -E "Command|Exit status"
    else
        echo -e "${GREEN}[V] Sukces!${NC}"
        # Wyciąganie kluczowych danych z raportu time
        local user_time=$(grep "User time" .time_err | awk '{print $4}')
        local sys_time=$(grep "System time" .time_err | awk '{print $4}')
        local max_ram=$(grep "Maximum resident set size" .time_err | awk '{print $6}')

        echo "    Czas procesora (User):   ${user_time}s"
        echo "    Czas systemowy (Sys):    ${sys_time}s"
        echo "    Maksymalny RAM (RSS):    ${max_ram} KB ($(echo "scale=2; $max_ram/1024" | bc) MB)"
    fi
    echo ""
    rm -f .time_err
}

# ------------------------------------------------------------------------------
# TEST 1: Skrajny przypadek n = 0
# ------------------------------------------------------------------------------
# Sprawdza poprawne wyjście z pętli bez wykonywania iteracji
TEST_1_INP=$(printf "A\nAAB\nBA\n")
run_bench "Przypadek brzegowy n=0" "0" "$TEST_1_INP"

# ------------------------------------------------------------------------------
# TEST 2: Wykładnicza eksplozja (Test strumieniowania i bufora 64KB)
# ------------------------------------------------------------------------------
# Klasyczny system Algae (A -> AB, B -> A). Długość ciągu rośnie jak ciąg Fibonacciego.
# Dla n=25 wygeneruje ciąg o długości 121393 znaków, ale przy n=28 to już miliony operacji.
# Pamięć powinna pozostać minimalna, rzędu kilku megabajtów (głównie bufor wejściowy).
TEST_2_INP=$(printf "A\nAAB\nBA\n")
run_bench "Strumieniowanie - System Algae (Średnie obciążenie)" "24" "$TEST_2_INP"

# ------------------------------------------------------------------------------
# TEST 3: Głęboki stos DFS (Test n rzędu milionów + mremap)
# ------------------------------------------------------------------------------
# Reguły: A -> B oraz B -> A. Rozmiar danych wyjściowych to zawsze dokładnie 1 bajt!
# Jednak głębokość rekurencji (stosu) wynosi dokładnie tyle, ile podane n.
# To przetestuje wydajność alokacji mremap oraz zachowanie pamięci przy ogromnym n.
TEST_3_INP=$(printf "A\nAB\nBA\n")

# Test dla n = 100 000 (Stos zajmie ok. 2.4 MB)
run_bench "Głęboki stos DFS (Głębokość 100k)" "100000" "$TEST_3_INP"

# Test dla n = 2 000 000 (Stos zajmie ok. 48 MB)
run_bench "Głęboki stos DFS (Głębokość 2 mln)" "2000000" "$TEST_3_INP"

# ------------------------------------------------------------------------------
# TEST 4: Walidacja błędów i przepełnienia parsera
# ------------------------------------------------------------------------------
# Próba podania n przekraczającego 32 bity (np. 5000000000) - program powinien natychmiast
# wyjść z kodem błędu 1 i nie alokować zbędnej pamięci.
run_bench "Parser - Przepełnienie 32-bitowego n (> 2^32-1)" "5000000000" "$TEST_3_INP"
#!/usr/bin/env python3
import subprocess
import sys

# Konfiguracja
EXEC_PATH = "./discrete_fractal"

# =====================================================================
# 1. WZORCOWA IMPLEMENTACJA (REFERENCJA)
# =====================================================================
def generate_reference_output(n, input_data):
    """
    Generuje poprawny wynik w Pythonie używając prostej rekurencji (DFS).
    Dzięki temu zachowuje się dokładnie tak samo jak Twój kod w ASM.
    """
    # Parsowanie wejścia
    lines = input_data.strip('\n').split('\n')
    if not lines or not lines[0]:
        return "\n"

    start_str = lines[0]
    rules = {}
    for line in lines[1:]:
        if len(line) >= 1:
            rules[line[0]] = line[1:]

    output = []

    # Funkcja rekurencyjna (DFS)
    def dfs(char, depth):
        if depth == 0 or char not in rules:
            output.append(char)
        else:
            for c in rules[char]:
                dfs(c, depth - 1)

    # Przetwarzanie każdego znaku ciągu startowego
    for c in start_str:
        dfs(c, n)

    # ASM dodaje znak nowej linii na samym końcu
    return "".join(output) + "\n"

# =====================================================================
# 2. ZESTAW TESTÓW
# =====================================================================
# Format: ("Nazwa testu", n, "Dane wejściowe")
TEST_CASES = [
    (
        "Przypadek brzegowy n=0",
        0,
        "A\nAB\nBA\n"
    ),
    (
        "Proste zastąpienie n=1",
        1,
        "A\nAB\nBA\n"
    ),
    (
        "Klasyczny L-system (Algae) n=6",
        6,
        "A\nAB\nBA\n"
    ),
    (
        "Zbiór Cantora n=4",
        4,
        "A\nABA\nBBB\n"
    ),
    (
        "Brakujące reguły (znaki stałe)",
        3,
        "A-B+A\nAA+\n" # Tylko 'A' ma regułę, '-' i 'B' i '+' zostają bez zmian
    ),
    (
        "Brak reguł (pusty słownik) n=10",
        10,
        "HELLO_WORLD\n" # Program powinien po prostu zwrócić startowy string
    ),
    (
        "Długie reguły (eksplozja objętości) n=3",
        3,
        "X\nXXYXZXYX\nYXX\nZYYYYY\n"
    ),
    (
        "Usunięcie znaku (pusta reguła) n=2",
        2,
        "ABC\nB\n" # 'B' zastępowane jest niczym (pusty ciąg za literą B)
    ),
    (
        "Głęboka permutacja n=15",
        15,
        "A\nBC\nCA\nAB\n"
    )
]

# =====================================================================
# 3. SPRAWDZARKA (DRIVER)
# =====================================================================
def run_tests():
    print(f"=== URUCHAMIANIE TESTÓW POPRAWNOŚCI DLA: {EXEC_PATH} ===")
    passed = 0
    total = len(TEST_CASES)

    for i, (name, n, inp) in enumerate(TEST_CASES, 1):
        print(f"Test {i}/{total}: {name} (n={n}) ... ", end="", flush=True)

        # 1. Uruchomienie asemblera
        try:
            process = subprocess.run(
                [EXEC_PATH, str(n)],
                input=inp,
                text=True,
                capture_output=True,
                timeout=5 # Bezpiecznik, żeby testy nie wisiały w nieskończoność
            )
        except FileNotFoundError:
            print(f"\n[BŁĄD] Nie znaleziono pliku {EXEC_PATH}. Skompiluj najpierw program!")
            sys.exit(1)
        except subprocess.TimeoutExpired:
            print(f"\n[FAIL] Przekroczono czas wykonania (Timeout)!")
            continue

        if process.returncode != 0:
            print(f"\n[FAIL] Program asemblerowy zwrócił błąd (kod {process.returncode})!")
            print(f"Błąd z stderr: {process.stderr.strip()}")
            continue

        asm_output = process.stdout

        # 2. Uruchomienie referencji
        ref_output = generate_reference_output(n, inp)

        # 3. Weryfikacja
        if asm_output == ref_output:
            print("\033[0;32mPASS\033[0m")
            passed += 1
        else:
            print("\033[0;31mFAIL\033[0m")
            print("--- OCZEKIWANO (Referencja) ---")
            # Skracamy log do 100 znaków, żeby nie zalać terminala przy dużych stringach
            print(ref_output[:100] + ("..." if len(ref_output) > 100 else ""))
            print("--- OTRZYMANO (Asembler) ---")
            print(asm_output[:100] + ("..." if len(asm_output) > 100 else ""))
            print("-------------------------------")

    print(f"\nWynik końcowy: {passed}/{total} testów zaliczonych.")
    if passed == total:
        print("\033[0;32m[!] Twój asembler to solidna maszyna! Gratulacje!\033[0m")
    else:
        sys.exit(1)

if __name__ == "__main__":
    run_tests()
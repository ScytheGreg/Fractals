#!/usr/bin/env python3
import subprocess
import sys
import time

def reference_stream(axiom, rules, n):
    """Generator, który leniwie (on-the-fly) zwraca kolejne znaki fraktala."""
    def dfs(char, depth):
        if depth == 0 or char not in rules:
            yield char
        else:
            for c in rules[char]:
                yield from dfs(c, depth - 1)

    for c in axiom:
        yield from dfs(c, n)
    yield '\n' # ASM dodaje nową linię na końcu

def run_streaming_test(n, axiom, rules_list):
    # Parsowanie reguł dla referencji
    rules = {r[0]: r[1:] for r in rules_list if r}

    # Przygotowanie wejścia dla programu ASM
    asm_input = axiom + "\n" + "\n".join(rules_list) + "\n"

    # Uruchomienie procesu ASM z przekierowaniem stdout do potoku
    process = subprocess.Popen(
        ["./discrete_fractal", str(n)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1 # Buforowanie linia po linii / blokowe
    )

    # Wstrzyknięcie danych wejściowych i zamknięcie stdin, żeby ASM zaczął działać
    process.stdin.write(asm_input)
    process.stdin.close()

    print(f"Uruchamiam test strumieniowy: n={n}...")
    start_time = time.time()

    chars_checked = 0
    mismatch = False

    # Inicjalizacja generatora referencyjnego
    ref_gen = reference_stream(axiom, rules, n)

    # Czytamy z ASM tak długo, jak sypie znakami
    while True:
        # Czytamy porcję danych (np. blok 4KB, żeby nie dławić wydajności pojedynczymi bajtami)
        asm_chunk = process.stdout.read(4096)
        if not asm_chunk:
            break

        for asm_char in asm_chunk:
            try:
                ref_char = next(ref_gen)
            except StopIteration:
                print(f"\n[BŁĄD] ASM wysłał za dużo znaków! Pozycja: {chars_checked}")
                mismatch = True
                break

            if asm_char != ref_char:
                print(f"\n[BŁĄD] Niezgodność znaków na pozycji {chars_checked}!")
                print(f"ASM: '{asm_char}', Referencja: '{ref_char}'")
                mismatch = False
                break

            chars_checked += 1
            if chars_checked % 10_000_000 == 0:
                print(f" -> Zweryfikowano pomyślnie {chars_checked // 1_000_000} mln znaków...", end="\r")

        if mismatch:
            break

    # Sprawdzenie, czy referencja nie miała więcej znaków
    if not mismatch:
        try:
            next(ref_gen)
            print(f"\n[BŁĄD] ASM skończył pracę za wcześnie! Referencja oczekiwała więcej znaków.")
            mismatch = True
        except StopIteration:
            pass

    process.wait()
    end_time = time.time()

    if mismatch or process.returncode != 0:
        print(f"\n❌ TEST NIEZALICZONY. Kod błędu ASM: {process.returncode}")
        sys.exit(1)
    else:
        duration = end_time - start_time
        speed = (chars_checked / duration) / 1_000_000 if duration > 0 else 0
        print(f"\n✅ SUKCES! Przetworzono {chars_checked} znaków w {duration:.2f}s ({speed:.2f} mln znaków/s).")

if __name__ == "__main__":
    # Test eksplozji (System Algae)
    # Dla n=26 wygeneruje 242 786 znaków (szybki test)
    # Dla n=32 wygeneruje 7 049 123 znaków
    # Możesz tu bezpiecznie wpisać większe n, np. 35, jeśli chcesz solidnie obciążyć procesor
    AXIOM = "A"
    RULES = ["AAB", "BAB"]

    run_streaming_test(n=24, axiom=AXIOM, rules_list=RULES)
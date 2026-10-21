#!/usr/bin/env python3
import subprocess
import sys

# Configuration
EXEC_PATH = "./discrete_fractal"

# =====================================================================
# 1. REFERENCE IMPLEMENTATION
# =====================================================================
def generate_reference_output(n, input_data):
    """
    Generate expected output in Python using simple recursion (DFS).
    This mirrors the behavior of the assembly implementation.
    """
    # Parse input.
    lines = input_data.strip('\n').split('\n')
    if not lines or not lines[0]:
        return "\n"

    start_str = lines[0]
    rules = {}
    for line in lines[1:]:
        if len(line) >= 1:
            rules[line[0]] = line[1:]

    output = []

    # Recursive function (DFS).
    def dfs(char, depth):
        if depth == 0 or char not in rules:
            output.append(char)
        else:
            for c in rules[char]:
                dfs(c, depth - 1)

    # Process each character in the starting string.
    for c in start_str:
        dfs(c, n)

    # Assembly adds a newline at the end.
    return "".join(output) + "\n"

# =====================================================================
# 2. TEST CASES
# =====================================================================
# Format: ("Test name", n, "Input data")
TEST_CASES = [
    (
        "Boundary case n=0",
        0,
        "A\nAB\nBA\n"
    ),
    (
        "Single replacement n=1",
        1,
        "A\nAB\nBA\n"
    ),
    (
        "Classic L-system (Algae) n=6",
        6,
        "A\nAB\nBA\n"
    ),
    (
        "Cantor set n=4",
        4,
        "A\nABA\nBBB\n"
    ),
    (
        "Missing rules (unchanged symbols)",
        3,
        "A-B+A\nAA+\n" # Only 'A' has a rule; '-', 'B', and '+' remain unchanged.
    ),
    (
        "No rules (empty dictionary) n=10",
        10,
        "HELLO_WORLD\n" # The program should return the starting string unchanged.
    ),
    (
        "Long rules (rapid growth) n=3",
        3,
        "X\nXXYXZXYX\nYXX\nZYYYYY\n"
    ),
    (
        "Character deletion (empty rule) n=2",
        2,
        "ABC\nB\n" # 'B' is replaced with nothing (empty replacement string).
    ),
    (
        "Deep permutation n=15",
        15,
        "A\nBC\nCA\nAB\n"
    ),
        (
            "Empty output n = 10",
            10,
            "aaaa\nabbb\nbccc\ncddd\ndeee\nefff\nfggg\ng\n"
        ),
        (
            "Large input",
            5,
            ('A' * int(1e7) + 'B' * int(1e7) + "\nA\n")
        )
]

# =====================================================================
# 3. SPRAWDZARKA (DRIVER)
# =====================================================================
def run_tests():
    print(f"=== RUNNING CORRECTNESS TESTS FOR: {EXEC_PATH} ===")
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
                timeout=5 # Prevent tests from hanging indefinitely.
            )
        except FileNotFoundError:
            print(f"\n[ERROR] Executable {EXEC_PATH} not found. Build the program first!")
            sys.exit(1)
        except subprocess.TimeoutExpired:
            print(f"\n[FAIL] Execution timed out!")
            continue

        if process.returncode != 0:
            print(f"\n[FAIL] Assembly program returned an error (status {process.returncode})!")
            print(f"stderr: {process.stderr.strip()}")
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
            print("--- EXPECTED (Reference) ---")
            # Limit logs to 100 characters for large strings.
            print(ref_output[:100] + ("..." if len(ref_output) > 100 else ""))
            print("--- ACTUAL (Assembly) ---")
            print(asm_output[:100] + ("..." if len(asm_output) > 100 else ""))
            print("-------------------------------")

    print(f"\nFinal result: {passed}/{total} tests passed.")
    if passed == total:
        print("\033[0;32m[!] All tests passed!\033[0m")
    else:
        sys.exit(1)

if __name__ == "__main__":
    run_tests()

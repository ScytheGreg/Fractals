#!/usr/bin/env python3
import subprocess
import sys
import time

def reference_stream(axiom, rules, n):
    """Generator that lazily yields successive fractal characters."""
    def dfs(char, depth):
        if depth == 0 or char not in rules:
            yield char
        else:
            for c in rules[char]:
                yield from dfs(c, depth - 1)

    for c in axiom:
        yield from dfs(c, n)
    yield '\n' # Assembly adds a newline at the end.

def run_streaming_test(n, axiom, rules_list):
    # Parse rules for the reference implementation.
    rules = {r[0]: r[1:] for r in rules_list if r}

    # Prepare input for the assembly program.
    asm_input = axiom + "\n" + "\n".join(rules_list) + "\n"

    # Run the assembly process with stdout connected to a pipe.
    process = subprocess.Popen(
        ["./discrete_fractal", str(n)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1 # Buforowanie linia po linii / blokowe
    )

    # Send input and close stdin so the assembly program can start.
    process.stdin.write(asm_input)
    process.stdin.close()

    print(f"Running streaming test: n={n}...")
    start_time = time.time()

    chars_checked = 0
    mismatch = False

    # Initialize the reference generator.
    ref_gen = reference_stream(axiom, rules, n)

    # Read assembly output until the stream ends.
    while True:
        # Read chunks (for example, 4 KB) to avoid per-byte I/O overhead.
        asm_chunk = process.stdout.read(4096)
        if not asm_chunk:
            break

        for asm_char in asm_chunk:
            try:
                ref_char = next(ref_gen)
            except StopIteration:
                print(f"\n[ERROR] Assembly produced extra output at position {chars_checked}.")
                mismatch = True
                break

            if asm_char != ref_char:
                print(f"\n[ERROR] Character mismatch at position {chars_checked}.")
                print(f"ASM: '{asm_char}', Referencja: '{ref_char}'")
                mismatch = False
                break

            chars_checked += 1
            if chars_checked % 10_000_000 == 0:
                print(f" -> Successfully checked {chars_checked // 1_000_000} million characters...", end="\r")

        if mismatch:
            break

    # Check whether the reference has more output.
    if not mismatch:
        try:
            next(ref_gen)
            print(f"\n[ERROR] Assembly stopped early; the reference expected more output.")
            mismatch = True
        except StopIteration:
            pass

    process.wait()
    end_time = time.time()

    if mismatch or process.returncode != 0:
        print(f"\n❌ TEST FAILED. Assembly exit status: {process.returncode}")
        sys.exit(1)
    else:
        duration = end_time - start_time
        speed = (chars_checked / duration) / 1_000_000 if duration > 0 else 0
        print(f"\n✅ SUCCESS! Processed {chars_checked} characters in {duration:.2f}s ({speed:.2f} million characters/s).")

if __name__ == "__main__":
    # Test eksplozji (System Algae)
    # At n=26 this generates 242,786 characters (quick test).
    # At n=32 this generates 7,049,123 characters.
    # Increase n (for example, to 35) for a heavier CPU load.

    AXIOM = "A"
    RULES = ["AAB", "BAB"]

    run_streaming_test(n=24, axiom=AXIOM, rules_list=RULES)

    AXIOM = "A"
    RULES = [chr(i) + chr(i)+ chr(i) for i in range(33, ord('A'))] + [chr(i) + chr(i) + chr(i) for i in range(ord('A') + 1, 126)] + ["AAAB"]

    run_streaming_test(n=20, axiom=AXIOM, rules_list=RULES)


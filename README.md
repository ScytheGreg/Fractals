# Discrete Fractal Generator

A Linux x86-64 assembly program that generates discrete string fractals by repeatedly applying symbol replacement rules. The implementation uses NASM and Linux system calls for input, output, and memory management.

## Build

Requirements: NASM, GNU `ld`, and a Linux x86-64 environment.

```bash
make
```

This builds the `discrete_fractal` executable. The equivalent assembler and linker commands are:

```bash
nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o discrete_fractal.o discrete_fractal.asm
ld -pie -I /lib64/ld-linux-x86-64.so.2 --fatal-warnings -o discrete_fractal discrete_fractal.o
```

## Usage

```bash
./discrete_fractal <iterations> < input.txt
```

The iteration count is a base-10 integer from 0 through 2³²−1. Input is line-based:

1. The first line is the starting string; it may be empty.
2. Each following line defines one replacement: the first symbol is the symbol to replace, and the rest of the line is its replacement string. A replacement may be empty. Each symbol can have at most one rule.

Symbols are printable ASCII characters with codes 33–126. Every input line must end with a newline. The program applies all applicable replacements simultaneously at each iteration, then writes the resulting string followed by a newline.

### Example

```text
$ printf 'A\nAAB\nBA\n' | ./discrete_fractal 4
ABAABABA
```

## Implementation notes

- Written in x86-64 NASM assembly, with direct Linux system calls.
- Uses memory mapped buffers and expands output incrementally, avoiding a fixed maximum fractal-string length; available memory is the practical limit.
- Checks the argument, input format, and system-call results, and exits with status 0 on success or 1 on error.

## Tests and benchmarks

The `tests/` directory contains invalid-input cases, Python checker and fuzzing utilities, and benchmarks. Run the available targets with:

```bash
make fuzz
make bench
```

The Python-based targets require Python 3. Benchmark results measure performance and memory use; they do not validate output correctness.

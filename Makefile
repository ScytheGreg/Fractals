all: discrete_fractal

discrete_fractal: discrete_fractal.asm
	nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o discrete_fractal.o discrete_fractal.asm
	ld -pie -I /lib64/ld-linux-x86-64.so.2 --fatal-warnings -o discrete_fractal discrete_fractal.o

example: example.asm
	nasm -f elf64 example.asm
	ld -o example example.o

mem_search: mem_search.asm
	nasm -f elf64 mem_search.asm -o mem_search.o
	ld mem_search.o -o mem_search

bench:
	./tests/benchmark.sh
	./tests/python/streaming_benchmark.py

fuzz:
	./tests/python/checker.py
	./tests/python/fuzz_runner.sh

.PHONY: all clean bench fuzz

clean:
	rm -f discrete_fractal mem_search

all: discrete_fractal

discrete_fractal: discrete_fractal.asm
	nasm -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel -o discrete_fractal.o discrete_fractal.asm -g -O0
	ld -pie -I /lib64/ld-linux-x86-64.so.2 --fatal-warnings -o discrete_fractal discrete_fractal.o


mem_search: mem_search.asm
	nasm -f elf64 mem_search.asm -o mem_search.o
	ld mem_search.o -o mem_search

test:
	./tests/benchmark.sh

.PHONY: all clean test

clean:
	rm -f discrete_fractal
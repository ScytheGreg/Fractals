global _start

SYS_EXIT equ 60

_start:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
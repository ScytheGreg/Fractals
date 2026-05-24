section .rodata

    SYS_EXIT equ 60


section .text

_start:
    ; Wczytanie parametru n
    mov rbp, [rsp]
    cmp rbp, 2
    jne .exit_error


.exit:
    xor rdi, rdi
    mov rax, SYS_EXIT
    syscall


.exit_error:
    mov rdi, 1
    mov rax, SYS_EXIT
    syscall
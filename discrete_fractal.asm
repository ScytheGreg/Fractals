section .rodata
    ; --- SYSTEM CALL NUMBERS (x86_64) ---
    SYS_READ        equ 0
    SYS_WRITE       equ 1
    SYS_MMAP        equ 9
    SYS_MUNMAP      equ 11
    SYS_EXIT        equ 60

    ; --- FILE DESCRIPTORS & CONSTANTS ---
    STD_IN_FD       equ 0
    STD_OUT_FD      equ 1
    NEW_LINE        equ 10

    ; --- MMAP FLAGS ---
    PROT_FLAGS      equ 3       ; PROT_READ (1) | PROT_WRITE (2) - Allow read and write
    MAP_FLAGS       equ 0x22    ; MAP_PRIVATE (0x02) | MAP_ANONYMOUS (0x20) - Not backed by a file

section .bss
    align 8
    target_n resq 1             ; The 'n' parameter (number of iterations) parsed from argv[1]

    ; --- READ BUFFER TRACKING ---
    read_buf        resq 1      ; Read buffer start pointer (dynamically allocated)
    read_cup        resq 1      ; Read buffer capacity (currently allocated memory size)
    read_end        resq 1      ; Read input end pointer (stops exactly after the last read char)

    first_line_end  resq 1      ; Pointer to the end of the first line (the initial fractal string)

    ; --- WRITE BUFFER TRACKING ---
    write_buf       resq 1      ; Write buffer start pointer (4KB chunk)
    write_end       resq 1      ; Write buffer end bound

    ; --- DFS STACK TRACKING ---
    stack_buf       resq 1      ; Custom stack buffer start pointer
    stack_end       resq 1      ; Custom stack buffer end bound

    ; --- REPLACEMENT RULES ARRAY ---
    ; Pattern array and stack structure:
    ; typedef struct pattern_node (stack_node) {
    ;       size_t start        ; Pointer to the replacement string start
    ;       size_t end          ; Pointer to the replacement string end
    ; }
    ; Every supported ascii number (from 33 '!' to 126 '~') takes two qwords (16 bytes)
    patterns        resq 188    ; (126 - 32) * 2 qwords = 188 qwords (1504 bytes)

section .text
default rel
global _start

; =======================================================================================
; HIGH LEVEL: Gracefully releases dynamically allocated memory using sys_munmap.
; LOW LEVEL : Tracks errors by setting rdi to 1 (exit code) if any munmap call fails.
; =======================================================================================
memory_cleanup:
    ; Read buffer cleanup
    mov rax, SYS_MUNMAP
    mov rdi, [read_buf]         ; Source address to unmap
    mov rsi, [read_cup]         ; Length of the mapping
    syscall

    xor rdi, rdi                ; Assume success (exit code 0 in rdi)
    cmp rax, -4095              ; Check if sys_munmap returned an error (addr > -4095)
    seta dil                    ; Set dil (lowest byte of rdi) to 1 if error occurred

    ; Write and Stack buffer cleanup (they were allocated as a single continuous block)
    mov rax, SYS_MUNMAP
    mov rdi, [write_buf]        ; Source address to unmap (start of combined block)
    mov rsi, [stack_end]        ; Calculate Length: stack_end - write_buf
    sub rsi,  rdi               ; rsi now holds the total size of combined block
    syscall

    cmp rax, -4095              ; Check if second sys_munmap failed
    seta cl                     ; Set cl to 1 if error occurred
    and dil, cl                 ; Combine previous error (dil) and current error (cl)
    ret                         ; Return to caller (rdi holds 1 on error, 0 on success)

_start:
; =======================================================================================
; %%%%% PARSE 'n' PARAMETER %%%%%
; HIGH LEVEL: Validates argc == 2, parses argv[1] (string) into target_n (integer).
; LOW LEVEL : Loops over argv[1] characters, multiplies running total by 10, adds digit.
; =======================================================================================
    mov rbp, [rsp]              ; Load argc from stack top
    cmp rbp, 2                  ; if(argc != 2)
    jne .exit_error             ;     exit(1)

    mov rbp, [rsp + 16]         ; Load argv[1] pointer (rsp + 8 is argv[0])
    xor rcx, rcx                ; byte index of n ; i = 0
    xor rdi, rdi                ; result_n = 0
.parse_n_loop:
    movzx rbx, byte [rbp + rcx] ; bl = argv[1][i] (load next char, zero-extend to rbx)

    test bl, bl                 ; test end of word (null terminator)
    jz .parse_n_done            ; if null, parsing is done

    cmp bl, '0'                 ; Validate char is >= '0'
    jb .exit_error              ; if (c < '0') exit(1)

    cmp bl, '9'                 ; Validate char is <= '9'
    ja .exit_error              ; if (c > '9') exit(1)

    sub rbx, '0'                ; Convert ASCII char to numeric value

    imul edi, 10                ; result_n *= 10 (shift digits left in base 10)
    jc   .exit_error            ; Check for multiplication overflow
    add  edi, ebx               ; Add current digit to result
    jc   .exit_error            ; Check for addition overflow

    inc rcx                     ; ++i (move to next character)
    jmp .parse_n_loop           ; Repeat for next character

.parse_n_done:
    mov [target_n], rdi         ; Save the final integer 'n' in a global variable

; =======================================================================================
; %%%%% READ INPUT to READ BUFFER %%%%%
; HIGH LEVEL: Reads all stdin data into a dynamic buffer. If the buffer is full, it
;             doubles the capacity via mmap, copies old data, and frees the old buffer.
; LOW LEVEL : Uses sys_read. rbx = total capacity, r12 = used size, r13 = target capacity.
; =======================================================================================
                                ; Registers:
                                ;   rbp - read buffer start pointer
    xor rbx, rbx                ; rbx: Current size of allocated memory for read buffer (0)
    mov r13, 1024               ; r13: Target memory allocation size (starts at 1KB)
    xor r12, r12                ; r12: Writing length (total bytes read so far)

.read_loop:
    ; Make space for data
    cmp rbx, r13                ; Check if required memory (r13) is already allocated (rbx)
    jae .space_buf_ok           ; If allocated >= required, skip reallocation

    ; No space for input - Reallocate via MMAP
    mov rax, SYS_MMAP           ; syscall number for mmap
    xor rdi, rdi                ; address = NULL (let OS choose)
    mov rsi, r13                ; length = Target capacity (r13)
    mov rdx, PROT_FLAGS         ; protection = PROT_READ | PROT_WRITE
    mov r8, -1                  ; fd = -1 (Required for anonymous mapping)
    xor r9, r9                  ; Offset = 0
    mov r10, MAP_FLAGS          ; flags = MAP_PRIVATE | MAP_ANONYMOUS
    syscall

    cmp rax, -4095              ; Check for mmap error
    jae .exit_error

    mov rbp, rax                ; Save the new read buffer pointer to rbp

    test rbx, rbx               ; If current capacity is 0 (first allocation), nothing to copy
    jz .copy_done

    ; Copy old buffer data to the newly allocated buffer
    mov rdi, rax                ; Destination = new buffer
    mov rsi, [read_buf]         ; Source = old buffer
    mov rcx, r12                ; Reps = Current read length (number of bytes to copy)
    rep movsb                   ; Fast byte-by-byte copy using hardware instruction

    ; Free old buffer
    mov rax, SYS_MUNMAP
    mov rdi, [read_buf]         ; Source = old buffer
    mov rsi, rbx                ; Length = old capacity
    syscall

    cmp rax, -4095              ; Check for munmap error
    jae .exit_error

.copy_done:
    mov [read_buf], rbp         ; Save the new read buffer address to global variable
    mov rbx, r13                ; Update amount of allocated memory (current capacity = target)

.space_buf_ok:
    ; Read from standard input into the buffer
    mov rax, SYS_READ           ; syscall number for read
    mov rdi, STD_IN_FD          ; fd = 0 (stdin)
    mov rsi, [read_buf]         ; Buffer start
    add rsi, r12                ; Add offset of already read bytes (append mode)
    mov rdx, rbx                ; Calculate remaining space...
    sub rdx, r12                ;   ... Max read = total capacity (rbx) - used space (r12)
    syscall

    cmp rax, -4095              ; Check for read error
    jae .exit_error             ;     exit(1)

    test rax, rax               ; If bytes read == 0 (EOF reached)
    jz .read_done               ;     break out of read loop

    add r12, rax                ; Add number of newly read bytes to total string length

    cmp rbx, r12                ; Check if buffer is completely full
    jne .read_loop              ; If not completely full, try reading more without resizing
    shl r13, 1                  ; Double the needed memory (r13 = r13 * 2)
    jmp .read_loop              ; Loop back to allocate and read

.read_done:
    lea rcx, [rbp + r12]        ; Calculate exact end pointer of the input
    mov [read_end], rcx         ; Save to global variable

    mov [read_cup], rbx         ; Save total allocated capacity

; =======================================================================================
; %%%%% PARSE INPUT %%%%%
; HIGH LEVEL: Scans the buffer to isolate the first line (initial string). Then parses
;             the remaining lines as replacement rules and builds a lookup table.
; =======================================================================================
    ; Find newline for the initial string
    mov rdi, [read_buf]         ; Read pointer (starts at beginning of input)
    mov rsi, [read_end]         ; Read bound (EOF)
.first_line_loop:
    cmp rdi, rsi                ; Test if we reached EOF without finding a newline
    ja .exit_error              ; Out of bound - no newline found (invalid input)

    movzx ebx, byte [rdi]       ; Load current character
    inc rdi;                    ; index++ (advance pointer)

    cmp bl, NEW_LINE            ; Check for newline (end of first line)
    je .first_line_end          ;

    cmp bl, 33                  ; Validate ASCII Lowerbound ('!')
    jb .exit_error

    cmp bl, 126                 ; Validate ASCII Upperbound ('~')
    ja .exit_error

    jmp .first_line_loop

.first_line_end:
    dec rdi                     ; Step back to point exactly at the newline character
    mov [first_line_end], rdi   ; Save this position (marks the end of the initial string)
    inc rdi                     ; Step forward to the start of the next line (rules)

    ; Read patterns table (replacement rules)
    lea rcx, [patterns]         ; rcx will keep patterns table base pointer

.read_pattern:
    cmp rdi, rsi                ; Check if we reached EOF
    jae .input_parse_done       ; End of patterns - parsing done

    movzx ebx, byte [rdi]       ; Load the symbol to be replaced
    inc rdi                     ; index++

    cmp bl, 33                  ; Validate rule symbol Lowerbound
    jb .exit_error

    cmp bl, 126                 ; Validate rule symbol Upperbound
    ja .exit_error

    sub bl, 33                  ; Normalize sign for array indexing (shift range to 0-93)
    movzx rax, bl               ; rax will keep the normalized index of the symbol
    mov rdx, rdi                ; rdx will keep the start position of replacement string

; For the given symbol, read the characters it transforms into
.read_rule_loop:
    cmp rdi, rsi                ; Test bound
    ja .exit_error              ; Reached EOF without a trailing newline

    movzx ebx, byte [rdi]       ; Load character of the replacement string
    inc rdi                     ; index++

    cmp bl, NEW_LINE            ; End of the replacement string
    je .rule_found

    cmp bl, 33                  ; Validate replacement char lowerbound
    jb .exit_error

    cmp bl, 126                 ; Validate replacement char upperbound
    ja .exit_error

    jmp .read_rule_loop

.rule_found:
    shl rax, 4                  ; multiply normalized index by 16 (2^4) - frame size of pattern_node
                                ; (each entry is 16 bytes: 8 bytes start ptr, 8 bytes end ptr)

    mov r8, [rcx + rax]         ; Load the existing start pointer for this symbol
    test r8, r8;                ; Test whether there already is a pattern for that sign
    jnz .exit_error             ; there should be none (only one rule per symbol allowed)

    mov [rcx + rax], rdx        ; Save pattern_node.start (pointer to start of replacement)
    mov rdx, rdi;               ; rdx = current pointer (points AFTER newline)
    dec rdx                     ; Calculate end pointer (points EXACTLY at newline)
    mov [rcx + rax + 8] , rdx   ; Save pattern_node.end

    jmp .read_pattern           ; Loop for the next rule

.input_parse_done:

; =======================================================================================
; %%%%% MAIN DFS LOOP %%%%%
; HIGH LEVEL: Instead of building giant strings in memory, this uses a Depth-First Search
;             approach. It dynamically resolves string replacements on-the-fly and writes
;             resolved characters directly to a 4KB output buffer.
; LOW LEVEL : Allocates a single block for both the write buffer (4KB) and the DFS stack.
;             Stack requires 16 bytes per iteration level (n * 16).
; =======================================================================================

    ; Allocate write buffer (4 kB) and stack_space (n * 16 B)
    mov rsi, [target_n]
    inc rsi                     ; For n = 0 allocate at least one level
    shl rsi, 4                  ; Calculate stack_space (rsi = (n + 1) * 16)

    ; MMAP Combined space
    mov rax, SYS_MMAP
    xor rdi, rdi                ; Address = NULL
    add rsi, 4096               ; Total size = stack_space + write buffer (4096)
    mov rdx, PROT_FLAGS         ; Read/Write
    mov r8, -1                  ; Anonymous mapping
    xor r9, r9                  ; Offset = 0
    mov r10, MAP_FLAGS
    syscall

    cmp rax, -4095              ; Handle errors
    ja .exit_error

    mov [write_buf], rax        ; Save write buf start pointer
    add rax, 4097               ; write_end is write_buf + 4096 + 1 (wait, 4097? effectively 4KB)
    mov [write_end], rax        ; Save write buf end bound

    mov [stack_buf], rax        ; Start the stack buffer right after the write buffer
    add rax, rsi                ; Add total requested size
    sub rax, 4096               ; Subtract write buffer size to get true stack end
    mov [stack_end], rax        ; Save stack buf end

; Main loop initialization
    mov r8,  [target_n]         ; r8 = Iterations to go (Current Depth, stops at 0)
    mov r9,  [read_buf]         ; r9 = Start pointer of currently processed string
    mov r10, [first_line_end]   ; r10 = End pointer of currently processed string
    mov r12, [write_buf]        ; r12 = Current write position in the output buffer
    mov r13, [write_end]        ; r13 = Write end bound
    dec r13                     ; Decrease bound by 1 to always leave space for final newline
    mov r14, [stack_buf]        ; r14 = Current Stack position

    lea rbx, [patterns]         ; rbx = Stable reference to patterns lookup table
    mov r15, r8                 ; r15 = Stable original 'n' to detect when we return to root

    ; Push the initial string onto the base of the stack (iteration 0 context)
    mov [r14], r9               ; Start position of zero iteration
    mov [r14 + 8], r10          ; End position of zero iteration

.process_epoch:
    mov r9,  [r14]              ; Load start of currently processed string from stack
    mov r10, [r14 + 8]          ; Load end of currently processed string from stack

    test r8, r8;                ; Check if we reached the maximum depth (n = 0 iterations left)
    jz  .write_to_buffer        ; If deepest level, print the character instead of expanding
.write_done:                    ; Return label after character is written or skipped
    cmp r9, r10                 ; Test if every sign in the current string has been processed
    jae .decrease_epoch         ; If string is exhausted, go UP one level in the stack (decrease depth)

; If string is not exhausted, process the next character (Increase depth / expand rule)
    mov rcx, [r14]              ; Load current string pointer
    inc rcx                     ; Advance pointer by 1 (consume character)
    mov [r14], rcx              ; Save updated pointer back to stack (context for when we return)

    add r14, 16                 ; Increase stack position (Push new context frame)
    dec r8                      ; Decrease iterations to go (Go deeper)

    movzx rax, byte [r9]         ; Load the character we need to expand
    sub rax, 33                  ; Normalize to array index (shift -33)
    shl rax, 4                   ; Multiply by 16 (frame size of patterns)

    mov rcx, [rbx + rax]         ; Lookup replacement rule start pointer
    test rcx, rcx                ; Check if rule exists (pointer != 0)
    jz .no_rule_found            ; If no rule, fallback to keeping the character itself
    mov [r14], rcx               ; Save replacement start pointer to the new stack frame

    mov rcx, [rbx + rax + 8]     ; Lookup replacement rule end pointer
    mov [r14 + 8], rcx           ; Save replacement end pointer to the new stack frame

    jmp .process_epoch           ; Dive into the newly pushed replacement string

.no_rule_found:
    ; If no rule exists, the "replacement" is just the character itself
    mov [r14], r9               ; Save pointer to current char as "start" of replacement
    inc r9                      ; End pointer is exactly one position...
    mov [r14 + 8], r9           ;     ...behind that char
    jmp .process_epoch          ; Process this 1-character "replacement" string

.decrease_epoch:
    ; We finished processing a string at the current depth
    sub r14, 16                 ; Pop the stack (Decrease stack position)
    inc r8                      ; Increase iterations to go (We returned a level up)

    cmp r8, r15                 ; Check if we popped past the root level (r8 > original n)
    ja  .final_flush_write      ; If true, the entire fractal generation is finished

    jmp .process_epoch          ; Otherwise, resume processing the parent string

.write_to_buffer:
    ; We are at depth 0, time to output the character
    cmp r12, r13;               ; Test if write_buf is full (current pos >= bound)
    jae .flush_write            ; If full, flush buffer to stdout

    cmp r9, r10                 ; Test if the 1-character string is exhausted (bounds check)
    jae .write_done             ; If exhausted, go back to DFS logic

    movzx rax, byte [r9]        ; Load the character into al
    mov [r12], al               ; Save char to write buffer
    inc r9                      ; string_index++
    inc r12                     ; write_index++

    jmp .write_to_buffer        ; Loop back (will immediately hit .write_done because it's 1 char)

.final_flush_write:
    ; Entire DFS finished. Append the mandatory trailing newline.
    mov [r12], byte NEW_LINE    ; Add new line at the end of the output buffer
    inc r12                     ; Advance write pointer

.flush_write:
    ; Dumps the contents of the write buffer to STDOUT
    mov rax, SYS_WRITE
    mov rdi, STD_OUT_FD         ; File descriptor 1 (stdout)
    mov rsi, [write_buf]        ; Start of buffer
    mov rdx, r12                ; Calculate Number of bytes to write:
    sub rdx, rsi                ;     = current position (r12) - start (rsi)
    syscall

    cmp r8, r15                 ; Check if we are flushing because we are completely done
    ja .exit                    ; If done (r8 > original n), exit program

    mov r12, rsi                ; If just a periodic flush, reset write position to buffer start
    jmp .write_to_buffer        ; Return to writing the character that caused the flush

.exit:
    ; Successful exit
    call memory_cleanup         ; Free memory
    ; rdi is already set by memory_cleanup (0 on success, 1 on munmap failure)
    mov rax, SYS_EXIT
    syscall

.exit_error:
    ; Error exit
    call memory_cleanup         ; Free memory
    mov rdi, 1                  ; Force exit code 1
    mov rax, SYS_EXIT
    syscall
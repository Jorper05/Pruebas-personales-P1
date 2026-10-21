; =====================================================================
; ex04_msgpass.asm - Paso de mensajes: SEND / RECEIVE entre procesos
;
;   Dos procesos (P0 = padre, P1 = hijo) con ESPACIOS DE DIRECCIONES
;   SEPARADOS se comunican solo mediante mensajes explícitos por un
;   pipe del kernel:
;       SEND(dato, destino)  ->  write(fd, &dato, 8)
;       RECEIVE(buffer)      ->  read(fd, &buffer, 8)   (bloqueante)
;
;   Parte A: RECEIVE espera a que se ejecute el SEND correspondiente.
;   Parte B: "ping-pong" para medir la latencia de comunicación.
;
;   Las llamadas al sistema se hacen directamente con SYSCALL; printf
;   solo se usa para mostrar resultados.
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex04_msgpass.asm
;     gcc -no-pie ex04_msgpass.o -o ex04_msgpass
; =====================================================================
default rel
extern printf, fflush, exit
global main

SYS_READ   equ 0
SYS_WRITE  equ 1
SYS_PIPE   equ 22
SYS_NANOSLEEP equ 35
SYS_FORK   equ 57
SYS_WAIT4  equ 61
ROUNDS     equ 100000           ; viajes de ida y vuelta en la parte B

section .data
dato    dq 0                    ; cada proceso tendrá SU PROPIA copia
f_a0    db "[P0] Ejecuto RECEIVE (se bloquea hasta que P1 haga SEND)...", 10, 0
f_a1    db "[P1] Calculo durante 1 s y luego SEND(dato=%ld, P0)", 10, 0
f_a2    db "[P0] RECEIVE completado tras %ld ms: buffer=%ld, mi variable dato=%ld", 10, 0
f_b     db "[P0] %d viajes ida/vuelta en %ld ms -> latencia ~ %ld ns por mensaje", 10, 0
ts_1s   dq 1, 0                 ; struct timespec {1 s, 0 ns}

section .bss
fd_a    resd 2                  ; pipe P1 -> P0 (parte A) / P0 -> P1 (parte B)
fd_b    resd 2                  ; pipe P1 -> P0 (parte B)
buffer  resq 1
t0      resq 1

%include "sync.inc"

section .text
; SEND(rdi = fd, rsi = &dato)
send:
        mov     eax, SYS_WRITE
        mov     edx, 8
        syscall
        ret
; RECEIVE(rdi = fd, rsi = &buffer)
receive:
        mov     eax, SYS_READ
        mov     edx, 8
        syscall
        ret

main:
        push    rbx
        sub     rsp, 16                 ; alineada

        ; ================= PARTE A =================
        mov     eax, SYS_PIPE
        lea     rdi, [fd_a]
        syscall
        xor     edi, edi
        call    fflush                  ; vaciar stdout antes de fork()
        mov     eax, SYS_FORK
        syscall
        test    rax, rax
        jnz     .padre_a

        ; ---------- hijo: P1 ----------
        mov     qword [dato], 42        ; solo cambia la copia de P1
        lea     rdi, [f_a1]
        mov     rsi, [dato]
        xor     eax, eax
        call    printf
        xor     edi, edi
        call    fflush
        mov     eax, SYS_NANOSLEEP      ; "computar" 1 segundo
        lea     rdi, [ts_1s]
        xor     esi, esi
        syscall
        mov     edi, [fd_a+4]           ; extremo de escritura
        lea     rsi, [dato]
        call    send                    ; SEND(dato, P0)
        xor     edi, edi
        call    exit

.padre_a:
        mov     rbx, rax                ; pid del hijo
        lea     rdi, [f_a0]
        xor     eax, eax
        call    printf
        xor     edi, edi
        call    fflush
        call    now_ns
        mov     [t0], rax
        mov     edi, [fd_a]             ; extremo de lectura
        lea     rsi, [buffer]
        call    receive                 ; RECEIVE(buffer)  <-- bloquea
        call    now_ns
        sub     rax, [t0]
        xor     edx, edx
        mov     ecx, 1000000
        div     rcx
        lea     rdi, [f_a2]
        mov     rsi, rax
        mov     rdx, [buffer]
        mov     rcx, [dato]             ; ¡sigue en 0 en P0!
        xor     eax, eax
        call    printf
        mov     eax, SYS_WAIT4
        mov     rdi, rbx
        xor     esi, esi
        xor     edx, edx
        xor     r10, r10
        syscall

        ; ================= PARTE B =================
        mov     eax, SYS_PIPE
        lea     rdi, [fd_a]             ; P0 -> P1
        syscall
        mov     eax, SYS_PIPE
        lea     rdi, [fd_b]             ; P1 -> P0
        syscall
        xor     edi, edi
        call    fflush
        mov     eax, SYS_FORK
        syscall
        test    rax, rax
        jnz     .padre_b

        ; ---------- hijo: eco ----------
        mov     ebx, ROUNDS
.eco:   mov     edi, [fd_a]
        lea     rsi, [buffer]
        call    receive
        inc     qword [buffer]
        mov     edi, [fd_b+4]
        lea     rsi, [buffer]
        call    send
        dec     ebx
        jnz     .eco
        xor     edi, edi
        call    exit

.padre_b:
        push    rax                     ; pid del hijo
        push    rax
        call    now_ns
        mov     [t0], rax
        mov     qword [buffer], 0
        mov     ebx, ROUNDS
.ping:  mov     edi, [fd_a+4]
        lea     rsi, [buffer]
        call    send                    ; ping
        mov     edi, [fd_b]
        lea     rsi, [buffer]
        call    receive                 ; pong
        dec     ebx
        jnz     .ping
        call    now_ns
        sub     rax, [t0]
        mov     rbx, rax                ; ns totales
        xor     edx, edx
        mov     rcx, 2*ROUNDS           ; mensajes en total
        div     rcx
        mov     rcx, rax                ; ns por mensaje
        mov     rax, rbx
        xor     edx, edx
        mov     r8d, 1000000
        div     r8
        mov     rdx, rax                ; ms
        lea     rdi, [f_b]
        mov     esi, ROUNDS
        xor     eax, eax
        call    printf
        pop     rdi
        pop     rdi
        mov     eax, SYS_WAIT4
        xor     esi, esi
        xor     edx, edx
        xor     r10, r10
        syscall

        add     rsp, 16
        pop     rbx
        xor     eax, eax
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

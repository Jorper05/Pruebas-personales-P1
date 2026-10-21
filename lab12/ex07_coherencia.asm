; =====================================================================
; ex07_coherencia.asm - El costo del protocolo de coherencia (MESI)
;
;   Dos hilos incrementan N veces cada uno un contador en memoria.
;   <disposición>:
;     0 : contadores DISTINTOS en la MISMA línea de caché (8 B de
;         separación)  -> "falso compartimiento" (false sharing):
;         cada escritura invalida la copia del otro núcleo y la
;         línea rebota M -> I -> M entre las cachés.
;     1 : contadores en líneas DISTINTAS (128 B de separación)
;         -> cada línea queda en estado M en su núcleo; sin tráfico.
;     2 : el MISMO contador (compartimiento verdadero).
;     3 : un solo hilo hace 2N incrementos (referencia uniprocesador).
;   <atómico>:
;     0 : ADD [mem],1        (load+add+store, NO atómico entre núcleos)
;     1 : LOCK ADD [mem],1   (read-modify-write atómico: exige la línea
;                             en estado M y vacía el store buffer)
;
;   Uso: ./ex07_coherencia <disposición> <atómico>
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex07_coherencia.asm
;     gcc -no-pie ex07_coherencia.o -o ex07_coherencia -lpthread
; =====================================================================
default rel
extern printf, atoi, pthread_create, pthread_join
global main, incrementa, incrementa_lock

N       equ 50000000

section .data
usage   db "uso: %s <disp 0=misma linea 1=lineas distintas 2=mismo contador 3=un hilo> <atomico 0|1>", 10, 0
f_res   db "disp=%ld atomico=%ld  tiempo=%7.1f ms   c[0]=%-10ld c[1]=%-10ld (&c0=%p, &c1=%p)", 10, 0
align 8
ms_div  dq 1000000.0

section .bss
mode    resq 1
atom    resq 1
alignb 64
area    resb 256                ; aquí viven los contadores
pc0     resq 1                  ; dirección del contador del hilo 0
pc1     resq 1                  ; dirección del contador del hilo 1
th0     resq 1
th1     resq 1
iter    resq 1

%include "sync.inc"

section .text
; void *incrementa(uint64_t *c) : N veces  c++  (load + add + store)
incrementa:
        mov     rcx, [iter]
.l:     add     qword [rdi], 1          ; escribe -> necesita la línea en estado M
        dec     rcx
        jnz     .l
        xor     eax, eax
        ret

; void *incrementa_lock(uint64_t *c) : N veces  lock c++
incrementa_lock:
        mov     rcx, [iter]
.l:     lock add qword [rdi], 1         ; RMW atómico
        dec     rcx
        jnz     .l
        xor     eax, eax
        ret

main:
        push    rbx
        push    r12
        push    r13                     ; alineada
        cmp     edi, 3
        jge     .ok
        lea     rdi, [usage]
        mov     rsi, [rsi]
        xor     eax, eax
        call    printf
        mov     eax, 1
        jmp     .ret
.ok:
        mov     rbx, rsi
        mov     rdi, [rbx+8]
        call    atoi
        mov     [mode], rax
        mov     rdi, [rbx+16]
        call    atoi
        mov     [atom], rax
        mov     qword [iter], N
        lea     rax, [area]
        mov     [pc0], rax
        lea     rdx, [rax+8]            ; modo 0: misma línea
        mov     rcx, [mode]
        cmp     rcx, 1
        jne     .m2
        lea     rdx, [rax+128]          ; modo 1: otra línea
.m2:    cmp     rcx, 2
        jne     .m3
        mov     rdx, rax                ; modo 2: el mismo contador
.m3:    mov     [pc1], rdx

        lea     rbx, [incrementa]       ; rbx = rutina a usar
        cmp     qword [atom], 0
        je      .sel
        lea     rbx, [incrementa_lock]
.sel:
        call    now_ns
        mov     r12, rax
        cmp     qword [mode], 3
        jne     .dos_hilos
        mov     qword [iter], 2*N       ; modo 3: un hilo, todo el trabajo
        mov     rdi, [pc0]
        call    rbx
        jmp     .medir
.dos_hilos:
        lea     rdi, [th0]
        xor     esi, esi
        mov     rdx, rbx
        mov     rcx, [pc0]
        call    pthread_create
        lea     rdi, [th1]
        xor     esi, esi
        mov     rdx, rbx
        mov     rcx, [pc1]
        call    pthread_create
        mov     rdi, [th0]
        xor     esi, esi
        call    pthread_join
        mov     rdi, [th1]
        xor     esi, esi
        call    pthread_join
.medir:
        call    now_ns
        sub     rax, r12
        cvtsi2sd xmm0, rax
        divsd   xmm0, [ms_div]
        sub     rsp, 16                 ; 7º argumento (entero) en la pila
        mov     rax, [pc1]
        mov     [rsp], rax
        lea     rdi, [f_res]
        mov     rsi, [mode]
        mov     rdx, [atom]
        mov     rax, [pc0]
        mov     rcx, [rax]
        mov     rax, [pc1]
        mov     r8, [rax]
        mov     r9, [pc0]
        mov     eax, 1
        call    printf
        add     rsp, 16
        xor     eax, eax
.ret:
        pop     r13
        pop     r12
        pop     rbx
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

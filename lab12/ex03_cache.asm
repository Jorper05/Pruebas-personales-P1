; =====================================================================
; ex03_cache.asm - Latencia de memoria vs. tamaño de datos, y speedup
;                  superlineal por aumento de caché total
;
;   Se reserva un arreglo de TAM KB formado por nodos de 64 bytes (una
;   línea de caché cada uno). El arreglo se divide en T porciones; en cada
;   porción los nodos se enlazan en un ciclo aleatorio (algoritmo de
;   Sattolo) para derrotar al prefetcher. Cada hilo recorre ("persigue
;   punteros") SU porción. El total de accesos es fijo (2^25) y se reparte
;   entre los T hilos, así que el trabajo total es el mismo para cualquier T.
;
;   Uso:   ./ex03_cache <tam_KB> <hilos>
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex03_cache.asm
;     gcc -no-pie ex03_cache.o -o ex03_cache -lpthread
; =====================================================================
default rel
extern printf, atoi, aligned_alloc, malloc, free
extern pthread_create, pthread_join
global main, chaser

ACCESSES equ 1 << 25            ; accesos totales (todos los hilos)
MAXT     equ 64

section .data
usage   db "uso: %s <tam_KB> <hilos>", 10, 0
fmt     db "tam=%7ld KB  hilos=%2ld  KB/hilo=%7ld  tiempo=%8.1f ms  latencia=%6.2f ns/acceso", 10, 0
align 8
ms_div  dq 1000000.0

section .bss
nthreads resq 1
size_kb  resq 1
nodes    resq 1                 ; puntero al arreglo de nodos
perm     resq 1                 ; arreglo auxiliar para la permutación
rng      resq 1
alignb 64
start    resq MAXT              ; nodo inicial de cada hilo
tids     resq MAXT
alignb 64
sink     resq MAXT*8            ; resultado de cada hilo (líneas separadas)

%include "sync.inc"

section .text
; ---------------------------------------------------------------------
; xorshift64 -> rax
; ---------------------------------------------------------------------
rand64:
        mov     rax, [rng]
        mov     rdx, rax
        shl     rdx, 13
        xor     rax, rdx
        mov     rdx, rax
        shr     rdx, 7
        xor     rax, rdx
        mov     rdx, rax
        shl     rdx, 17
        xor     rax, rdx
        mov     [rng], rax
        ret

; ---------------------------------------------------------------------
; build_cycle(rdi = primer nodo (índice), rsi = n nodos)
;   Enlaza los nodos [first, first+n) en un único ciclo aleatorio.
; ---------------------------------------------------------------------
build_cycle:
        push    rbx
        push    r12
        push    r13
        mov     r12, rdi                ; first
        mov     r13, rsi                ; n
        mov     rbx, [perm]
        xor     ecx, ecx                ; perm[i] = first + i
.init:  cmp     rcx, r13
        jae     .shuffle
        lea     rax, [r12+rcx]
        mov     [rbx+rcx*8], rax
        inc     rcx
        jmp     .init
.shuffle:                               ; Sattolo: i = n-1 .. 1, j en [0, i)
        mov     rcx, r13
        dec     rcx
.s_loop:
        cmp     rcx, 1
        jl      .link
        push    rcx
        call    rand64
        pop     rcx
        xor     edx, edx
        div     rcx                     ; rdx = rand % i
        mov     rax, [rbx+rcx*8]        ; swap perm[i], perm[j]
        mov     r8,  [rbx+rdx*8]
        mov     [rbx+rcx*8], r8
        mov     [rbx+rdx*8], rax
        dec     rcx
        jmp     .s_loop
.link:                                  ; nodo[perm[i]].next = &nodo[perm[i+1]]
        mov     r9, [nodes]
        xor     ecx, ecx
.l_loop:
        cmp     rcx, r13
        jae     .done
        lea     rdx, [rcx+1]
        cmp     rdx, r13
        jb      .nowrap
        xor     edx, edx
.nowrap:
        mov     rax, [rbx+rcx*8]
        shl     rax, 6
        add     rax, r9                 ; dirección del nodo i
        mov     r8, [rbx+rdx*8]
        shl     r8, 6
        add     r8, r9                  ; dirección del siguiente
        mov     [rax], r8
        inc     rcx
        jmp     .l_loop
.done:
        mov     rax, [rbx]              ; nodo de inicio = perm[0]
        shl     rax, 6
        add     rax, r9
        pop     r13
        pop     r12
        pop     rbx
        ret

; ---------------------------------------------------------------------
; void *chaser(void *id) : recorre su ciclo ACCESSES/T veces
; ---------------------------------------------------------------------
chaser:
        lea     rax, [start]
        mov     rax, [rax+rdi*8]        ; p = start[id]
        push    rdi
        mov     rcx, ACCESSES
        xchg    rax, rcx
        xor     edx, edx
        div     qword [nthreads]        ; accesos por hilo
        xchg    rax, rcx
.hop:
        mov     rax, [rax]              ; p = p->next   (acceso dependiente)
        dec     rcx
        jnz     .hop
        pop     rdi
        shl     rdi, 6
        lea     rdx, [sink]
        mov     [rdx+rdi], rax          ; evita que el trabajo sea "inútil"
        xor     eax, eax
        ret

; ---------------------------------------------------------------------
main:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     rbx, rsi
        cmp     edi, 3
        jge     .ok
        lea     rdi, [usage]
        mov     rsi, [rbx]
        xor     eax, eax
        call    printf
        mov     eax, 1
        jmp     .ret
.ok:
        mov     rdi, [rbx+8]
        call    atoi
        mov     [size_kb], rax
        mov     rdi, [rbx+16]
        call    atoi
        cmp     eax, 1
        jge     .a
        mov     eax, 1
.a:     cmp     eax, MAXT
        jle     .b
        mov     eax, MAXT
.b:     mov     [nthreads], rax
        mov     rax, 88172645463325252  ; semilla del generador
        mov     [rng], rax

        mov     r12, [size_kb]
        shl     r12, 4                  ; nodos totales = KB*1024/64 = KB*16
        mov     edi, 64
        mov     rsi, r12
        shl     rsi, 6
        call    aligned_alloc           ; nodos alineados a línea de caché
        mov     [nodes], rax
        mov     rdi, r12
        shl     rdi, 3
        call    malloc
        mov     [perm], rax

        mov     rax, r12                ; nodos por hilo
        xor     edx, edx
        div     qword [nthreads]
        mov     r13, rax
        xor     r14, r14                ; i
.build:
        cmp     r14, [nthreads]
        jae     .run
        mov     rdi, r14
        imul    rdi, r13
        mov     rsi, r13
        call    build_cycle
        lea     rdx, [start]
        mov     [rdx+r14*8], rax
        inc     r14
        jmp     .build

.run:
        call    now_ns
        mov     r15, rax
        xor     r14, r14
.cr:    cmp     r14, [nthreads]
        jae     .jn0
        lea     rdi, [tids]
        lea     rdi, [rdi+r14*8]
        xor     esi, esi
        lea     rdx, [chaser]
        mov     rcx, r14
        call    pthread_create
        inc     r14
        jmp     .cr
.jn0:   xor     r14, r14
.jn:    cmp     r14, [nthreads]
        jae     .fin
        lea     rax, [tids]
        mov     rdi, [rax+r14*8]
        xor     esi, esi
        call    pthread_join
        inc     r14
        jmp     .jn
.fin:
        call    now_ns
        sub     rax, r15
        cvtsi2sd xmm0, rax              ; xmm0 = ms
        divsd   xmm0, [ms_div]
        ; latencia = ns * T / ACCESSES
        cvtsi2sd xmm1, rax
        cvtsi2sd xmm2, qword [nthreads]
        mulsd   xmm1, xmm2
        mov     rax, ACCESSES
        cvtsi2sd xmm2, rax
        divsd   xmm1, xmm2
        mov     rax, [size_kb]
        xor     edx, edx
        div     qword [nthreads]
        mov     rcx, rax                ; KB por hilo
        lea     rdi, [fmt]
        mov     rsi, [size_kb]
        mov     rdx, [nthreads]
        mov     eax, 2
        call    printf
        xor     eax, eax
.ret:
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

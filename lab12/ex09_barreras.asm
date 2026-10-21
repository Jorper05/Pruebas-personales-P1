; =====================================================================
; ex09_barreras.asm - Sincronización con BARRERAS
;
;   Modelo de una simulación por pasos de tiempo (como la del clima del
;   texto): en cada fase p, el hilo i "simula" (trabajo de duración
;   variable), publica su resultado estado[i] = p y luego lee los
;   resultados de TODOS los hilos para la fase siguiente.
;   Si algún vecino todavía no publicó la fase p (o ya publicó p+1),
;   el hilo usa un dato equivocado -> se cuenta un error.
;
;     modo 0 : sin barreras
;     modo 1 : barrera después de publicar y barrera después de leer
;
;   Uso: ./ex09_barreras <hilos> <fases> <modo>
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex09_barreras.asm
;     gcc -no-pie ex09_barreras.o -o ex09_barreras -lpthread
; =====================================================================
default rel
extern printf, atoi, pthread_create, pthread_join
global main, worker

MAXT    equ 64

section .data
usage   db "uso: %s <hilos> <fases> <modo 0=sin barrera 1=con barrera>", 10, 0
f_res   db "hilos=%ld fases=%ld modo=%ld  lecturas inconsistentes=%ld de %ld  tiempo=%.1f ms", 10, 0
align 8
ms_div  dq 1000000.0
align 64
barrera dq 0, 0, 0              ; contador, generación, n (se fija en main)
        times 5 dq 0

section .bss
nthreads resq 1
fases    resq 1
mode     resq 1
alignb 64
estado   resq 8*MAXT            ; estado[i] en la línea i (64 B c/u)
alignb 64
errores  resq 8*MAXT
tids     resq MAXT

%include "sync.inc"

section .text
; trabajo "de simulación" de longitud variable según el hilo y la fase
simula:                         ; rdi = id, rsi = fase
        lea     rcx, [rdi+rsi]
        and     rcx, 7
        inc     rcx
        imul    rcx, rcx, 2000
.l:     dec     rcx
        jnz     .l
        ret

worker:                         ; rdi = id
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        mov     r12, rdi                ; id
        xor     r13, r13                ; fase p
        xor     r14, r14                ; errores
.fase:
        cmp     r13, [fases]
        jae     .fin
        mov     rdi, r12
        mov     rsi, r13
        call    simula
        mov     rax, r12                ; estado[id] = p + 1 (publicar)
        shl     rax, 6
        lea     rdx, [estado]
        lea     rcx, [r13+1]
        mov     [rdx+rax], rcx
        cmp     qword [mode], 0
        je      .leer
        lea     rdi, [barrera]
        call    barrier_wait            ; BARRERA 1: todos publicaron
.leer:
        xor     r15, r15                ; j
        lea     rcx, [r13+1]            ; valor esperado
.chk:   cmp     r15, [nthreads]
        jae     .chk_fin
        mov     rax, r15
        shl     rax, 6
        lea     rdx, [estado]
        cmp     [rdx+rax], rcx
        je      .okv
        inc     r14                     ; lectura inconsistente
.okv:   inc     r15
        jmp     .chk
.chk_fin:
        cmp     qword [mode], 0
        je      .sig
        lea     rdi, [barrera]
        call    barrier_wait            ; BARRERA 2: todos leyeron
.sig:   inc     r13
        jmp     .fase
.fin:
        mov     rax, r12
        shl     rax, 6
        lea     rdx, [errores]
        mov     [rdx+rax], r14
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        xor     eax, eax
        ret

main:
        push    rbx
        push    r12
        push    r13
        mov     rbx, rsi
        cmp     edi, 4
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
        cmp     eax, 1
        jge     .a
        mov     eax, 1
.a:     cmp     eax, MAXT
        jle     .b
        mov     eax, MAXT
.b:     mov     [nthreads], rax
        mov     [barrera+16], rax
        mov     rdi, [rbx+16]
        call    atoi
        mov     [fases], rax
        mov     rdi, [rbx+24]
        call    atoi
        mov     [mode], rax

        call    now_ns
        mov     r13, rax
        xor     r12, r12
.cr:    cmp     r12, [nthreads]
        jae     .j0
        lea     rdi, [tids]
        lea     rdi, [rdi+r12*8]
        xor     esi, esi
        lea     rdx, [worker]
        mov     rcx, r12
        call    pthread_create
        inc     r12
        jmp     .cr
.j0:    xor     r12, r12
.j:     cmp     r12, [nthreads]
        jae     .fin
        lea     rax, [tids]
        mov     rdi, [rax+r12*8]
        xor     esi, esi
        call    pthread_join
        inc     r12
        jmp     .j
.fin:
        call    now_ns
        sub     rax, r13
        cvtsi2sd xmm0, rax
        divsd   xmm0, [ms_div]
        xor     r8, r8                  ; total de errores
        xor     r12, r12
.s:     cmp     r12, [nthreads]
        jae     .p
        mov     rax, r12
        shl     rax, 6
        lea     rdx, [errores]
        add     r8, [rdx+rax]
        inc     r12
        jmp     .s
.p:
        mov     r9, [nthreads]          ; lecturas totales = T*T*fases
        imul    r9, r9
        imul    r9, [fases]
        lea     rdi, [f_res]
        mov     rsi, [nthreads]
        mov     rdx, [fases]
        mov     rcx, [mode]
        mov     eax, 1
        call    printf
        xor     eax, eax
.ret:
        pop     r13
        pop     r12
        pop     rbx
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

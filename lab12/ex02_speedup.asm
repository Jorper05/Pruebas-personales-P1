; =====================================================================
; ex02_speedup.asm - Speedup y balance de carga con hilos POSIX
;
;   El programa tiene K = 64 tareas indivisibles. La tarea k cuesta
;   (k+1)*BASE iteraciones, es decir, las tareas tienen tamaños distintos
;   (como en el problema resuelto 12.5).  Se reparten entre T hilos:
;
;     modo 0 : reparto estático por BLOQUES   (tareas contiguas)
;     modo 1 : reparto estático CÍCLICO       (k = id, id+T, id+2T, ...)
;     modo 2 : reparto DINÁMICO               (cola compartida con LOCK XADD)
;
;   Uso:   ./ex02_speedup  <hilos 1..64>  <modo 0|1|2>
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex02_speedup.asm
;     gcc -no-pie ex02_speedup.o -o ex02_speedup -lpthread
; =====================================================================
default rel
extern printf, atoi, pthread_create, pthread_join
global main, worker, do_task

K       equ 64                  ; número de tareas
BASE    equ 600000              ; iteraciones de la tarea más pequeña
MAXT    equ 64

section .data
usage   db "uso: %s <hilos 1..64> <modo 0=bloques 1=ciclico 2=dinamico>", 10, 0
fmt_hdr db "hilos=%ld  modo=%ld  tiempo=%.1f ms  checksum=%016lx", 10, 0
fmt_thr db "  hilo %2ld: %2ld tareas, %10ld iteraciones, ocupado %.1f ms", 10, 0
align 8
ms_div  dq 1000000.0

section .bss
nthreads resq 1
mode     resq 1
alignb 64
next_task resq 8                ; contador compartido (su propia línea)
alignb 64
tids     resq MAXT
alignb 64
; Estadísticas por hilo, 64 bytes c/u para no compartir líneas de caché:
;   [+0] checksum  [+8] tareas  [+16] iteraciones  [+24] ns ocupado
stats    resb 64*MAXT

%include "sync.inc"

section .text
; ---------------------------------------------------------------------
; do_task: rdi = k   -> ejecuta (k+1)*BASE iteraciones de xorshift64
;           devuelve rax = estado final, rdx = iteraciones realizadas
; ---------------------------------------------------------------------
do_task:
        lea     rcx, [rdi+1]
        imul    rcx, rcx, BASE          ; iteraciones
        mov     rdx, rcx
        lea     rax, [rdi+1]            ; semilla determinista por tarea
.l:     mov     r8, rax                 ; x ^= x << 13
        shl     r8, 13
        xor     rax, r8
        mov     r8, rax                 ; x ^= x >> 7
        shr     r8, 7
        xor     rax, r8
        mov     r8, rax                 ; x ^= x << 17
        shl     r8, 17
        xor     rax, r8
        dec     rcx
        jnz     .l
        ret

; ---------------------------------------------------------------------
; void *worker(void *id)
; ---------------------------------------------------------------------
worker:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15                     ; pila alineada (5 pushes + ret)
        mov     r12, rdi                ; id
        xor     r13, r13                ; checksum local
        xor     r14, r14                ; tareas hechas
        xor     r15, r15                ; iteraciones hechas
        call    now_ns
        mov     rbx, rax                ; t_inicio

        mov     rax, [mode]
        cmp     rax, 1
        je      .ciclico
        cmp     rax, 2
        je      .dinamico

.bloques:                               ; [id*K/T , (id+1)*K/T)
        mov     rax, r12
        imul    rax, rax, K
        xor     edx, edx
        div     qword [nthreads]
        push    rax                     ; inicio (se guarda en la pila)
        lea     rax, [r12+1]
        imul    rax, rax, K
        xor     edx, edx
        div     qword [nthreads]
        push    rax                     ; fin
.b_loop:
        mov     rdi, [rsp+8]
        cmp     rdi, [rsp]
        jae     .b_end
        call    do_task
        add     r13, rax
        add     r15, rdx
        inc     r14
        inc     qword [rsp+8]
        jmp     .b_loop
.b_end:
        add     rsp, 16
        jmp     .fin

.ciclico:                               ; k = id, id+T, id+2T ...
        push    r12
        push    r12                     ; [rsp] = k actual (2 pushes: alineado)
.c_loop:
        mov     rdi, [rsp]
        cmp     rdi, K
        jae     .c_end
        call    do_task
        add     r13, rax
        add     r15, rdx
        inc     r14
        mov     rax, [nthreads]
        add     [rsp], rax
        jmp     .c_loop
.c_end:
        add     rsp, 16
        jmp     .fin

.dinamico:                              ; toma la siguiente tarea libre
        mov     eax, 1
        lock xadd [next_task], rax      ; rax = tarea asignada (atómico)
        cmp     rax, K
        jae     .fin
        mov     rdi, rax
        call    do_task
        add     r13, rax
        add     r15, rdx
        inc     r14
        jmp     .dinamico

.fin:
        call    now_ns
        sub     rax, rbx
        mov     rdi, r12
        shl     rdi, 6                  ; id * 64
        lea     rsi, [stats]
        add     rsi, rdi
        mov     [rsi], r13
        mov     [rsi+8], r14
        mov     [rsi+16], r15
        mov     [rsi+24], rax
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        xor     eax, eax
        ret

; ---------------------------------------------------------------------
main:
        push    rbx
        push    r12
        push    r13
        push    r14                     ; 4 pushes + ret = 40 -> desalineada
        sub     rsp, 8                  ; ... ahora alineada
        mov     rbx, rsi                ; argv
        cmp     edi, 3
        jge     .args_ok
        lea     rdi, [usage]
        mov     rsi, [rbx]
        xor     eax, eax
        call    printf
        mov     eax, 1
        jmp     .ret
.args_ok:
        mov     rdi, [rbx+8]
        call    atoi
        cmp     eax, 1
        jge     .t1
        mov     eax, 1
.t1:    cmp     eax, MAXT
        jle     .t2
        mov     eax, MAXT
.t2:    mov     [nthreads], rax
        mov     rdi, [rbx+16]
        call    atoi
        mov     [mode], rax

        call    now_ns
        mov     r14, rax                ; t0

        xor     r12, r12                ; crear T hilos
.create:
        cmp     r12, [nthreads]
        jae     .join_init
        lea     rdi, [tids]
        lea     rdi, [rdi + r12*8]      ; &tids[i]
        xor     esi, esi                ; atributos por defecto
        lea     rdx, [worker]
        mov     rcx, r12                ; argumento = id
        call    pthread_create
        inc     r12
        jmp     .create
.join_init:
        xor     r12, r12
.join:
        cmp     r12, [nthreads]
        jae     .joined
        lea     rax, [tids]
        mov     rdi, [rax + r12*8]
        xor     esi, esi
        call    pthread_join            ; sincronización final ("barrera")
        inc     r12
        jmp     .join
.joined:
        call    now_ns
        sub     rax, r14                ; tiempo total (ns)

        ; checksum global = suma de los checksums parciales
        xor     r13, r13
        xor     r12, r12
        lea     rcx, [stats]
.sum:   cmp     r12, [nthreads]
        jae     .print
        mov     rdx, r12
        shl     rdx, 6
        add     r13, [rcx+rdx]
        inc     r12
        jmp     .sum
.print:
        cvtsi2sd xmm0, rax
        divsd   xmm0, [ms_div]
        lea     rdi, [fmt_hdr]
        mov     rsi, [nthreads]
        mov     rdx, [mode]
        mov     rcx, r13
        mov     eax, 1                  ; 1 argumento en registro XMM
        call    printf

        xor     r12, r12
.pthr:  cmp     r12, [nthreads]
        jae     .done
        mov     rax, r12
        shl     rax, 6
        lea     r13, [stats]
        add     r13, rax
        cvtsi2sd xmm0, qword [r13+24]
        divsd   xmm0, [ms_div]
        lea     rdi, [fmt_thr]
        mov     rsi, r12
        mov     rdx, [r13+8]
        mov     rcx, [r13+16]
        mov     eax, 1
        call    printf
        inc     r12
        jmp     .pthr
.done:
        xor     eax, eax
.ret:
        add     rsp, 8
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

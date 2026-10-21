; =====================================================================
; ex08_candados.asm - Sincronización con CANDADOS (locks)
;
;   T hilos incrementan un contador compartido N veces cada uno.
;     modo 0 : sin sincronización  (mov rax,[c] / inc / mov [c],rax)
;              -> condición de carrera: se pierden actualizaciones
;     modo 1 : instrucción atómica  LOCK INC [c]
;     modo 2 : candado de espera activa (spin lock) con XCHG que protege
;              una sección crítica NO atómica
;
;   Uso: ./ex08_candados <hilos> <modo>
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex08_candados.asm
;     gcc -no-pie ex08_candados.o -o ex08_candados -lpthread
; =====================================================================
default rel
extern printf, atoi, pthread_create, pthread_join
global main, worker, seccion_critica

N       equ 1000000
MAXT    equ 64

section .data
usage   db "uso: %s <hilos> <modo 0=sin sincronizacion 1=lock inc 2=spinlock>", 10, 0
f_res   db "hilos=%ld modo=%ld  esperado=%ld  obtenido=%ld  perdidos=%ld  tiempo=%.1f ms", 10, 0
align 8
ms_div  dq 1000000.0

section .bss
nthreads resq 1
mode     resq 1
alignb 64
contador resq 8                 ; variable compartida (su propia línea)
alignb 64
candado  resq 8                 ; 0 = libre, 1 = tomado (su propia línea)
tids     resq MAXT

%include "sync.inc"

section .text
worker:
        push    rbx
        mov     rbx, N
        mov     rax, [mode]
        cmp     rax, 1
        je      w_atomico
        cmp     rax, 2
        je      w_spin

w_carrera:                               ; ---- modo 0 ----
        mov     rax, [contador]         ; 1) leer
        inc     rax                     ; 2) modificar
        mov     [contador], rax         ; 3) escribir  (otro hilo pudo escribir entre 1 y 3)
        dec     rbx
        jnz     w_carrera
        jmp     w_fin

w_atomico:                               ; ---- modo 1 ----
        lock inc qword [contador]       ; RMW indivisible
        dec     rbx
        jnz     w_atomico
        jmp     w_fin

w_spin:                                  ; ---- modo 2 ----
        lea     rdi, [candado]
        call    spin_lock               ; LOCK
seccion_critica:                        ; (etiqueta global para GDB)
        mov     rax, [contador]
        inc     rax
        mov     [contador], rax
        lea     rdi, [candado]
        call    spin_unlock             ; UNLOCK
        dec     rbx
        jnz     w_spin
w_fin:
        pop     rbx
        xor     eax, eax
        ret

main:
        push    rbx
        push    r12
        push    r13
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
        cmp     eax, 1
        jge     .a
        mov     eax, 1
.a:     cmp     eax, MAXT
        jle     .b
        mov     eax, MAXT
.b:     mov     [nthreads], rax
        mov     rdi, [rbx+16]
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
        mov     rdx, [nthreads]
        imul    rdx, rdx, N             ; esperado
        mov     rcx, [contador]         ; obtenido
        mov     r8, rdx
        sub     r8, rcx                 ; perdidos
        lea     rdi, [f_res]
        mov     rsi, [nthreads]
        mov     r9, rcx
        mov     rcx, rdx
        mov     rdx, [mode]
        mov     eax, 1
        ; printf(fmt, hilos, modo, esperado, obtenido, perdidos, ms)
        xchg    r8, r9                  ; r8 = obtenido, r9 = perdidos
        call    printf
        xor     eax, eax
.ret:
        pop     r13
        pop     r12
        pop     rbx
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

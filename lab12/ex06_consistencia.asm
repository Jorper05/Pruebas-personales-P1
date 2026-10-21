; =====================================================================
; ex06_consistencia.asm - ¿Ofrece x86 consistencia FUERTE (secuencial)?
;
;   Prueba de tornasol "Store Buffering" (algoritmo de Dekker):
;        inicialmente x = y = 0
;        Hilo 0:  x = 1 ;  r1 = y          Hilo 1:  y = 1 ;  r2 = x
;
;   Bajo consistencia fuerte existe un orden secuencial global de las
;   cuatro operaciones; en cualquier intercalado alguno de los stores
;   precede a ambos loads, por lo que (r1,r2) = (0,0) es IMPOSIBLE.
;   x86-64 implementa TSO (Total Store Order), un modelo relajado: cada
;   núcleo tiene un "store buffer" y un load puede adelantarse a un store
;   anterior a otra dirección  ->  (0,0) SÍ puede ocurrir.
;
;   Uso:  ./ex06_consistencia <iteraciones> <modo>
;      modo 0 : sin barrera
;      modo 1 : MFENCE entre el store y el load
;      modo 2 : store con XCHG (LOCK implícito = barrera completa)
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex06_consistencia.asm
;     gcc -no-pie ex06_consistencia.o -o ex06_consistencia -lpthread
; =====================================================================
default rel
extern printf, atoi, pthread_create, pthread_join
global main, hilo0, hilo1

section .data
usage   db "uso: %s <iteraciones> <modo 0=nada 1=mfence 2=xchg>", 10, 0
f_res   db "modo=%ld  iteraciones=%ld", 10
        db "  (r1,r2)=(0,0): %9ld   <-- prohibido con consistencia fuerte", 10
        db "  (r1,r2)=(0,1): %9ld", 10
        db "  (r1,r2)=(1,0): %9ld", 10
        db "  (r1,r2)=(1,1): %9ld", 10, 0
align 64
barrera dq 0, 0, 2              ; contador, generación, 2 hilos
        times 5 dq 0

section .bss
iters   resq 1
mode    resq 1
alignb 64
x       resq 8                  ; cada variable en su propia línea de caché
y       resq 8
r1      resq 8
r2      resq 8
cuenta  resq 4                  ; histograma de resultados
t0      resq 1
t1      resq 1

%include "sync.inc"

section .text
; ---------------- Hilo 0: x = 1 ; r1 = y ----------------
hilo0:
        push    rbx
        mov     rbx, [iters]
.it:
        lea     rdi, [barrera]
        call    barrier_wait            ; ambos hilos arrancan "a la vez"
        mov     rcx, [mode]
        cmp     rcx, 2
        je      .xchg
        mov     qword [x], 1            ; STORE x
        test    rcx, rcx
        jz      .ld
        mfence                          ; vacía el store buffer
        jmp     .ld
.xchg:  mov     eax, 1
        xchg    [x], rax                ; STORE atómico (barrera implícita)
.ld:    mov     rax, [y]                ; LOAD y
        mov     [r1], rax
        lea     rdi, [barrera]
        call    barrier_wait            ; ambos terminaron
        ; el hilo 0 anota el resultado y reinicia x, y
        mov     rax, [r1]
        shl     rax, 1
        or      rax, [r2]
        lea     rdx, [cuenta]
        inc     qword [rdx+rax*8]
        mov     qword [x], 0
        mov     qword [y], 0
        dec     rbx
        jnz     .it
        pop     rbx
        xor     eax, eax
        ret

; ---------------- Hilo 1: y = 1 ; r2 = x ----------------
hilo1:
        push    rbx
        mov     rbx, [iters]
.it:
        lea     rdi, [barrera]
        call    barrier_wait
        mov     rcx, [mode]
        cmp     rcx, 2
        je      .xchg
        mov     qword [y], 1            ; STORE y
        test    rcx, rcx
        jz      .ld
        mfence
        jmp     .ld
.xchg:  mov     eax, 1
        xchg    [y], rax
.ld:    mov     rax, [x]                ; LOAD x
        mov     [r2], rax
        lea     rdi, [barrera]
        call    barrier_wait
        dec     rbx
        jnz     .it
        pop     rbx
        xor     eax, eax
        ret

main:
        push    rbx
        mov     rbx, rsi
        cmp     edi, 3
        jge     .ok
        lea     rdi, [usage]
        mov     rsi, [rbx]
        xor     eax, eax
        call    printf
        mov     eax, 1
        pop     rbx
        ret
.ok:
        mov     rdi, [rbx+8]
        call    atoi
        mov     [iters], rax
        mov     rdi, [rbx+16]
        call    atoi
        mov     [mode], rax

        lea     rdi, [t0]
        xor     esi, esi
        lea     rdx, [hilo0]
        xor     ecx, ecx
        call    pthread_create
        lea     rdi, [t1]
        xor     esi, esi
        lea     rdx, [hilo1]
        xor     ecx, ecx
        call    pthread_create
        mov     rdi, [t0]
        xor     esi, esi
        call    pthread_join
        mov     rdi, [t1]
        xor     esi, esi
        call    pthread_join

        sub     rsp, 16                 ; 7º argumento va en la pila
        mov     rax, [cuenta+24]
        mov     [rsp], rax              ; (1,1)
        lea     rdi, [f_res]
        mov     rsi, [mode]
        mov     rdx, [iters]
        mov     rcx, [cuenta]           ; (0,0)
        mov     r8,  [cuenta+8]         ; (0,1)
        mov     r9,  [cuenta+16]        ; (1,0)
        xor     eax, eax
        call    printf
        add     rsp, 16
        pop     rbx
        xor     eax, eax
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

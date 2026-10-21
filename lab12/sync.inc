; =====================================================================
; sync.inc  -  Rutinas comunes del Laboratorio 12 (x86-64, System V ABI)
;   now_ns        : tiempo monotónico en nanosegundos  -> rax
;   spin_lock     : adquiere un candado (test-and-test-and-set con XCHG)
;   spin_unlock   : libera el candado
;   barrier_wait  : barrera centralizada con contador + generación
; =====================================================================
extern clock_gettime

section .text

; ---------------------------------------------------------------------
; uint64_t now_ns(void)
; ---------------------------------------------------------------------
now_ns:
        sub     rsp, 24                 ; 8 (ret) + 24 = 32 -> pila alineada a 16
        mov     edi, 1                  ; CLOCK_MONOTONIC
        mov     rsi, rsp                ; struct timespec en la pila
        call    clock_gettime
        mov     rax, [rsp]              ; tv_sec
        imul    rax, rax, 1000000000
        add     rax, [rsp+8]            ; + tv_nsec
        add     rsp, 24
        ret

; ---------------------------------------------------------------------
; void spin_lock(uint64_t *lock)        rdi = &lock   (0 = libre, 1 = ocupado)
;   XCHG con operando en memoria lleva LOCK implícito: es atómico y
;   además actúa como barrera completa de memoria (full fence).
; ---------------------------------------------------------------------
spin_lock:
.try:
        mov     eax, 1
        xchg    rax, [rdi]              ; test-and-set atómico
        test    rax, rax
        jz      .got                    ; estaba libre -> lo tenemos
        mov     edx, 4096               ; giros antes de ceder la CPU
.wait:
        pause                           ; pista al CPU: estamos en un spin-loop
        cmp     qword [rdi], 0          ; "test" solo lectura: la línea queda en S
        je      .try                    ; parece libre -> reintentar el XCHG
        dec     edx
        jnz     .wait
        mov     eax, 24                 ; sched_yield() por si hay más hilos que CPUs
        syscall
        jmp     .try
.got:
        ret

; ---------------------------------------------------------------------
; void spin_unlock(uint64_t *lock)
;   En x86 (TSO) un store simple tiene semántica "release": todas las
;   escrituras previas son visibles antes que esta.
; ---------------------------------------------------------------------
spin_unlock:
        mov     qword [rdi], 0
        ret

; ---------------------------------------------------------------------
; void barrier_wait(barrier_t *b)       rdi = &b
;   barrier_t: [0] contador de llegadas
;              [8] generación (cambia cuando todos llegaron)
;             [16] número de hilos participantes
; ---------------------------------------------------------------------
barrier_wait:
        mov     r8, [rdi+8]             ; generación actual (leer ANTES de llegar)
        mov     eax, 1
        lock xadd [rdi], rax            ; llegada atómica: rax = valor anterior
        inc     rax
        cmp     rax, [rdi+16]
        jne     .spin_init
        mov     qword [rdi], 0          ; último en llegar: reinicia contador
        inc     r8
        mov     [rdi+8], r8             ; ... y libera a todos (nueva generación)
        ret
.spin_init:
        mov     edx, 4096
.spin:
        pause
        cmp     [rdi+8], r8
        jne     .done                   ; la generación cambió: todos llegaron
        dec     edx
        jnz     .spin
        push    rdi
        push    r8
        mov     eax, 24                 ; sched_yield()
        syscall
        pop     r8
        pop     rdi
        jmp     .spin_init
.done:
        ret

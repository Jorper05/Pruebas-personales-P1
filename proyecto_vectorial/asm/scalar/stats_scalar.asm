; =============================================================
; stats_scalar.asm
; Version ESCALAR de los kernels de computo - Fase 2.
;
; Convencion de llamada: System V AMD64 ABI
;   enteros/punteros: rdi, rsi, rdx, rcx, r8, r9
;   flotantes:        xmm0, xmm1, xmm2, ...
;   retorno float:    xmm0
;   callee-saved:     rbx, rbp, r12-r15
;
; Todo el calculo se realiza en float32 y de forma escalar.
; =============================================================

    global sum_array
    global compute_stats
    global normalize_array

    section .text

; ---------------------------------------------------------------
; float sum_array(const float *arr, int n)
;
;   rdi = arr
;   esi = n
;   retorna la suma en xmm0
; ---------------------------------------------------------------
sum_array:
    xor     eax, eax
    xorps   xmm0, xmm0

.sum_loop:
    cmp     eax, esi
    jge     .sum_done

    movss   xmm1, [rdi + rax*4]
    addss   xmm0, xmm1

    inc     eax
    jmp     .sum_loop

.sum_done:
    ret


; ---------------------------------------------------------------
; void compute_stats(const float *arr, int n,
;                     float *mean, float *var,
;                     float *min, float *max)
;
;   rdi = arr
;   esi = n
;   rdx = mean*
;   rcx = var*
;   r8  = min*
;   r9  = max*
;
;   var = sum((x - mean)^2) / n
;         (varianza poblacional)
;
;   Caso n <= 0:
;       mean = 0
;       var  = 0
;       min  = 0
;       max  = 0
;
;   Primera pasada:
;       suma + minimo + maximo
;
;   Segunda pasada:
;       suma de (x - media)^2
; ---------------------------------------------------------------
compute_stats:

    ; Guardar registros callee-saved que utilizaremos.
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Guardar punteros.
    mov     r12, rdi          ; r12 = arr
    mov     r13, rdx          ; r13 = mean*
    mov     r14, rcx          ; r14 = var*
    mov     r15, r8           ; r15 = min*
    mov     rbx, r9           ; rbx = max*

    ; -----------------------------------------------------------
    ; Caso N <= 0
    ; -----------------------------------------------------------
    test    esi, esi
    jle     .stats_zero

    ; -----------------------------------------------------------
    ; Primera pasada:
    ; suma, minimo y maximo.
    ; -----------------------------------------------------------

    xor     eax, eax          ; i = 0
    xorps   xmm0, xmm0        ; suma = 0.0

    ; Inicializar min y max con arr[0].
    movss   xmm1, [r12]

    movaps  xmm2, xmm1        ; xmm2 = min
    movaps  xmm3, xmm1        ; xmm3 = max

.stats_loop1:

    cmp     eax, esi
    jge     .stats_pass1_done

    movss   xmm4, [r12 + rax*4]

    ; suma += x
    addss   xmm0, xmm4

    ; min = menor(min, x)
    minss   xmm2, xmm4

    ; max = mayor(max, x)
    maxss   xmm3, xmm4

    inc     eax
    jmp     .stats_loop1


.stats_pass1_done:

    ; -----------------------------------------------------------
    ; media = suma / N
    ; -----------------------------------------------------------

    cvtsi2ss xmm5, esi         ; xmm5 = float(N)

    movaps   xmm6, xmm0        ; xmm6 = suma
    divss    xmm6, xmm5        ; xmm6 = media

    movss    [r13], xmm6       ; guardar media
    movss    [r15], xmm2       ; guardar minimo
    movss    [rbx], xmm3       ; guardar maximo

    ; -----------------------------------------------------------
    ; Segunda pasada:
    ; suma((x - media)^2)
    ; -----------------------------------------------------------

    xor     eax, eax
    xorps   xmm0, xmm0        ; acumulador = 0

.stats_loop2:

    cmp     eax, esi
    jge     .stats_pass2_done

    movss   xmm1, [r12 + rax*4]

    ; x - media
    subss   xmm1, xmm6

    ; (x - media)^2
    mulss   xmm1, xmm1

    ; acumulador += diferencia^2
    addss   xmm0, xmm1

    inc     eax
    jmp     .stats_loop2


.stats_pass2_done:

    ; -----------------------------------------------------------
    ; varianza = suma_de_cuadrados / N
    ; -----------------------------------------------------------

    divss   xmm0, xmm5

    movss   [r14], xmm0       ; guardar varianza

    jmp     .stats_done


.stats_zero:

    ; -----------------------------------------------------------
    ; N <= 0:
    ; todos los resultados = 0.0
    ; -----------------------------------------------------------

    xorps   xmm0, xmm0

    movss   [r13], xmm0       ; mean = 0
    movss   [r14], xmm0       ; var  = 0
    movss   [r15], xmm0       ; min  = 0
    movss   [rbx], xmm0       ; max  = 0


.stats_done:

    ; Restaurar registros callee-saved.
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx

    ret


; ---------------------------------------------------------------
; void normalize_array(const float *in, float *out, int n,
;                       float mean, float stddev)
;
;   rdi  = in
;   rsi  = out
;   edx  = n
;   xmm0 = mean
;   xmm1 = stddev
;
;   out[i] = (in[i] - mean) / stddev
;
;   Caso stddev == 0:
;       out[i] = in[i]
;
;   Se utiliza procesamiento escalar:
;       movss
;       subss
;       divss
; ---------------------------------------------------------------
normalize_array:

    ; Guardar mean y stddev.
    ;
    ; XMM8-XMM15 son caller-saved en System V AMD64,
    ; por lo que podemos utilizarlos sin preservarlos.
    movaps  xmm8, xmm0         ; xmm8 = mean
    movaps  xmm9, xmm1         ; xmm9 = stddev

    ; -----------------------------------------------------------
    ; Caso N <= 0
    ; -----------------------------------------------------------

    test    edx, edx
    jle     .norm_done

    ; -----------------------------------------------------------
    ; Comprobar stddev == 0
    ; -----------------------------------------------------------

    xorps   xmm7, xmm7         ; xmm7 = 0.0

    ucomiss xmm9, xmm7
    je      .norm_copy

    ; -----------------------------------------------------------
    ; Normalizacion normal
    ; -----------------------------------------------------------

    xor     eax, eax           ; i = 0

.norm_loop:

    cmp     eax, edx
    jge     .norm_done

    ; x = in[i]
    movss   xmm2, [rdi + rax*4]

    ; x - mean
    subss   xmm2, xmm8

    ; (x - mean) / stddev
    divss   xmm2, xmm9

    ; out[i] = resultado
    movss   [rsi + rax*4], xmm2

    inc     eax
    jmp     .norm_loop


.norm_copy:

    ; -----------------------------------------------------------
    ; Caso stddev == 0:
    ; copiar entrada directamente a salida.
    ; -----------------------------------------------------------

    xor     eax, eax

.norm_copy_loop:

    cmp     eax, edx
    jge     .norm_done

    movss   xmm2, [rdi + rax*4]
    movss   [rsi + rax*4], xmm2

    inc     eax
    jmp     .norm_copy_loop


.norm_done:
    ret


; ---------------------------------------------------------------
; Indicar al linker que no se requiere una pila ejecutable.
; Esto elimina el warning:
; "missing .note.GNU-stack section"
; ---------------------------------------------------------------
section .note.GNU-stack noalloc noexec nowrite progbits

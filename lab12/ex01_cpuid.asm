; =====================================================================
; ex01_cpuid.asm - ¿Cuántos procesadores y qué cachés tiene mi máquina?
;   Usa la instrucción CPUID (hojas 0, 1 y 4) y sysconf().
;   Compilar:  nasm -f elf64 -g -F dwarf ex01_cpuid.asm
;              gcc -no-pie ex01_cpuid.o -o ex01_cpuid
; =====================================================================
default rel
extern printf, sysconf
global main

section .data
fmt_v   db "Fabricante (CPUID.0)                         : %s", 10, 0
fmt_l   db "Procesadores lógicos/paquete (CPUID.1 EBX[23:16]): %d", 10, 0
fmt_c   db "Tamaño de línea de caché (CPUID.1 EBX[15:8]*8)   : %d bytes", 10, 0
fmt_n   db "Procesadores en línea (sysconf)              : %ld", 10, 10, 0
fmt_h   db "Jerarquía de caché (CPUID.4):", 10, 0
fmt_k   db "  L%d %-13s %8d KB  línea=%d B  vías=%-3d compartida por <= %d CPU lógicas", 10, 0
s_data  db "datos", 0
s_inst  db "instrucciones", 0
s_unif  db "unificada", 0

section .bss
vendor  resb 16

section .text
main:
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15                     ; 5 pushes + ret = 48 -> alineada
        sub     rsp, 16                 ; espacio para el 7º argumento de printf

        ; ---- CPUID hoja 0: cadena del fabricante en EBX:EDX:ECX ----
        xor     eax, eax
        cpuid
        mov     [vendor], ebx
        mov     [vendor+4], edx
        mov     [vendor+8], ecx
        mov     byte [vendor+12], 0
        lea     rdi, [fmt_v]
        lea     rsi, [vendor]
        xor     eax, eax
        call    printf

        ; ---- CPUID hoja 1 ----
        mov     eax, 1
        cpuid
        mov     r12d, ebx
        mov     esi, r12d
        shr     esi, 16
        and     esi, 0xff               ; procesadores lógicos por paquete
        lea     rdi, [fmt_l]
        xor     eax, eax
        call    printf
        mov     esi, r12d
        shr     esi, 8
        and     esi, 0xff
        shl     esi, 3                  ; CLFLUSH line size * 8 = bytes
        lea     rdi, [fmt_c]
        xor     eax, eax
        call    printf

        ; ---- sysconf(_SC_NPROCESSORS_ONLN = 84) ----
        mov     edi, 84
        call    sysconf
        mov     rsi, rax
        lea     rdi, [fmt_n]
        xor     eax, eax
        call    printf

        lea     rdi, [fmt_h]
        xor     eax, eax
        call    printf

        ; ---- CPUID hoja 4: un sub-índice por cada caché (Intel) ----
        xor     r12d, r12d              ; sub-índice
.loop:
        mov     eax, 4
        mov     ecx, r12d
        cpuid
        mov     r13d, eax               ; guardar EAX
        and     eax, 0x1f               ; tipo: 0 = no hay más cachés
        jz      .end
        mov     r14d, eax               ; tipo
        ; tamaño = vías * particiones * línea * conjuntos
        mov     r15d, ebx
        shr     r15d, 22
        inc     r15d                    ; vías
        mov     eax, ebx
        shr     eax, 12
        and     eax, 0x3ff
        inc     eax                     ; particiones
        mov     r8d, ebx
        and     r8d, 0xfff
        inc     r8d                     ; tamaño de línea
        inc     ecx                     ; conjuntos
        imul    eax, r15d
        imul    eax, r8d
        imul    eax, ecx
        shr     eax, 10                 ; KB
        mov     ecx, eax                ; 4º arg: KB
        mov     r9d, r15d               ; 6º arg: vías
        mov     eax, r13d
        shr     eax, 14
        and     eax, 0xfff
        inc     eax
        mov     [rsp], rax              ; 7º arg (pila): CPUs que la comparten
        mov     esi, r13d
        shr     esi, 5
        and     esi, 7                  ; 2º arg: nivel
        lea     rdx, [s_data]
        cmp     r14d, 1
        je      .p
        lea     rdx, [s_inst]
        cmp     r14d, 2
        je      .p
        lea     rdx, [s_unif]
.p:
        lea     rdi, [fmt_k]
        xor     eax, eax
        call    printf
        inc     r12d
        jmp     .loop
.end:
        add     rsp, 16
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        xor     eax, eax
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

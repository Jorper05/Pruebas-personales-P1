; =====================================================================
; ex05_shm.asm - Memoria compartida: comunicación IMPLÍCITA
;
;   Parte A (procesos): tras fork(), una variable global normal queda
;   PRIVADA (cada proceso tiene su espacio de direcciones), pero una
;   región creada con mmap(MAP_SHARED) es un ÚNICO espacio visible para
;   ambos: lo que escribe P1 lo lee P0 sin SEND/RECEIVE.
;
;   Parte B (hilos): todos los hilos de un proceso comparten el espacio
;   de direcciones. Un hilo escribe un dato y levanta una bandera; el
;   hilo principal espera la bandera y lee el dato.
;
;   Compilar:
;     nasm -f elf64 -g -F dwarf ex05_shm.asm
;     gcc -no-pie ex05_shm.o -o ex05_shm -lpthread
; =====================================================================
default rel
extern printf, fflush, exit, pthread_create, pthread_join
global main, productor

SYS_MMAP  equ 9
SYS_FORK  equ 57
SYS_WAIT4 equ 61

section .data
privado dq 0
f_a     db "[P0] tras fork: privado=%ld (copia propia)   compartido=%ld (escrito por P1)", 10, 0
f_b     db "[main] bandera vista tras %ld giros: dato_hilos=%ld (escrito por otro hilo)", 10, 0

section .bss
compartido resq 1               ; puntero a la página MAP_SHARED
alignb 64
dato_hilos resq 8
alignb 64
bandera    resq 8
tid        resq 1

section .text
; hilo productor: escribe el dato y luego la bandera
productor:
        mov     qword [dato_hilos], 333 ; 1) dato
        mov     qword [bandera], 1      ; 2) bandera (x86 no reordena store-store)
        xor     eax, eax
        ret

main:
        push    rbx
        ; ---------------- PARTE A ----------------
        mov     eax, SYS_MMAP
        xor     edi, edi                ; addr = NULL
        mov     esi, 4096               ; una página
        mov     edx, 3                  ; PROT_READ | PROT_WRITE
        mov     r10d, 0x21              ; MAP_SHARED | MAP_ANONYMOUS
        mov     r8, -1                  ; fd = -1
        xor     r9d, r9d                ; offset = 0
        syscall
        mov     [compartido], rax
        mov     qword [rax], 0
        xor     edi, edi
        call    fflush
        mov     eax, SYS_FORK
        syscall
        test    rax, rax
        jnz     .padre
        ; ---- hijo P1 ----
        mov     qword [privado], 111    ; copy-on-write: solo su copia
        mov     rax, [compartido]
        mov     qword [rax], 222        ; misma página física que P0
        xor     edi, edi
        call    exit
.padre:
        mov     rdi, rax
        mov     eax, SYS_WAIT4          ; esperar a P1
        xor     esi, esi
        xor     edx, edx
        xor     r10, r10
        syscall
        lea     rdi, [f_a]
        mov     rsi, [privado]
        mov     rax, [compartido]
        mov     rdx, [rax]
        xor     eax, eax
        call    printf

        ; ---------------- PARTE B ----------------
        lea     rdi, [tid]
        xor     esi, esi
        lea     rdx, [productor]
        xor     ecx, ecx
        call    pthread_create
        xor     ebx, ebx                ; contador de giros
.espera:
        inc     rbx
        pause
        cmp     qword [bandera], 0      ; lectura de memoria compartida
        je      .espera
        mov     rdx, [dato_hilos]       ; x86 no reordena load-load
        lea     rdi, [f_b]
        mov     rsi, rbx
        xor     eax, eax
        call    printf
        mov     rdi, [tid]
        xor     esi, esi
        call    pthread_join
        pop     rbx
        xor     eax, eax
        ret
section .note.GNU-stack noalloc noexec nowrite progbits

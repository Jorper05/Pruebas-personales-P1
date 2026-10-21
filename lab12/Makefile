# Laboratorio 12 - Multiprocesadores (NASM x86-64 / Linux)
ASM    = nasm
AFLAGS = -f elf64 -g -F dwarf
LD     = gcc
LFLAGS = -no-pie
LIBS   = -lpthread

PROGS = ex01_cpuid ex02_speedup ex03_cache ex04_msgpass ex05_shm \
        ex06_consistencia ex07_coherencia ex08_candados ex09_barreras

all: $(PROGS)

%.o: %.asm sync.inc
	$(ASM) $(AFLAGS) $< -o $@

%: %.o
	$(LD) $(LFLAGS) $< -o $@ $(LIBS)

clean:
	rm -f *.o $(PROGS)

.PHONY: all clean
.SECONDARY:

/*
 * matmul.c
 * Multiplicador de matrices cuadradas N x N, usado como carga de trabajo
 * para la práctica de gem5 sobre arquitectura de memoria y caché.
 *
 * El tamaño N es configurable por línea de comandos para poder generar
 * distintos patrones de presión sobre la caché (matrices pequeñas caben
 * en L1/L2, matrices grandes fuerzan fallos de capacidad).
 *
 * Compilación estática (necesaria para el modo SE de gem5):
 *   gcc -O0 -static -o matmul matmul.c
 *
 * Uso:
 *   ./matmul <N>
 *   Si no se indica N, se usa un valor por defecto (64).
 *
 * Nota didáctica: se compila con -O0 a propósito, para que el compilador
 * NO reordene ni vectorice automáticamente los accesos a memoria. Esto
 * permite observar con mayor claridad el efecto de la localidad espacial
 * y temporal "cruda" del algoritmo, tal como se explica en la teoría.
 * Si se desea comparar el efecto de las optimizaciones del compilador,
 * se puede repetir el experimento con -O2 como ejercicio adicional.
 */

#include <stdio.h>
#include <stdlib.h>

#define DEFAULT_N 64

/* Multiplicación clásica ijk: C = A x B
 * Patrón de acceso: A por filas (buena localidad espacial),
 * B por columnas (mala localidad espacial -> más fallos de caché).
 * Este contraste es intencional para la práctica. */
static void matmul_ijk(int n, double *A, double *B, double *C) {
    int i, j, k;
    for (i = 0; i < n; i++) {
        for (j = 0; j < n; j++) {
            double sum = 0.0;
            for (k = 0; k < n; k++) {
                sum += A[i * n + k] * B[k * n + j];
            }
            C[i * n + j] = sum;
        }
    }
}

static void init_matrix(int n, double *M, unsigned int seed) {
    int i;
    unsigned int x = seed;
    for (i = 0; i < n * n; i++) {
        /* Generador simple para no depender de rand() con estado global */
        x = x * 1103515245u + 12345u;
        M[i] = (double)((x >> 16) % 100) / 7.0;
    }
}

static double checksum(int n, double *M) {
    int i;
    double s = 0.0;
    for (i = 0; i < n * n; i++) {
        s += M[i];
    }
    return s;
}

int main(int argc, char **argv) {
    int n = DEFAULT_N;

    if (argc > 1) {
        n = atoi(argv[1]);
        if (n <= 0) {
            fprintf(stderr, "N invalido, usando valor por defecto (%d)\n", DEFAULT_N);
            n = DEFAULT_N;
        }
    }

    double *A = (double *)malloc(sizeof(double) * n * n);
    double *B = (double *)malloc(sizeof(double) * n * n);
    double *C = (double *)malloc(sizeof(double) * n * n);

    if (!A || !B || !C) {
        fprintf(stderr, "Error de asignacion de memoria para N=%d\n", n);
        return 1;
    }

    init_matrix(n, A, 12345u);
    init_matrix(n, B, 6789u);

    matmul_ijk(n, A, B, C);

    /* Se imprime un checksum para verificar que el cómputo se realizó
     * y para evitar que el compilador elimine el cálculo por no usarse. */
    printf("N=%d checksum=%f\n", n, checksum(n, C));

    free(A);
    free(B);
    free(C);

    return 0;
}

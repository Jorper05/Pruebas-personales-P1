# Práctica de Laboratorio: Arquitectura de Memoria y Caché con gem5

**Curso:** Arquitectura de Computadoras
**Herramienta:** gem5 (simulador de arquitectura de computadoras)
**Duración estimada:** 3 - 4 horas
**Modalidad:** Individual o en parejas

---

## 1. Objetivos de aprendizaje

Al finalizar esta práctica, el estudiante será capaz de:

1. Instalar y ejecutar simulaciones básicas en gem5.
2. Configurar una jerarquía de memoria (L1 de instrucciones, L1 de datos, L2, memoria principal).
3. Modificar parámetros de caché (tamaño, asociatividad, tamaño de bloque, política de reemplazo) y observar su efecto.
4. Interpretar estadísticas de simulación (`stats.txt`): tasas de aciertos/fallos, tiempos de acceso, uso de ancho de banda.
5. Relacionar los resultados obtenidos con los conceptos teóricos de localidad espacial/temporal, principio de inclusión y trade-offs de diseño de caché.

---

## 2. Requisitos previos

- Conocimientos teóricos de: jerarquía de memoria, mapeo directo, asociativo por conjuntos, políticas de reemplazo (LRU, Random, FIFO), tiempo medio de acceso a memoria (AMAT).
- Sistema operativo Linux (nativo, WSL2 o máquina virtual) — gem5 no corre nativamente en Windows.
- Conocimientos básicos de terminal/bash y Python.
- Espacio en disco: al menos 10 GB libres.

---

## 3. Parte 1 — Instalación de gem5

### 3.1 Instalar dependencias

```bash
sudo apt update
sudo apt install -y build-essential git m4 scons zlib1g zlib1g-dev \
    libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
    python3-dev python3-pip doxygen libboost-all-dev libhdf5-serial-dev \
    python3-pydot libpng-dev libelf-dev pkg-config pip3 install mypy pillow six pydot
```

### 3.2 Clonar el repositorio

```bash
git clone https://github.com/gem5/gem5.git
cd gem5
```

### 3.3 Compilar (arquitectura X86, versión "opt")

```bash
scons build/X86/gem5.opt -j$(nproc)
```

> ⏱️ La compilación puede tardar entre 30 y 90 minutos según el equipo. Aprovecha este tiempo para repasar la teoría de jerarquía de memoria.

### 3.4 Verificar la instalación

```bash
./build/X86/gem5.opt --version
```

**Entregable 1:** captura de pantalla mostrando la versión de gem5 compilada exitosamente.

---

## 4. Parte 1.5 — Programa de carga de trabajo (multiplicador de matrices en C)

Para no depender solo de `hello` (que ejecuta muy pocas instrucciones y casi no genera fallos de caché interesantes), esta práctica incluye un programa propio de **multiplicación de matrices** (`matmul.c`), pensado específicamente para observar el efecto de la localidad espacial y temporal.

El archivo `matmul.c` ya está incluido junto con esta guía. Puntos clave de su diseño pedagógico:

- Implementa la multiplicación clásica de tres bucles anidados (`i, j, k`).
- Recorre la matriz `A` por filas (buena localidad espacial) y la matriz `B` por columnas (mala localidad espacial), lo cual genera un contraste claro y muy usado en cursos de arquitectura para introducir el tema de patrones de acceso a memoria.
- Recibe el tamaño `N` de la matriz como argumento de línea de comandos, lo que permite controlar cuánta presión se ejerce sobre la caché sin tocar el código fuente.
- Se compila con `-O0` deliberadamente, para que el compilador no reordene ni vectorice los accesos y el patrón de memoria observado en gem5 corresponda fielmente al código escrito.

### 4.1 Compilar el programa (estático, para modo SE de gem5)

gem5 en modo *System-Call Emulation* (SE) necesita un binario **estático**, ya que no hay un sistema operativo completo que resuelva las bibliotecas dinámicas:

```bash
gcc -O0 -static -o matmul matmul.c
```

Coloca el binario resultante dentro del árbol de gem5, por ejemplo:

```bash
mkdir -p tests/test-progs/matmul/bin/x86/linux
cp matmul tests/test-progs/matmul/bin/x86/linux/matmul
```

### 4.2 Probar el binario de forma nativa (fuera de gem5) antes de simular

Antes de correr algo en gem5 conviene confirmar que el programa funciona:

```bash
./matmul 64
# Salida esperada, similar a:
# N=64 checksum=123456.789012
```

Si esto falla o se cuelga, corrígelo antes de continuar — depurar dentro de gem5 es mucho más lento que depurar de forma nativa.

**Entregable 1.5:** captura de la ejecución nativa de `matmul` con al menos dos valores distintos de `N` (por ejemplo `32` y `256`) mostrando el checksum impreso.

---

## 5. Parte 2 — Primera simulación (modo System-Call Emulation)

gem5 incluye configuraciones de ejemplo en `configs/learning_gem5/`. Usaremos una de ellas como base y luego la modificaremos.

### 5.1 Crear el script de configuración base

Crea el archivo `configs/tutorial/simple_cache_config.py`:

```python
import m5
from m5.objects import *

# Sistema
system = System()
system.clk_domain = SrcClockDomain()
system.clk_domain.clock = '1GHz'
system.clk_domain.voltage_domain = VoltageDomain()

system.mem_mode = 'timing'
system.mem_ranges = [AddrRange('512MB')]

# CPU
system.cpu = TimingSimpleCPU()

# ---- Aquí se insertará la jerarquía de caché (Parte 3) ----

# Bus de memoria
system.membus = SystemXBar()

system.cpu.icache_port = system.membus.cpu_side_ports
system.cpu.dcache_port = system.membus.cpu_side_ports

system.cpu.createInterruptController()
system.cpu.interrupts[0].pio = system.membus.mem_side_ports
system.cpu.interrupts[0].int_requestor = system.membus.cpu_side_ports
system.cpu.interrupts[0].int_responder = system.membus.mem_side_ports

system.mem_ctrl = MemCtrl()
system.mem_ctrl.dram = DDR3_1600_8x8()
system.mem_ctrl.dram.range = system.mem_ranges[0]
system.mem_ctrl.port = system.membus.mem_side_ports

system.system_port = system.membus.cpu_side_ports

# Binario a ejecutar (multiplicador de matrices, ver Parte 1.5)
binary = 'tests/test-progs/matmul/bin/x86/linux/matmul'
system.workload = SEWorkload.init_compatible(binary)

process = Process()
# El segundo elemento es el argumento N (tamaño de la matriz).
# Empieza con un valor moderado; en la Parte 4 lo irás variando.
process.cmd = [binary, '128']
system.cpu.workload = process
system.cpu.createThreads()

root = Root(full_system=False, system=system)
m5.instantiate()

print("Iniciando la simulación")
exit_event = m5.simulate()
print(f"Simulación finalizada @ tick {m5.curTick()} por: {exit_event.getCause()}")
```

### 5.2 Ejecutar la simulación

```bash
./build/X86/gem5.opt configs/tutorial/simple_cache_config.py
```

### 5.3 Revisar resultados

gem5 genera una carpeta `m5out/` con:
- `stats.txt`: estadísticas numéricas de la simulación.
- `config.ini`: configuración efectiva del sistema simulado.

Abre `stats.txt` y busca las líneas relacionadas con `system.cpu.numCycles`, `sim_seconds` y `sim_insts`.

**Pregunta de análisis 1:** ¿Cuántos ciclos e instrucciones se ejecutaron? Calcula el IPC (instrucciones por ciclo) manualmente y compáralo con el reportado.

---

## 6. Parte 3 — Agregar una jerarquía de caché (L1 + L2)

### 6.1 Definir las clases de caché

Agrega esto **antes** de la sección del bus de memoria en tu script:

```python
class L1Cache(Cache):
    assoc = 2
    tag_latency = 2
    data_latency = 2
    response_latency = 2
    mshrs = 4
    tgts_per_mshr = 20

class L1ICache(L1Cache):
    size = '16kB'

class L1DCache(L1Cache):
    size = '64kB'

class L2Cache(Cache):
    size = '256kB'
    assoc = 8
    tag_latency = 20
    data_latency = 20
    response_latency = 20
    mshrs = 20
    tgts_per_mshr = 12
```

### 6.2 Conectar la caché al CPU y al bus

Reemplaza las líneas de conexión directa CPU–membus por:

```python
system.cpu.icache = L1ICache()
system.cpu.dcache = L1DCache()

system.cpu.icache.cpu_side = system.cpu.icache_port
system.cpu.dcache.cpu_side = system.cpu.dcache_port

system.l2bus = L2XBar()
system.cpu.icache.mem_side = system.l2bus.cpu_side_ports
system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports

system.l2cache = L2Cache()
system.l2cache.cpu_side = system.l2bus.mem_side_ports
system.l2cache.mem_side = system.membus.cpu_side_ports
```

> Nota: elimina las líneas anteriores `system.cpu.icache_port = system.membus.cpu_side_ports` y su equivalente de `dcache_port`, ya que ahora la caché se interpone entre el CPU y el bus.

### 6.3 Ejecutar de nuevo

```bash
./build/X86/gem5.opt configs/tutorial/simple_cache_config.py
```

### 6.4 Analizar `stats.txt`

Busca (y registra en una tabla) los siguientes campos para `icache`, `dcache` y `l2cache`:

| Métrica | icache | dcache | l2cache |
|---|---|---|---|
| `overallAccesses::total` | | | |
| `overallHits::total` | | | |
| `overallMisses::total` | | | |
| `overallMissRate::total` | | | |
| `overallAvgMissLatency::total` | | | |

**Entregable 2:** tabla completa + cálculo manual del AMAT (Average Memory Access Time) usando la fórmula:

```
AMAT = Hit_time_L1 + Miss_rate_L1 × (Hit_time_L2 + Miss_rate_L2 × Miss_penalty_memoria)
```

---

## 7. Parte 4 — Experimentos variando parámetros de caché

Ya cuentas con `matmul` como carga de trabajo (Parte 1.5). Recuerda que `process.cmd = [binary, 'N']` en el script de configuración controla el tamaño de la matriz — puedes cambiar ese valor sin recompilar nada, solo editando el script y volviendo a correr gem5.

Ejecuta **al menos 6 configuraciones distintas**, modificando un solo parámetro a la vez respecto a la configuración base (control: L1D de 64kB, 2 vías, N=128):

| # | Parámetro modificado | Valor base | Valor experimental |
|---|---|---|---|
| 1 | Tamaño L1D | 64kB | 8kB |
| 2 | Tamaño L1D | 64kB | 128kB |
| 3 | Asociatividad L1D | 2 vías | 8 vías (asociativa) |
| 4 | Asociatividad L1D | 2 vías | 1 vía (mapeo directo) |
| 5 | Tamaño de bloque (`cache_line_size` del sistema) | 64B | 32B / 128B |
| 6 | Tamaño de la carga de trabajo (`N` de `matmul`) | N=128 | N=32 y N=512 (dos corridas) |

> **Sobre el experimento 6:** con `N` pequeño (p. ej. 32), las tres matrices caben completas en L1D/L2, así que casi todos los accesos después del primer recorrido son aciertos. Con `N` grande (p. ej. 512), las matrices ya no caben en la caché y aparecen **fallos de capacidad** de forma mucho más marcada — este es el experimento más directo para "ver" en números el concepto de capacidad de caché visto en teoría. Ten en cuenta que N grande implica más tiempo de simulación.

Para cada experimento:

```bash
./build/X86/gem5.opt configs/tutorial/simple_cache_config.py
cp m5out/stats.txt resultados/stats_exp<N>.txt
```

### 7.1 Tabla comparativa final

Construye una tabla con: `miss_rate_L1D`, `IPC`, `sim_seconds`, `overallAvgMissLatency` para las 7 configuraciones (control + 6 experimentos).

**Preguntas de análisis 2:**

1. ¿Qué ocurrió con la tasa de fallos al reducir el tamaño de L1D a 8kB? Relaciónalo con el principio de localidad.
2. ¿La caché de mapeo directo (1 vía) tuvo más fallos por conflicto que la de 8 vías? Explica por qué, usando el concepto de "conflict miss".
3. ¿Cómo cambió el rendimiento (IPC) al modificar el tamaño de bloque? ¿Se relaciona con localidad espacial?
4. Compara la tasa de fallos entre N=32 y N=512 con la caché de control. ¿A partir de qué tamaño aproximado de matriz dejan de caber los datos en L1D? (Pista: calcula cuántos bytes ocupan las tres matrices para cada N y compáralo con el tamaño de la caché).
5. En términos de costo/beneficio (área de silicio vs. rendimiento), ¿qué configuración recomendarías y por qué?

---

## 8. Parte 5 — Política de reemplazo

Modifica la caché L1D para usar distintas políticas de reemplazo, comparando **LRU** (por defecto) contra **Random** y **FIFO**:

```python
from m5.objects import LRURP, RandomRP, FIFORP

class L1DCache(L1Cache):
    size = '64kB'
    replacement_policy = RandomRP()   # o LRURP() / FIFORP()
```

Ejecuta la simulación con cada política (manteniendo asociatividad de 4 u 8 vías, para que la política tenga margen de actuar) y registra `overallMissRate::total` de `dcache`.

**Pregunta de análisis 3:** ¿Con qué asociatividad la elección de política de reemplazo deja de tener impacto notable? ¿Por qué ocurre esto en una caché de mapeo directo?

---

## 9. Parte 6 (opcional / bono) — Visualización con `m5visual` o gráficas propias

Usa Python (`matplotlib`) para graficar, a partir de los `stats.txt` recolectados:

1. Miss rate vs. tamaño de caché (curva descendente esperada).
2. Miss rate vs. asociatividad.
3. IPC vs. cada una de las configuraciones anteriores.

```python
import matplotlib.pyplot as plt

tamanos = [8, 16, 32, 64, 128]     # kB
miss_rate = [0.18, 0.12, 0.07, 0.04, 0.03]  # ejemplo, reemplazar con tus datos

plt.plot(tamanos, miss_rate, marker='o')
plt.xlabel('Tamaño de caché L1D (kB)')
plt.ylabel('Tasa de fallos')
plt.title('Efecto del tamaño de caché en la tasa de fallos')
plt.grid(True)
plt.savefig('miss_rate_vs_size.png')
```

**Entregable 3 (bono):** las 3 gráficas + un párrafo de interpretación por gráfica.

---

## 10. Rúbrica sugerida

| Componente | Puntos |
|---|---|
| Compilación y prueba nativa de `matmul` (Entregable 1.5) | 5 |
| Instalación y ejecución exitosa de gem5 (Entregable 1) | 10 |
| Configuración correcta de jerarquía L1/L2 y tabla de estadísticas (Entregable 2) | 15 |
| Cálculo correcto del AMAT | 10 |
| Experimentos de la Parte 4 (6 configuraciones + tabla comparativa) | 25 |
| Respuestas a preguntas de análisis (1, 2 y 3) | 20 |
| Política de reemplazo (Parte 5) | 5 |
| Bono: gráficas e interpretación (Parte 6) | +10 |

---

## 11. Recomendaciones para el profesor

- Si el tiempo de laboratorio es limitado, se puede entregar a los estudiantes gem5 **ya compilado** (por ejemplo, en una imagen de máquina virtual o contenedor Docker) para saltar la Parte 1 y enfocar el tiempo en el análisis conceptual.
- Es útil pedir que registren el `config.ini` de cada corrida junto con el `stats.txt`, para verificar que efectivamente modificaron el parámetro correcto y no otro por error.
- Para grupos avanzados, se puede extender la práctica pidiendo comparar **caché inclusiva vs. no inclusiva** entre L1 y L2, o agregar un tercer nivel (L3) compartido entre múltiples núcleos usando `configs/example/se.py` con `--num-cpus`.

---

## 12. Referencias

- Documentación oficial de gem5: https://www.gem5.org/documentation/
- gem5 learning materials: `configs/learning_gem5/` dentro del repositorio.
- Hennessy, J. L. & Patterson, D. A. *Computer Architecture: A Quantitative Approach* (capítulo de jerarquía de memoria), para el marco teórico de AMAT y tipos de fallos (compulsory, capacity, conflict).

---

## 13. Archivos incluidos con esta práctica

| Archivo | Contenido |
|---|---|
| `practica_gem5_memoria_cache.md` | Esta guía. |
| `matmul.c` | Programa de multiplicación de matrices usado como carga de trabajo (ver Parte 1.5). |

El estudiante solo necesita copiar `matmul.c` a su entorno de trabajo, compilarlo según las instrucciones de la Parte 1.5 y seguir el resto de la guía sin necesidad de escribir código en C desde cero.

# Manual de Conceptos Fundamentales de gem5

**Material de apoyo teórico para la práctica de laboratorio**
**Curso:** Arquitectura de Computadoras

---

## Cómo usar este manual

Este documento **no reemplaza** la guía de laboratorio (`practica_gem5_memoria_cache.md`); la complementa. Mientras la guía te dice *qué comandos ejecutar*, este manual te explica *qué está pasando realmente por dentro* cuando los ejecutas. Se recomienda leerlo antes de iniciar la Parte 2 de la práctica, y volver a consultarlo cuando aparezca un término desconocido en `stats.txt` o en el script de configuración.

---

## 1. ¿Qué es gem5?

gem5 es un **simulador de arquitectura de computadoras a nivel de ciclo/evento**, usado tanto en investigación académica como en la industria para modelar y evaluar diseños de procesadores, jerarquías de memoria, sistemas de interconexión y dispositivos de entrada/salida **sin necesidad de construir hardware real**.

Es el resultado de la fusión de dos simuladores previos: **M5** (de la Universidad de Michigan, enfocado en simulación de sistema completo) y **GEMS** (de la Universidad de Wisconsin, enfocado en sistemas de memoria y coherencia de caché). De ahí el nombre: **g**EM**5**.

### 1.1 ¿Para qué se usa en la práctica?

En este laboratorio, gem5 nos permite:

- Ejecutar un programa real (nuestro `matmul.c` compilado) sobre un **procesador simulado**.
- Definir con precisión cada parámetro de la jerarquía de caché (tamaño, asociatividad, latencia, política de reemplazo) y observar el efecto exacto que tiene sobre el rendimiento, algo imposible de hacer con hardware físico sin comprar chips distintos.
- Obtener estadísticas exactas y reproducibles (tasas de fallos, ciclos, IPC) que en un procesador real requerirían contadores de hardware (`perf`, PMU) y no siempre son tan detallados ni configurables.

### 1.2 ¿Qué NO es gem5?

- No es un emulador de un procesador específico existente en el mercado (aunque puede modelar procesadores similares a ARM, x86, RISC-V, etc.).
- No ejecuta el programa "de verdad" en el sentido de que el binario corre sobre un intérprete/simulador funcional, no sobre silicio; por eso una simulación de segundos de "tiempo simulado" puede tardar minutos u horas de tiempo real en tu computadora.

---

## 2. Arquitectura interna de gem5

### 2.1 SimObjects: el bloque de construcción universal

Todo componente de un sistema simulado en gem5 —una CPU, una caché, un bus, un controlador de memoria, un disco— es una instancia de una clase Python llamada **SimObject**. Esto es clave para entender los scripts de configuración: cuando escribes

```python
system.cpu = TimingSimpleCPU()
system.l2cache = L2Cache()
```

no estás llamando funciones, estás **instanciando piezas de hardware simulado** que luego se conectan entre sí como si fueran componentes físicos con "cables" (ports).

Cada SimObject:
- Tiene **parámetros** configurables desde Python (tamaño, latencia, frecuencia, etc.).
- Puede tener **puertos** (`ports`) para conectarse a otros SimObjects.
- Está implementado internamente en **C++** por razones de rendimiento (la simulación de miles de millones de instrucciones debe ser rápida), pero se configura desde **Python**, que actúa como "pegamento" de alto nivel.

> **Por qué esto importa para el laboratorio:** cuando en la Parte 3 defines `class L1DCache(L1Cache): size = '64kB'`, estás usando herencia de clases de Python para crear una variante de una caché ya definida en gem5 (`Cache`), sobrescribiendo solo el parámetro que te interesa. Esto es programación orientada a objetos aplicada a configuración de hardware.

### 2.2 Simulación dirigida por eventos discretos

gem5 no simula "un ciclo de reloj a la vez" de forma ingenua. Usa una **cola de eventos** ordenada por tiempo: cada evento (por ejemplo, "la caché terminó de resolver un fallo", "el CPU puede buscar la siguiente instrucción") se programa para ocurrir en un **tick** futuro específico, y el simulador simplemente va sacando el evento más próximo de la cola y ejecutándolo. Esto es mucho más eficiente que evaluar todo el sistema en cada ciclo, especialmente cuando distintos componentes tienen distintas frecuencias de reloj.

### 2.3 Ticks: la unidad de tiempo de gem5

El **tick** es la unidad de tiempo interna de gem5, y por defecto **1 tick = 1 pico-segundo (10⁻¹² s)**. Todas las frecuencias de reloj que defines (`system.clk_domain.clock = '1GHz'`) se traducen internamente a ticks. Cuando ves en la consola:

```
Simulación finalizada @ tick 4823910000 por: ...
```

esa cifra es tiempo simulado, no tiempo real de ejecución de tu computadora. Para convertir a segundos simulados: `tiempo_segundos = ticks × 10⁻¹²`.

---

## 3. Modos de simulación

gem5 soporta dos modos de operación fundamentalmente distintos. La práctica de laboratorio usa el primero.

### 3.1 System-Call Emulation (SE mode)

- **No simula un sistema operativo completo.** El binario del usuario (en nuestro caso, `matmul`) se ejecuta directamente sobre el hardware simulado, y cuando el programa hace una llamada al sistema (`malloc`, `printf`, etc.), gem5 **intercepta esa llamada y la reenvía al sistema operativo anfitrión** (el Linux donde corre gem5), en lugar de simularla.
- Ventajas: arranca casi instantáneamente (no hay que "bootear" un SO simulado), es más simple de configurar, y es suficiente para estudiar CPU y jerarquía de memoria — que es exactamente nuestro objetivo en esta práctica.
- Limitaciones: no puede simular múltiples procesos con contexto de SO real, interrupciones de hardware complejas, drivers de dispositivos, ni el efecto del kernel sobre la caché (el kernel real también genera tráfico de memoria que aquí no se modela).
- Por eso el binario debe compilarse **estático** (`-static`): como no hay un SO simulado que resuelva bibliotecas dinámicas en tiempo de ejecución, todo el código necesario debe estar autocontenido en el ejecutable.

### 3.2 Full-System (FS mode)

- Simula una máquina completa, incluyendo **BIOS/firmware, arranque del kernel de Linux, dispositivos de E/S (disco, red, consola)**, sobre la cual corre un sistema operativo real sin modificaciones.
- Es indispensable para investigar temas que dependen del SO: manejo de interrupciones reales, drivers, multiprogramación con cambios de contexto reales, virtualización.
- Es mucho más lento de iniciar (hay que simular el proceso de arranque completo) y de configurar (requiere imágenes de disco, kernel compilado para simulación, etc.).
- **No se usa en esta práctica** porque el objetivo es aislar el comportamiento de CPU y caché sin el ruido adicional de un sistema operativo completo — SE mode es la elección pedagógicamente correcta aquí.

---

## 4. Modelos de CPU disponibles

gem5 no tiene "un" modelo de CPU: ofrece varios, cada uno con un balance distinto entre **precisión** y **velocidad de simulación**. Elegir el modelo correcto depende de qué se quiere estudiar.

| Modelo | Descripción | Uso típico |
|---|---|---|
| **AtomicSimpleCPU** | Ejecuta cada instrucción de forma "atómica": asume que toma un tiempo fijo y no modela contención real de recursos ni de memoria (los accesos a memoria "siempre aciertan" en términos de tiempo). | Simulaciones muy rápidas para calentar caché (*fast-forwarding*) o verificar funcionalidad, no para medir rendimiento. |
| **TimingSimpleCPU** | Modela correctamente los **tiempos de latencia** de acceso a memoria: si hay un fallo de caché, el CPU efectivamente espera. Sigue siendo un CPU *in-order* de una sola instrucción en vuelo a la vez (no hace superescalar ni fuera de orden). | **El que usamos en esta práctica.** Es el mínimo necesario para que las estadísticas de caché (hits, misses, latencias) tengan sentido real. |
| **MinorCPU** | Modela un pipeline **in-order** más realista, con etapas explícitas (fetch, decode, execute, etc.), similar a procesadores embebidos simples (piensa en un ARM Cortex-A serie pequeña). | Estudiar efectos de pipeline en procesadores simples. |
| **O3CPU (Out-of-Order)** | El modelo más detallado y más lento de simular: modela ejecución fuera de orden, ventana de instrucciones, unidades funcionales múltiples, predicción de saltos, etc. Similar en espíritu a procesadores de escritorio modernos. | Investigación de microarquitectura avanzada; **no es necesario para esta práctica** y ralentizaría mucho las simulaciones sin aportar información adicional sobre caché. |

> **Nota pedagógica:** en la práctica usamos `TimingSimpleCPU` precisamente porque es el modelo más simple que **sí refleja fielmente el comportamiento de la caché**. Usar `AtomicSimpleCPU` haría que todos los experimentos de la Parte 4 dieran resultados idénticos, porque ese modelo no distingue entre un acierto y un fallo en términos de tiempo.

---

## 5. El sistema de memoria clásico de gem5

gem5 ofrece dos sistemas de memoria distintos: el **sistema de memoria clásico** (Classic Memory System) y **Ruby** (un sistema más flexible orientado a modelar protocolos de coherencia de caché personalizados, usado en investigación de sistemas multinúcleo). **Esta práctica usa el sistema clásico**, que es más simple y suficiente para estudiar una jerarquía de caché convencional.

### 5.1 Componentes principales

```
CPU ── icache/dcache (L1) ── L2XBar ── L2 Cache ── SystemXBar (membus) ── MemCtrl ── DRAM
```

- **`Cache`**: el SimObject genérico de caché. Se configura con parámetros como `size`, `assoc`, `tag_latency`, `data_latency`, `response_latency`, `mshrs`, `tgts_per_mshr` y `replacement_policy` (ver sección 6).
- **`SystemXBar` / `L2XBar`**: los **"crossbars"** o buses de interconexión. Conectan múltiples puertos entre sí, permitiendo que, por ejemplo, tanto la caché de instrucciones como la de datos compartan el camino hacia L2.
- **`MemCtrl`**: el controlador de memoria principal, que modela la latencia y el ancho de banda de acceso a la DRAM.
- **`DDR3_1600_8x8`** (u otro modelo de DRAM): un modelo de temporización específico de un tipo de memoria DRAM real, con sus tiempos de fila/columna, refresco, etc.

### 5.2 Puertos (Ports): cómo se conectan los componentes

Cada SimObject de memoria tiene **puertos** de dos tipos:

- **`cpu_side` / `cpu_side_ports`**: el lado del componente que está "más cerca" del procesador (recibe peticiones).
- **`mem_side` / `mem_side_ports`**: el lado que está "más cerca" de la memoria principal (envía peticiones hacia adelante cuando hay un fallo).

Cuando en el script escribes:

```python
system.cpu.dcache.mem_side = system.l2bus.cpu_side_ports
```

estás literalmente diciendo: "el lado de memoria de la caché de datos se conecta al lado de CPU del bus L2" — es exactamente como conectar un cable entre dos componentes de hardware, solo que en Python.

### 5.3 ¿Qué pasa exactamente cuando el CPU accede a memoria?

1. El CPU emite una petición de lectura/escritura por su puerto `dcache_port`.
2. La caché L1D revisa si la dirección está presente (**hit**) o no (**miss**).
   - Si es **hit**: responde en `tag_latency + data_latency` (aproximadamente), sin involucrar a L2 ni a memoria.
   - Si es **miss**: reenvía la petición hacia L2 a través del `L2XBar`, y crea una entrada en su **MSHR** (Miss Status Holding Register) para recordar que esa petición está pendiente.
3. Si L2 tampoco tiene el dato (**miss en L2**), la petición sigue hacia el `MemCtrl` y finalmente hacia el modelo de DRAM.
4. La respuesta viaja de regreso por el mismo camino, instalando el bloque en cada nivel de caché por el que pasó (política *inclusiva* típica).

Este recorrido es exactamente lo que después se refleja en los contadores `overallHits`, `overallMisses` y `overallAvgMissLatency` de `stats.txt` para cada caché.

---

## 6. Parámetros de configuración de caché (glosario técnico)

Esta es la sección de referencia más importante para la Parte 3 y la Parte 4 de la práctica: aquí se explica **cada parámetro** que vas a modificar y qué representa físicamente.

| Parámetro | Significado | Efecto al aumentarlo |
|---|---|---|
| `size` | Capacidad total de la caché (ej. `'64kB'`). | Menos fallos de capacidad, pero más área de silicio y potencialmente mayor latencia de acceso en hardware real. |
| `assoc` | Número de "vías" (*ways*) por conjunto — cuántos bloques distintos pueden mapear al mismo índice sin desplazarse. `assoc=1` es mapeo directo; `assoc = size/block_size` sería totalmente asociativa. | Menos fallos por conflicto, pero mayor complejidad de hardware (más comparadores) y mayor consumo energético. |
| `tag_latency` | Ciclos necesarios para comparar la etiqueta (*tag*) de la dirección y determinar hit/miss. | Aumenta el tiempo de acceso incluso en un acierto. |
| `data_latency` | Ciclos necesarios para leer/escribir el dato una vez confirmado el acierto. | Aumenta el tiempo total de un hit. |
| `response_latency` | Ciclos adicionales para enviar la respuesta de vuelta al solicitante. | Aumenta la latencia total percibida por el nivel superior. |
| `mshrs` | Número de **Miss Status Holding Registers**: cuántos fallos distintos puede tener la caché "en vuelo" simultáneamente antes de bloquearse. | Más fallos pueden procesarse en paralelo (más *memory-level parallelism*), útil en cargas con muchos accesos concurrentes. |
| `tgts_per_mshr` | Cuántas peticiones distintas pueden "esperar" sobre el mismo MSHR (por ejemplo, dos instrucciones que piden la misma línea que ya está en camino). | Reduce bloqueos cuando varias peticiones coinciden en la misma línea de caché pendiente. |
| `replacement_policy` | Algoritmo para decidir qué bloque desalojar cuando un conjunto está lleno y llega un bloque nuevo (`LRURP`, `RandomRP`, `FIFORP`, etc.). | Cambia cuáles bloques sobreviven en caché; su impacto es mayor cuanto más asociativa es la caché (con `assoc=1` no hay nada que decidir). |
| `cache_line_size` (parámetro del **sistema**, no de la caché individual) | Tamaño del bloque de datos que se mueve como unidad entre niveles de memoria (típicamente 64 bytes en procesadores reales). | Bloques más grandes aprovechan mejor la localidad espacial (menos fallos si el programa accede a datos contiguos), pero desperdician más ancho de banda y espacio de caché si el programa NO tiene buena localidad espacial (*false sharing* de espacio). |

### 6.1 Tipos de fallos de caché (the 3 C's)

Este es un concepto teórico clásico que vas a poder **observar empíricamente** en los experimentos de la Parte 4:

- **Compulsory (obligatorio):** el bloque nunca ha sido traído a caché antes (primer acceso). Inevitable incluso con una caché infinita.
- **Capacity (capacidad):** el bloque fue desalojado porque la caché es demasiado pequeña para contener todo el conjunto de trabajo activo, aunque la asociatividad fuera infinita. Esto es lo que observas cuando reduces `size` o aumentas `N` en `matmul` (experimento 6 de la Parte 4).
- **Conflict (conflicto):** el bloque fue desalojado aunque *hubiera* espacio libre en otras partes de la caché, simplemente porque su conjunto específico está lleno y la asociatividad es insuficiente. Esto es lo que observas al comparar `assoc=1` contra `assoc=8` (experimentos 3 y 4).

`stats.txt` no siempre desglosa explícitamente estos tres tipos por nombre, pero **el diseño de tus experimentos** (variar un solo parámetro a la vez) es precisamente lo que te permite inferir cuál tipo de fallo domina en cada caso.

---

## 7. El sistema de estadísticas de gem5

### 7.1 ¿De dónde salen los números de `stats.txt`?

Cada SimObject en gem5 puede declarar internamente **contadores** (llamados *Stats* en el código fuente de C++) que se incrementan automáticamente durante la simulación cada vez que ocurre el evento correspondiente (un acierto, un fallo, una instrucción retirada, etc.). Al final de la simulación —o cuando se invoca `m5.stats.dump()`— gem5 vuelca todos estos contadores acumulados a `m5out/stats.txt` en formato de texto plano `nombre.completo.del.contador   valor   # descripción`.

### 7.2 Estadísticas clave para esta práctica

| Estadística | Qué mide |
|---|---|
| `sim_seconds` | Tiempo **simulado** total (no tiempo real de tu computadora). |
| `sim_insts` | Número total de instrucciones ejecutadas por el CPU. |
| `system.cpu.numCycles` | Número de ciclos de reloj del CPU simulado. |
| IPC (derivado, no aparece directo en versiones recientes) | `sim_insts / system.cpu.numCycles`. Instrucciones por ciclo: mide qué tan bien aprovechado está el CPU. |
| `<cache>.overallAccesses::total` | Total de accesos que recibió esa caché (hits + misses). |
| `<cache>.overallHits::total` | Accesos que encontraron el dato en esa caché. |
| `<cache>.overallMisses::total` | Accesos que **no** encontraron el dato y tuvieron que ir al siguiente nivel. |
| `<cache>.overallMissRate::total` | `overallMisses / overallAccesses`. La métrica central de esta práctica. |
| `<cache>.overallAvgMissLatency::total` | Tiempo promedio (en ticks) que tomó resolver un fallo, incluyendo el viaje hacia el siguiente nivel de memoria. |

### 7.3 ¿Por qué `config.ini` también importa?

`m5out/config.ini` registra la **configuración efectiva** con la que realmente corrió esa simulación (todos los parámetros de todos los SimObjects, incluyendo valores por defecto que quizás no escribiste explícitamente). Es la manera de **verificar** que un experimento realmente cambió el parámetro que creías haber cambiado, y no otro por error de copiar/pegar en el script — por eso se pide conservarlo junto a `stats.txt` en cada entrega.

---

## 8. Anatomía de un script de configuración en Python

Todo script de configuración de gem5 (como el de la práctica) sigue el mismo patrón general, independientemente de qué tan complejo sea el sistema simulado:

```python
import m5
from m5.objects import *

# 1) Declarar el sistema y su reloj/voltaje
system = System()
system.clk_domain = SrcClockDomain()
...

# 2) Declarar los SimObjects (CPU, cachés, buses, memoria)
system.cpu = TimingSimpleCPU()
system.cpu.icache = L1ICache()
...

# 3) Conectar los puertos entre SimObjects ("cablear" el sistema)
system.cpu.icache.cpu_side = system.cpu.icache_port
...

# 4) Definir la carga de trabajo (el binario a ejecutar)
process = Process()
process.cmd = [binary, 'argumento']
system.cpu.workload = process

# 5) Crear el nodo raíz e instanciar (construye el sistema en C++)
root = Root(full_system=False, system=system)
m5.instantiate()

# 6) Ejecutar la simulación
exit_event = m5.simulate()
```

Entender este flujo es lo que te permite, en la Parte 4 de la práctica, modificar con confianza **solo** el bloque 2 (los parámetros de la caché) o el bloque 4 (el argumento `N` del programa), sabiendo que el resto del "cableado" del sistema no necesita tocarse.

- **`m5.instantiate()`** es el paso donde Python termina de describir el sistema y gem5 lo **construye realmente en C++**, asignando memoria y preparando cada SimObject para ejecutar. Después de esta línea, ya no se pueden cambiar parámetros estructurales (como `size` de una caché).
- **`m5.simulate()`** es el que efectivamente avanza la cola de eventos discretos hasta que el programa termina (o hasta un límite de ticks, si se especifica uno).

---

## 9. Glosario rápido de términos usados en la práctica

| Término | Definición breve |
|---|---|
| **SimObject** | Clase base de cualquier componente simulado en gem5 (CPU, caché, bus, memoria, etc.). |
| **Tick** | Unidad de tiempo interna de gem5 (por defecto, 1 tick = 1 picosegundo). |
| **SE mode** | Modo de simulación sin sistema operativo simulado; las llamadas al sistema se reenvían al SO anfitrión. |
| **FS mode** | Modo de simulación de sistema completo, con SO real arrancando dentro de la simulación. |
| **AtomicSimpleCPU / TimingSimpleCPU / MinorCPU / O3CPU** | Distintos modelos de CPU con distinto balance entre precisión y velocidad de simulación. |
| **XBar (crossbar)** | Bus de interconexión que permite que múltiples puertos se comuniquen entre sí (ej. `SystemXBar`, `L2XBar`). |
| **MSHR** | Miss Status Holding Register: estructura que rastrea fallos de caché pendientes de resolver. |
| **Replacement Policy** | Algoritmo de reemplazo de bloques en una caché asociativa (`LRURP`, `RandomRP`, `FIFORP`). |
| **AMAT** | Average Memory Access Time: tiempo medio de acceso a memoria considerando toda la jerarquía. |
| **Compulsory / Capacity / Conflict miss** | Las "3 C's" que clasifican por qué ocurrió un fallo de caché. |
| **`stats.txt`** | Archivo de salida con todos los contadores acumulados de la simulación. |
| **`config.ini`** | Archivo de salida con la configuración efectiva (todos los parámetros reales) de la simulación. |
| **`m5.instantiate()`** | Paso que construye en C++ el sistema descrito en Python; después de esto no se pueden cambiar parámetros estructurales. |
| **`m5.simulate()`** | Paso que ejecuta la simulación avanzando la cola de eventos discretos. |

---

## 10. Preguntas de repaso (autoevaluación, no se entregan)

Antes de iniciar la Parte 3 de la práctica, verifica que puedes responder sin ayuda:

1. ¿Por qué el binario `matmul` debe compilarse con `-static` para usarse en modo SE?
2. ¿Qué diferencia concreta observarías en `stats.txt` si cambiaras `TimingSimpleCPU` por `AtomicSimpleCPU`, y por qué la práctica evita ese modelo?
3. Si `overallMissRate::total` de tu L1D es 0 en la caché de instrucciones pero 15% en la de datos, ¿qué te dice eso sobre el patrón de acceso del programa `matmul`?
4. ¿Qué diferencia hay entre un fallo de capacidad y uno de conflicto, y qué experimento de la Parte 4 aísla cada uno?
5. ¿Por qué `config.ini` es tan importante como `stats.txt` a la hora de reportar resultados?

---

## 11. Referencias

- Binkert, N. et al. (2011). *The gem5 Simulator*. ACM SIGARCH Computer Architecture News.
- Documentación oficial: https://www.gem5.org/documentation/
- Código fuente y definiciones de SimObjects: `src/mem/cache/Cache.py` y `src/cpu/` dentro del repositorio de gem5.
- Hennessy, J. L. & Patterson, D. A. *Computer Architecture: A Quantitative Approach*, capítulos de jerarquía de memoria (para el marco teórico de AMAT y las 3 C's de los fallos de caché).

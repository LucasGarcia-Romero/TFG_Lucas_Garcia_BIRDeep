# Sistema de grabación automática con Docker / Automatic Docker Recording System

Repositorio / Repository: `LucasGarcia-Romero/pruebas_grabadora`

---

## Español

### 1. Descripción general

Este proyecto implementa un sistema de grabación automática orientado a una Orange Pi o dispositivo Linux similar. El sistema está desplegado mediante Docker y separa las responsabilidades en varios servicios:

- `bird-recorder`: graba audio de forma automática y genera espectrogramas.
- `bird-stats`: registra estadísticas de temperatura y humedad.
- `bird-http-server`: expone una interfaz web y endpoints HTTP para configuración, consulta de ficheros, memoria, sensores y estado.
- `bird-recorder-watchdog`: vigila los contenedores principales y aplica reinicios controlados en caso de fallo.

El sistema guarda los datos persistentes en `/data`, incluyendo grabaciones WAV, espectrogramas PNG, históricos CSV, configuración, estado del recorder y estado del watchdog.

---

### 2. Arquitectura implementada

```text
pruebas_grabadora/
├── DHT22/                  # Código/binario para lectura del sensor DHT22
├── httpserver/             # Servidor HTTP C++ e interfaz web
│   ├── html/               # Páginas HTML, CSS, JS e imágenes
│   └── lib/                # Lógica de rutas, sistema, sesiones, sensores
├── recorder/               # Servicio de grabación automática
├── server/                 # Dockerfile/build del servidor HTTP
├── spectrogram/            # Generación de espectrogramas
├── stats/                  # Servicio de métricas de temperatura/humedad
├── watchdog/               # Servicio watchdog de contenedores Docker
├── docker-compose.yml      # Orquestación de servicios
├── generar_usuario         # Utilidad para credenciales
└── README_OrangePi_Docker.md
```

---

### 3. Servicios Docker

#### 3.1. `bird-recorder`

Servicio encargado de la grabación automática.

Funciones implementadas:

- Crea las carpetas persistentes:
  - `/data/recordings`
  - `/data/sdBackup`
- Crea/actualiza ficheros de estado:
  - `/data/stats.txt`
  - `/data/recorder_state.env`
  - log con nombre basado en la estación
- Lee configuración desde variables de entorno y desde `/data/config.txt`.
- Graba audio con `sox`.
- Usa timeout para evitar que una grabación quede colgada indefinidamente.
- Genera espectrograma tras cada WAV.
- Registra el estado de cada etapa:
  - `init`
  - `recording`
  - `spectrogram`
  - `sleeping`
- Reinicia el contenedor si falla la generación de espectrograma.
- Permite configurar duración, frecuencia de muestreo, bitrate, ganancia, identificador, GPIO, dispositivo de audio y pausa entre grabaciones.

Variables principales:

| Variable | Descripción | Valor por defecto / usado |
|---|---|---|
| `DATA_DIR` | Directorio persistente | `/data` |
| `STATION` | Prefijo de estación para ficheros | `TECHOUTAD_` |
| `BITRATE` | Bitrate de audio | `16` |
| `SAMPLE_RATE` | Frecuencia de muestreo | `32000` |
| `GAIN` | Ganancia | `5.0` |
| `DURATION` | Duración de cada grabación en segundos | `60` |
| `IDRECORDER` | Identificador de grabadora | `1` |
| `SLEEPDURATION` | Pausa entre grabaciones | `10` |
| `GPIO_PIN` | Pin GPIO usado | `117` |
| `AUDIO_DEVICE` | Dispositivo ALSA | `plughw:CARD=Microphone,DEV=0` |

---

#### 3.2. `bird-stats`

Servicio encargado del registro de métricas.

Funciones implementadas:

- Lee temperatura interna desde `/sys/class/thermal/thermal_zone0/temp`.
- Lee temperatura externa y humedad desde el binario DHT22.
- Escribe histórico en `/data/sensor_history.csv`.
- Mantiene cabecera CSV:

```csv
timestamp,internal_temp,external_temp,humidity
```

- Rota el CSV para limitar el número de líneas.
- Tolera fallos del DHT22 para que el resto de métricas continúe funcionando.
- Incluye healthcheck propio.

Variables principales:

| Variable | Descripción | Valor por defecto / usado |
|---|---|---|
| `DATA_DIR` | Directorio persistente | `/data` |
| `SLEEP_INTERVAL` | Intervalo entre lecturas | `60` en compose |
| `MAX_LINES` | Máximo de líneas conservadas | `130000` en compose |
| `STATS_MAX_AGE_SECONDS` | Antigüedad máxima esperada para healthcheck | `300` |

---

#### 3.3. `bird-http-server`

Servicio encargado de la interfaz web y API HTTP.

Funciones implementadas:

- Sirve la interfaz web del sistema.
- Sirve archivos persistentes desde `/data`.
- Expone rutas para:
  - login
  - listado de archivos
  - consulta y guardado de configuración
  - consulta de memoria
  - limpieza de estadísticas
  - limpieza de espectrogramas
  - limpieza de audios
  - configuración de limpieza automática
  - estado del watchdog
  - sensores
  - temperatura
- Expone el puerto `8000`.
- Monta `/data` para acceder a grabaciones, estadísticas y estado.
- Monta `/var/run/docker.sock` para poder reiniciar `bird-recorder` tras cambios de configuración.
- Incluye healthcheck propio.

---

#### 3.4. `bird-recorder-watchdog`

Servicio encargado de tolerancia a fallos Docker.

Funciones implementadas:

- Vigila los contenedores:
  - `bird-recorder`
  - `bird-stats`
  - `bird-http-server`
- Detecta contenedores:
  - inexistentes
  - detenidos
  - unhealthy
  - en arranque
  - sin healthcheck
- Reinicia contenedores fallidos.
- Aplica cooldown por contenedor para evitar reinicios agresivos.
- Mantiene historial de reinicios por ventana temporal.
- Activa backoff largo si un contenedor supera el máximo de reinicios permitido.
- Escribe estado JSON en `/data/watchdog_status.json`.
- Permite consultar el estado del watchdog desde la web/API.

Variables principales:

| Variable | Descripción | Valor usado |
|---|---|---|
| `WATCHDOG_CONTAINERS` | Contenedores monitorizados | `bird-recorder,bird-stats,bird-http-server` |
| `CHECK_INTERVAL` | Intervalo de revisión | `60` |
| `WATCHDOG_RESTART_COOLDOWN_SECONDS` | Cooldown normal | `300` |
| `WATCHDOG_FAILURE_WINDOW_SECONDS` | Ventana de fallos | `1800` |
| `WATCHDOG_MAX_RESTARTS_IN_WINDOW` | Máximo de reinicios en ventana | `3` |
| `WATCHDOG_LONG_COOLDOWN_SECONDS` | Backoff largo | `1800` |
| `WATCHDOG_STATUS_FILE` | Estado JSON | `/data/watchdog_status.json` |

---

### 4. Funcionalidades implementadas

#### 4.1. Estadísticas

Implementado.

El sistema registra estadísticas de temperatura interna, temperatura externa y humedad en `/data/sensor_history.csv`.

También existen rutas web/API para consultar valores recientes e históricos.

---

#### 4.2. Watchdog Docker incremental

Implementado.

El watchdog no solo reinicia contenedores fallidos, sino que aplica lógica incremental de protección:

1. Detecta fallo.
2. Comprueba cooldown normal.
3. Reinicia si procede.
4. Registra el reinicio en una ventana temporal.
5. Si hay demasiados reinicios, activa backoff largo.
6. Publica estado JSON para consulta.

---

#### 4.3. Limpieza de memoria

Implementado.

Existen acciones manuales para limpiar:

- estadísticas
- espectrogramas
- audios WAV

La lógica de limpieza se encuentra en el backend HTTP y actúa sobre `/data`.

---

#### 4.4. Limpieza de memoria cuando está lleno

Implementado con nota operativa.

El backend tiene limpieza automática configurable:

- Umbral de uso: `90%`
- Porcentaje eliminado: `20%`
- Tipos afectados:
  - WAV antiguos
  - PNG antiguos
  - filas antiguas del CSV de sensores

Nota: la limpieza automática se ejecuta al consultar el estado de memoria mediante la ruta correspondiente. No es un daemon independiente que corra cada minuto por sí solo.

---

#### 4.5. Bloque de grabación automática

Implementado.

El script de grabación funciona en bucle:

1. Carga configuración.
2. Prepara carpetas.
3. Activa GPIO si está disponible.
4. Genera nombre de archivo con timestamp.
5. Graba WAV con `sox`.
6. Genera espectrograma.
7. Registra temperatura de placa en logs.
8. Actualiza estado.
9. Espera `SLEEPDURATION`.
10. Repite el ciclo.

---

#### 4.6. Mostrar y filtrar grabaciones

Implementado.

La interfaz web permite listar grabaciones y filtrar por:

- nombre
- fecha desde
- fecha hasta
- extensión

El backend extrae timestamps del nombre de archivo y aplica filtros antes de devolver la lista.

---

#### 4.7. Rutas para audios y JSON de memoria

Implementado.

El servidor puede servir archivos desde `/data`, por lo que las grabaciones y espectrogramas quedan accesibles como recursos HTTP.

También existen endpoints para consultar memoria y limpieza.

---

### 5. Interfaz web

El directorio `httpserver/html` contiene la interfaz del sistema.

Páginas destacadas:

| Página | Función |
|---|---|
| `index.html` | Página principal |
| `login.html` | Acceso al sistema |
| `config.html` | Configuración del recorder |
| `recordings.html` | Visualización y filtrado de grabaciones |
| `memory.html` | Estado y limpieza de memoria |
| `status.html` | Estado de servicios |
| `temperature.html` | Visualización de sensores/temperatura |

---

### 6. Endpoints principales

#### 6.1. Endpoints POST registrados

| Endpoint / Clase | Función |
|---|---|
| `Login` | Autenticación |
| `ListFiles` | Listado de archivos y carpetas |
| `RecordData` | Escritura de datos |
| `GetConfig` | Obtener configuración |
| `SaveConfig` | Guardar configuración y reiniciar recorder |
| `MemoryStatus` | Estado de disco, conteo de WAV/PNG y limpieza automática |
| `ClearStats` | Limpiar estadísticas |
| `ClearSpectrograms` | Borrar espectrogramas PNG |
| `ClearAudios` | Borrar audios WAV |
| `GetAutoCleanup` | Consultar limpieza automática |
| `SaveAutoCleanup` | Activar/desactivar limpieza automática |

#### 6.2. Rutas de consulta y archivos

| Ruta | Método | Descripción |
|---|---|---|
| `/` | GET | Interfaz web |
| `/recordings/...` | GET | Acceso a WAV/PNG almacenados en `/data/recordings` |
| `/watchdog_status.json` | GET | Estado JSON generado por el watchdog |
| `/watchdog/status` | GET | Estado del watchdog |
| `/sensors/latest` | GET | Última lectura de sensores |
| `/sensors/history` | GET | Histórico de sensores |
| `/temperature` | GET | Temperatura actual |
| `/temperature/history` | GET | Histórico de temperatura |
| `/config` | GET/POST según implementación web | Configuración del recorder |

---

### 7. Archivos persistentes en `/data`

| Archivo / carpeta | Descripción |
|---|---|
| `/data/recordings` | Audios WAV y espectrogramas PNG |
| `/data/sdBackup` | Carpeta preparada para copias o backup |
| `/data/stats.txt` | Log simple de grabaciones/temperatura |
| `/data/sensor_history.csv` | Histórico de temperatura y humedad |
| `/data/config.txt` | Configuración editable del recorder |
| `/data/credentials.txt` | Credenciales para login |
| `/data/recorder_state.env` | Estado actual del recorder |
| `/data/watchdog_status.json` | Estado del watchdog |
| `/data/auto_cleanup.txt` | Configuración de limpieza automática |

---

### 8. Puesta en marcha

#### 8.1. Construir y arrancar

```bash
docker compose up -d --build
```

#### 8.2. Ver estado de contenedores

```bash
docker ps
```

#### 8.3. Ver logs

```bash
docker logs -f bird-recorder
docker logs -f bird-stats
docker logs -f bird-http-server
docker logs -f bird-recorder-watchdog
```

#### 8.4. Acceder a la web

```text
http://<IP_DE_LA_ORANGE_PI>:8000
```

---

### 9. Configuración

El sistema admite configuración mediante variables de entorno y mediante `/data/config.txt`.

Ejemplo de configuración:

```env
STATION=TECHOUTAD_
BITRATE=16
SAMPLE_RATE=32000
GAIN=5.0
DURATION=60
IDRECORDER=1
SLEEPDURATION=10
GPIO_PIN=117
AUDIO_DEVICE=plughw:CARD=Microphone,DEV=0
```

Cuando se guarda configuración desde la interfaz/API, el servidor reinicia el contenedor `bird-recorder` para aplicar cambios.

---

### 10. Healthchecks y tolerancia a fallos

Cada servicio principal incluye healthcheck o vigilancia:

- `bird-recorder`: comprueba que el proceso y la grabación funcionan correctamente.
- `bird-stats`: comprueba que las estadísticas se actualizan.
- `bird-http-server`: comprueba disponibilidad HTTP.
- `bird-recorder-watchdog`: vigila los anteriores usando Docker.

El watchdog reduce el riesgo de bucles de reinicio mediante cooldown y backoff.

---

### 11. Notas importantes

- La limpieza automática se dispara desde la consulta de estado de memoria, no desde un cron independiente.
- El sistema depende de acceso privilegiado para audio, GPIO y sensores.
- El acceso a Docker socket permite al servidor y watchdog interactuar con contenedores.
- Los ficheros de audio pueden ocupar mucho espacio; conviene activar limpieza automática si el almacenamiento es limitado.
- La generación de espectrogramas es parte del flujo de grabación; si falla, el contenedor puede salir para que Docker/watchdog lo recuperen.

---

### 12. Resumen de cumplimiento

| Requisito | Estado |
|---|---|
| Estadísticas | Implementado |
| Watchdog Docker incremental | Implementado |
| Limpieza de memoria manual | Implementado |
| Limpieza de memoria cuando está lleno | Implementado con ejecución al consultar memoria |
| Bloque de grabación automática | Implementado |
| Mostrar y filtrar grabaciones | Implementado |
| Rutas para audios y JSON de memoria | Implementado |

---

## English

### 1. Overview

This project implements an automatic audio recording system intended for an Orange Pi or similar Linux device. The system is deployed with Docker and splits responsibilities across several services:

- `bird-recorder`: automatically records audio and generates spectrograms.
- `bird-stats`: records temperature and humidity statistics.
- `bird-http-server`: exposes the web interface and HTTP endpoints for configuration, file browsing, memory, sensors and status.
- `bird-recorder-watchdog`: monitors the main containers and performs controlled restarts when failures are detected.

Persistent data is stored under `/data`, including WAV recordings, PNG spectrograms, CSV histories, configuration, recorder state and watchdog state.

---

### 2. Implemented architecture

```text
pruebas_grabadora/
├── DHT22/                  # DHT22 sensor code/binary
├── httpserver/             # C++ HTTP server and web interface
│   ├── html/               # HTML pages, CSS, JS and images
│   └── lib/                # Routes, system logic, sessions and sensors
├── recorder/               # Automatic recording service
├── server/                 # HTTP server Docker build
├── spectrogram/            # Spectrogram generation
├── stats/                  # Temperature/humidity metrics service
├── watchdog/               # Docker container watchdog
├── docker-compose.yml      # Service orchestration
├── generar_usuario         # Credential helper
└── README_OrangePi_Docker.md
```

---

### 3. Docker services

#### 3.1. `bird-recorder`

Service responsible for automatic recording.

Implemented features:

- Creates persistent folders:
  - `/data/recordings`
  - `/data/sdBackup`
- Creates/updates state files:
  - `/data/stats.txt`
  - `/data/recorder_state.env`
  - station-based log file
- Reads configuration from environment variables and `/data/config.txt`.
- Records audio using `sox`.
- Uses timeout to prevent hanging recording processes.
- Generates a spectrogram after each WAV.
- Tracks recorder stages:
  - `init`
  - `recording`
  - `spectrogram`
  - `sleeping`
- Exits on spectrogram failure so Docker/watchdog can recover the service.
- Allows configuration of duration, sample rate, bitrate, gain, recorder ID, GPIO, audio device and delay between recordings.

Main variables:

| Variable | Description | Default / used value |
|---|---|---|
| `DATA_DIR` | Persistent data directory | `/data` |
| `STATION` | Station prefix for files | `TECHOUTAD_` |
| `BITRATE` | Audio bitrate | `16` |
| `SAMPLE_RATE` | Audio sample rate | `32000` |
| `GAIN` | Gain | `5.0` |
| `DURATION` | Recording duration in seconds | `60` |
| `IDRECORDER` | Recorder identifier | `1` |
| `SLEEPDURATION` | Delay between recordings | `10` |
| `GPIO_PIN` | GPIO pin | `117` |
| `AUDIO_DEVICE` | ALSA device | `plughw:CARD=Microphone,DEV=0` |

---

#### 3.2. `bird-stats`

Service responsible for metrics collection.

Implemented features:

- Reads internal temperature from `/sys/class/thermal/thermal_zone0/temp`.
- Reads external temperature and humidity using the DHT22 binary.
- Writes history to `/data/sensor_history.csv`.
- Maintains CSV header:

```csv
timestamp,internal_temp,external_temp,humidity
```

- Rotates the CSV to limit the number of stored lines.
- Tolerates DHT22 failures so other metrics keep working.
- Includes its own healthcheck.

Main variables:

| Variable | Description | Default / used value |
|---|---|---|
| `DATA_DIR` | Persistent data directory | `/data` |
| `SLEEP_INTERVAL` | Delay between readings | `60` in compose |
| `MAX_LINES` | Maximum retained lines | `130000` in compose |
| `STATS_MAX_AGE_SECONDS` | Maximum expected metrics age for healthcheck | `300` |

---

#### 3.3. `bird-http-server`

Service responsible for the web interface and HTTP API.

Implemented features:

- Serves the web interface.
- Serves persistent files from `/data`.
- Exposes routes for:
  - login
  - file listing
  - configuration get/save
  - memory status
  - statistics cleanup
  - spectrogram cleanup
  - audio cleanup
  - automatic cleanup configuration
  - watchdog status
  - sensors
  - temperature
- Exposes port `8000`.
- Mounts `/data` to access recordings, metrics and status files.
- Mounts `/var/run/docker.sock` to restart `bird-recorder` after configuration changes.
- Includes its own healthcheck.

---

#### 3.4. `bird-recorder-watchdog`

Service responsible for Docker fault tolerance.

Implemented features:

- Monitors:
  - `bird-recorder`
  - `bird-stats`
  - `bird-http-server`
- Detects containers that are:
  - missing
  - stopped
  - unhealthy
  - starting
  - running without healthcheck
- Restarts failed containers.
- Applies per-container cooldown to avoid aggressive restart loops.
- Maintains restart history inside a time window.
- Enables long backoff if a container exceeds the maximum number of restarts.
- Writes JSON status to `/data/watchdog_status.json`.
- Makes watchdog state available through the web/API.

Main variables:

| Variable | Description | Used value |
|---|---|---|
| `WATCHDOG_CONTAINERS` | Monitored containers | `bird-recorder,bird-stats,bird-http-server` |
| `CHECK_INTERVAL` | Check interval | `60` |
| `WATCHDOG_RESTART_COOLDOWN_SECONDS` | Normal cooldown | `300` |
| `WATCHDOG_FAILURE_WINDOW_SECONDS` | Failure window | `1800` |
| `WATCHDOG_MAX_RESTARTS_IN_WINDOW` | Maximum restarts in the window | `3` |
| `WATCHDOG_LONG_COOLDOWN_SECONDS` | Long backoff | `1800` |
| `WATCHDOG_STATUS_FILE` | JSON status file | `/data/watchdog_status.json` |

---

### 4. Implemented features

#### 4.1. Statistics

Implemented.

The system records internal temperature, external temperature and humidity in `/data/sensor_history.csv`.

The web/API layer also provides routes to query latest and historical values.

---

#### 4.2. Incremental Docker watchdog

Implemented.

The watchdog does more than restart failed containers. It applies incremental protection logic:

1. Detect failure.
2. Check normal cooldown.
3. Restart if allowed.
4. Register the restart in a time window.
5. If too many restarts happen, activate long backoff.
6. Publish JSON status for inspection.

---

#### 4.3. Memory cleanup

Implemented.

Manual cleanup actions exist for:

- statistics
- spectrograms
- WAV audio files

The cleanup logic lives in the HTTP backend and acts on `/data`.

---

#### 4.4. Memory cleanup when storage is full

Implemented with an operational note.

The backend includes configurable automatic cleanup:

- Disk usage threshold: `90%`
- Deleted percentage: `20%`
- Affected data:
  - old WAV files
  - old PNG files
  - old rows from the sensor CSV

Note: automatic cleanup runs when the memory status route is queried. It is not an independent daemon running every minute.

---

#### 4.5. Automatic recording block

Implemented.

The recording script runs in a loop:

1. Load configuration.
2. Prepare folders.
3. Enable GPIO when available.
4. Generate timestamped filename.
5. Record WAV with `sox`.
6. Generate spectrogram.
7. Log board temperature.
8. Update state.
9. Sleep for `SLEEPDURATION`.
10. Repeat.

---

#### 4.6. Display and filter recordings

Implemented.

The web interface can list recordings and filter by:

- name
- start date
- end date
- extension

The backend extracts timestamps from filenames and applies the filters before returning the file list.

---

#### 4.7. Routes for audio files and memory JSON

Implemented.

The server can serve files from `/data`, so recordings and spectrograms are available as HTTP resources.

There are also endpoints for memory status and cleanup.

---

### 5. Web interface

The `httpserver/html` directory contains the system interface.

Main pages:

| Page | Purpose |
|---|---|
| `index.html` | Main page |
| `login.html` | System login |
| `config.html` | Recorder configuration |
| `recordings.html` | Recording browser and filters |
| `memory.html` | Memory status and cleanup |
| `status.html` | Service status |
| `temperature.html` | Sensor/temperature view |

---

### 6. Main endpoints

#### 6.1. Registered POST endpoints

| Endpoint / Class | Purpose |
|---|---|
| `Login` | Authentication |
| `ListFiles` | File and folder listing |
| `RecordData` | Data writing |
| `GetConfig` | Get configuration |
| `SaveConfig` | Save configuration and restart recorder |
| `MemoryStatus` | Disk usage, WAV/PNG counts and automatic cleanup |
| `ClearStats` | Clear statistics |
| `ClearSpectrograms` | Delete PNG spectrograms |
| `ClearAudios` | Delete WAV audio files |
| `GetAutoCleanup` | Get automatic cleanup state |
| `SaveAutoCleanup` | Enable/disable automatic cleanup |

#### 6.2. Query and file routes

| Route | Method | Description |
|---|---|---|
| `/` | GET | Web interface |
| `/recordings/...` | GET | Access WAV/PNG files stored in `/data/recordings` |
| `/watchdog_status.json` | GET | JSON status generated by the watchdog |
| `/watchdog/status` | GET | Watchdog status |
| `/sensors/latest` | GET | Latest sensor reading |
| `/sensors/history` | GET | Sensor history |
| `/temperature` | GET | Current temperature |
| `/temperature/history` | GET | Temperature history |
| `/config` | GET/POST depending on web implementation | Recorder configuration |

---

### 7. Persistent files under `/data`

| File / folder | Description |
|---|---|
| `/data/recordings` | WAV audio files and PNG spectrograms |
| `/data/sdBackup` | Folder prepared for backups |
| `/data/stats.txt` | Simple recording/temperature log |
| `/data/sensor_history.csv` | Temperature and humidity history |
| `/data/config.txt` | Editable recorder configuration |
| `/data/credentials.txt` | Login credentials |
| `/data/recorder_state.env` | Current recorder state |
| `/data/watchdog_status.json` | Watchdog state |
| `/data/auto_cleanup.txt` | Automatic cleanup configuration |

---

### 8. Startup

#### 8.1. Build and start

```bash
docker compose up -d --build
```

#### 8.2. Check containers

```bash
docker ps
```

#### 8.3. View logs

```bash
docker logs -f bird-recorder
docker logs -f bird-stats
docker logs -f bird-http-server
docker logs -f bird-recorder-watchdog
```

#### 8.4. Open the web UI

```text
http://<ORANGE_PI_IP>:8000
```

---

### 9. Configuration

The system supports configuration through environment variables and `/data/config.txt`.

Example:

```env
STATION=TECHOUTAD_
BITRATE=16
SAMPLE_RATE=32000
GAIN=5.0
DURATION=60
IDRECORDER=1
SLEEPDURATION=10
GPIO_PIN=117
AUDIO_DEVICE=plughw:CARD=Microphone,DEV=0
```

When configuration is saved from the UI/API, the server restarts the `bird-recorder` container so changes are applied.

---

### 10. Healthchecks and fault tolerance

Each main service has a healthcheck or watchdog coverage:

- `bird-recorder`: checks that the recording process is working.
- `bird-stats`: checks that metrics are being updated.
- `bird-http-server`: checks HTTP availability.
- `bird-recorder-watchdog`: monitors the previous services through Docker.

The watchdog reduces restart-loop risk using cooldown and backoff.

---

### 11. Important notes

- Automatic cleanup is triggered from the memory status query, not by an independent cron-like daemon.
- The system requires privileged access for audio, GPIO and sensors.
- Docker socket access allows the server and watchdog to interact with containers.
- Audio files can consume significant storage; automatic cleanup is recommended when storage is limited.
- Spectrogram generation is part of the recording flow; if it fails, the container may exit so Docker/watchdog can recover it.

---

### 12. Compliance summary

| Requirement | Status |
|---|---|
| Statistics | Implemented |
| Incremental Docker watchdog | Implemented |
| Manual memory cleanup | Implemented |
| Memory cleanup when full | Implemented, triggered on memory-status query |
| Automatic recording block | Implemented |
| Display and filter recordings | Implemented |
| Routes for audio files and memory JSON | Implemented |

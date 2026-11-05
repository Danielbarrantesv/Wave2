# wave-toolkit

Scripts para gestionar el flujo de trabajo de **wave-app** (Android, Kotlin/Compose)
desde el sandbox Wave2, sin perder cambios y reduciendo errores.

## Que resuelve

- **Sandbox reciclado**: el sandbox pierde todo al reiniciar. Estos scripts
  viven en `Wave2/scripts/wave-toolkit/` (pusheado a GitHub) y reconstruyen
  el entorno de desarrollo en cualquier sesion nueva.
- **Cambios perdidos**: `sync.sh` auto-commitea y pushea con un mensaje
  generado, asi nunca te quedas con trabajo sin subir.
- **Builds rotos en GitHub**: `safe-push.sh` compila localmente ANTES de
  push; si falla, aborta el push y no ensucia `main`.
- **Toolchain perdido**: `bootstrap.sh` instala JDK 21 + Gradle 8.14.3 +
  Android SDK 36 de forma idempotente (espejos Aliyun).

## Flujo recomendado

```
1. ./bootstrap.sh        # una sola vez por sandbox nuevo
2. ./workon.sh           # al iniciar cada sesion (clone o pull + env)
3. ... editar codigo ...
4. ./sync.sh             # commit + push rapido (no build)
5. ./safe-push.sh        # antes de publicar algo "oficial" (build + push)
```

## Scripts

| Script           | Para que sirve                                           |
|------------------|----------------------------------------------------------|
| `bootstrap.sh`   | Instala JDK 21 + Gradle 8.14.3 + Android SDK 36          |
| `workon.sh`      | Inicia sesion: clone/pull + activa entorno + dashboard   |
| `sync.sh`        | Commit + push rapido (no hace build)                     |
| `safe-push.sh`   | Build local + push + CHANGELOG (regla 13.1 spec Wave)    |
| `install-hooks.sh` | Instala `pre-push` hook (verifica build antes de push) |
| `status.sh`      | Dashboard de salud (git + toolchain + APK + sugerencias) |
| `recover.sh`     | Recuperacion ante desastre (re-clone + bootstrap)        |

## Variables de entorno

| Variable             | Default                        | Para que             |
|----------------------|--------------------------------|----------------------|
| `WAVE_TOOLCHAIN_DIR` | `$HOME/wave-toolchain`         | Donde instalar tools |
| `WAVE_APP_DIR`       | `/home/z/my-project/wave-app`  | Donde clonar el repo |
| `WAVE_GITHUB_TOKEN`  | (vacío)                        | PAT para push privado|
| `WAVE_REPO`          | `github.com/Danielbarrantesv/wave-app` | URL override   |

## Setup inicial en sandbox nuevo

```bash
cd /home/z/my-project/scripts/wave-toolkit
chmod +x *.sh

# 1. Instalar toolchain (JDK + Gradle + Android SDK)
./bootstrap.sh

# 2. Activar entorno en este shell
source $HOME/wave-toolchain/env.sh

# 3. Iniciar sesion de trabajo en wave-app
export WAVE_GITHUB_TOKEN=ghp_xxx   # si repo privado
./workon.sh

# 4. Instalar git hook (una sola vez por clone)
./install-hooks.sh
```

Despues de eso, el flujo diario es solo: `./workon.sh` → editar → `./sync.sh` o `./safe-push.sh`.

## Anti-patrones

- **NO** editar directo en GitHub web: perdés el build local.
- **NO** `git push --force` a main sin aviso: rompe a otros contributors.
- **NO** saltar el hook con `WAVE_SKIP_BUILD_CHECK=1` salvo emergencia real.
- **NO** usar `sync.sh` para publicar versiones estables: usar `safe-push.sh`.

## Documento completo

Ver `download/Wave_Workflow_Desarrollo.docx` para la especificacion del
flujo, anti-patrones, decision tree y mapeo a las reglas 13.1 / 14 / 15.1
de la spec Wave v2.4.0.

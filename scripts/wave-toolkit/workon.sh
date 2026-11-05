#!/usr/bin/env bash
# workon.sh — Inicia una sesion de trabajo en wave-app.
#
# Hace:
#   1. Verifica/instala toolchain (llama a bootstrap.sh si hace falta)
#   2. Clona github.com/Danielbarrantesv/wave-app si no existe
#   3. Pull de main (si hay remoto y no hay cambios locales)
#   4. Verifica que working tree este limpio (o avisa)
#   5. Activa entorno (JAVA_HOME, GRADLE_HOME, ANDROID_HOME)
#   6. Imprime dashboard de estado
#
# Uso:
#   ./workon.sh                       # sesion normal
#   ./workon.sh --no-pull             # clona/pone entorno pero NO hace pull
#   ./workon.sh --repo URL            # override del repo (privado: usar con token)
#   WAVE_GITHUB_TOKEN=xxx ./workon.sh # repo privado
#
# Salida: 0 si sesion lista, !=0 si bloqueador.

set -euo pipefail

# ============================================================================
# Config
# ============================================================================
WAVE_ROOT="${WAVE_ROOT:-/home/z/my-project}"
WAVE_APP_DIR="${WAVE_APP_DIR:-$WAVE_ROOT/wave-app}"
WAVE_REPO_DEFAULT="https://github.com/Danielbarrantesv/wave-app.git"
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE_TOOLCHAIN_DIR="${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}"

# Colores
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; BOLD=""; NC=""
fi

log()  { printf "%s[workon]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf "%s  [OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s [ERR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# Args
DO_PULL=true
REPO_URL="$WAVE_REPO_DEFAULT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-pull) DO_PULL=false; shift ;;
    --repo)    REPO_URL="$2"; shift 2 ;;
    --help|-h)
      cat <<USAGE
Uso: workon.sh [--no-pull] [--repo URL]

Prepara sesion de trabajo en wave-app:
  1. bootstrap del toolchain si falta
  2. clone del repo (si no existe)
  3. pull main (a menos que --no-pull)
  4. activa entorno
  5. dashboard

Variables:
  WAVE_ROOT           Directorio base (default: /home/z/my-project)
  WAVE_APP_DIR        Donde clonar wave-app (default: \$WAVE_ROOT/wave-app)
  WAVE_GITHUB_TOKEN   PAT para repo privado (opcional)
  WAVE_TOOLCHAIN_DIR  Donde esta el toolchain (default: \$HOME/wave-toolchain)
USAGE
      exit 0 ;;
    *) err "argumento desconocido: $1"; exit 2 ;;
  esac
done

# ============================================================================
# Paso 1: Toolchain
# ============================================================================
log "Paso 1/5: toolchain"
if [[ ! -f "$WAVE_TOOLCHAIN_DIR/env.sh" ]]; then
  warn "toolchain no inicializado, lanzando bootstrap.sh"
  bash "$TOOLKIT_DIR/bootstrap.sh" --check 2>/dev/null || bash "$TOOLKIT_DIR/bootstrap.sh"
else
  if ! bash "$TOOLKIT_DIR/bootstrap.sh" --check >/dev/null 2>&1; then
    warn "toolchain incompleto, lanzando bootstrap.sh"
    bash "$TOOLKIT_DIR/bootstrap.sh"
  else
    ok "toolchain ya completo"
  fi
fi

# Activar entorno
if [[ -f "$WAVE_TOOLCHAIN_DIR/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$WAVE_TOOLCHAIN_DIR/env.sh"
fi

# ============================================================================
# Paso 2: Clone si falta
# ============================================================================
log "Paso 2/5: clone de wave-app"
if [[ ! -d "$WAVE_APP_DIR/.git" ]]; then
  log "clonando $REPO_URL en $WAVE_APP_DIR"

  # Si hay token y la URL es https, inyectar token
  local_url="$REPO_URL"
  if [[ -n "${WAVE_GITHUB_TOKEN:-}" ]] && [[ "$local_url" == https://github.com/* ]]; then
    local_url="${local_url/https:\/\//https:\/\/Danielbarrantesv:${WAVE_GITHUB_TOKEN}@}"
  fi

  git clone "$local_url" "$WAVE_APP_DIR" || { err "fallo el clone"; exit 3; }
  # Reescribir origin a URL sin token para no dejarlo en .git/config
  git -C "$WAVE_APP_DIR" remote set-url origin "$REPO_URL"
  ok "repo clonado"
else
  ok "repo ya presente en $WAVE_APP_DIR"
fi

cd "$WAVE_APP_DIR"

# ============================================================================
# Paso 3: Pull
# ============================================================================
if $DO_PULL; then
  log "Paso 3/5: pull main"

  # Fetch primero (siempre seguro)
  if git fetch origin --quiet 2>/dev/null; then
    ok "fetch OK"
  else
    warn "fetch fallo (sin red?) — trabajando con estado local"
  fi

  # Verificar working tree
  if [[ -n "$(git status --porcelain)" ]]; then
    warn "working tree NO limpio — NO se hara pull para no perder cambios"
    warn "ejecuta ./sync.sh o ./status.sh para revisar"
  else
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" == "main" ]]; then
      if git pull --ff-only origin main --quiet 2>/dev/null; then
        ok "pull main OK"
      else
        warn "pull --ff-only fallo; revisa conflictos"
      fi
    else
      warn "branch actual: $current_branch (no main) — sin pull automatico"
    fi
  fi
else
  log "Paso 3/5: --no-pull, saltando"
fi

# ============================================================================
# Paso 4: Verificar working tree + hooks instalados
# ============================================================================
log "Paso 4/5: verificacion"

local_changes=$(git status --porcelain | wc -l)
last_commit=$(git log -1 --oneline 2>/dev/null || echo "(sin commits)")
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(sin branch)")

if [[ "$local_changes" -eq 0 ]]; then
  ok "working tree limpio"
else
  warn "hay $local_changes archivos modificados/sin trackear"
fi

# Verificar hook pre-push instalado
if [[ -x ".git/hooks/pre-push" ]]; then
  ok "pre-push hook instalado"
else
  warn "pre-push hook NO instalado — recomendado: $TOOLKIT_DIR/install-hooks.sh"
fi

# ============================================================================
# Paso 5: Dashboard
# ============================================================================
log "Paso 5/5: dashboard"

# Informacion de build artifacts
apk_count=0
apk_latest="(ninguno)"
if [[ -d "app/build/outputs/apk/debug" ]]; then
  apk_count=$(find app/build/outputs/apk/debug -name "*.apk" 2>/dev/null | wc -l)
  if [[ "$apk_count" -gt 0 ]]; then
    apk_latest=$(ls -t app/build/outputs/apk/debug/*.apk 2>/dev/null | head -1)
    apk_latest=$(basename "$apk_latest")
  fi
fi

echo ""
echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo "${BOLD}  Wave — sesion iniciada$(date +"  %Y-%m-%d %H:%M")${NC}"
echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
printf "  Repo:        %s\n" "$WAVE_APP_DIR"
printf "  Branch:      %s\n" "$current_branch"
printf "  Ultimo commit: %s\n" "$last_commit"
printf "  Cambios locales: %s\n" "$([[ $local_changes -eq 0 ]] && echo "limpio" || echo "${local_changes} archivos")"
printf "  Pre-push hook: %s\n" "$([[ -x .git/hooks/pre-push ]] && echo "instalado" || echo "no instalado")"
echo ""
echo "${CYAN}Toolchain:${NC}"
printf "  JAVA_HOME:   %s\n" "${JAVA_HOME:-(no activo)}"
[[ -n "${JAVA_HOME:-}" ]] && [[ -x "$JAVA_HOME/bin/javac" ]] \
  && printf "              javac %s\n" "$("$JAVA_HOME/bin/javac" -version 2>&1 | awk '{print $2}')"
printf "  GRADLE_HOME: %s\n" "${GRADLE_HOME:-(no activo)}"
[[ -n "${GRADLE_HOME:-}" ]] && [[ -x "$GRADLE_HOME/bin/gradle" ]] \
  && printf "              gradle %s\n" "$("$GRADLE_HOME/bin/gradle" --version 2>/dev/null | awk '/Gradle /{print $2}')"
printf "  ANDROID_HOME: %s\n" "${ANDROID_HOME:-(no activo)}"
echo ""
echo "${CYAN}Build artifacts:${NC}"
printf "  APK count:   %s\n" "$apk_count"
printf "  APK latest:  %s\n" "$apk_latest"
echo ""
echo "${BOLD}Comandos utiles:${NC}"
echo "  ./sync.sh         # commit + push de cambios pendientes"
echo "  ./safe-push.sh    # build + push (verifica antes de subir)"
echo "  ./status.sh       # dashboard de salud"
echo "  ./recover.sh      # recuperacion ante desastre"
echo ""

ok "sesion lista"

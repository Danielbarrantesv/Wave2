#!/usr/bin/env bash
# safe-push.sh — Build local + push.
#
# Es la VERIFICACION ANTES DE SUBIR (regla 13.1 de la spec Wave):
#   1. Build local: ./gradlew assembleDebug
#   2. Si build falla -> aborta push, NO sube nada
#   3. Si build pasa -> commitea si hay cambios + pushea
#   4. Actualiza CHANGELOG.md con el commit
#
# Esto es lo que DEBES usar para publicar cambios estables.
# sync.sh es para "guardar rapido sin perder", safe-push.sh es para "publicar confiado".
#
# Uso:
#   ./safe-push.sh                      # build + commit auto + push
#   ./safe-push.sh -m "fix: eq init"    # build + commit custom + push
#   ./safe-push.sh --no-changelog       # no toca CHANGELOG.md
#   ./safe-push.sh --build-only         # solo build, no commit/push
#
# Variables:
#   WAVE_GITHUB_TOKEN  PAT de GitHub (para push en repo privado)

set -euo pipefail

WAVE_APP_DIR="${WAVE_APP_DIR:-/home/z/my-project/wave-app}"
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$WAVE_APP_DIR/.git" ]]; then
  echo "[ERR] $WAVE_APP_DIR no es un repo git" >&2
  exit 2
fi
cd "$WAVE_APP_DIR"

# Colores
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; BOLD=""; NC=""
fi
log()  { printf "%s[safe-push]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf "%s  [OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s [ERR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# Args
COMMIT_MSG=""
UPDATE_CHANGELOG=true
BUILD_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) COMMIT_MSG="$2"; shift 2 ;;
    --no-changelog) UPDATE_CHANGELOG=false; shift ;;
    --build-only) BUILD_ONLY=true; shift ;;
    --help|-h)
      cat <<USAGE
Uso: safe-push.sh [-m "msg"] [--no-changelog] [--build-only]

Sin argumentos      build + commit auto + push + actualiza CHANGELOG.md
-m "mensaje"        build + commit custom + push
--no-changelog      no actualiza CHANGELOG.md
--build-only        solo build, no commitea ni pushea

Variables:
  WAVE_GITHUB_TOKEN  PAT de GitHub (requerido para push en repo privado)
USAGE
      exit 0 ;;
    *) err "argumento desconocido: $1"; exit 2 ;;
  esac
done

# ============================================================================
# Pre-condiciones
# ============================================================================
# Activar entorno
if [[ -f "${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}/env.sh"
fi

if [[ -z "${JAVA_HOME:-}" ]] || [[ ! -x "$JAVA_HOME/bin/javac" ]]; then
  err "JAVA_HOME no configurado o sin javac"
  warn "ejecuta primero: bash $TOOLKIT_DIR/bootstrap.sh"
  exit 3
fi

# Localizar gradlew del proyecto o usar gradle del toolchain
GRADLE_BIN=""
if [[ -x "./gradlew" ]]; then
  GRADLE_BIN="./gradlew"
elif [[ -x "${GRADLE_HOME:-}/bin/gradle" ]]; then
  GRADLE_BIN="$GRADLE_HOME/bin/gradle"
else
  err "no se encontro gradlew ni gradle en GRADLE_HOME"
  exit 3
fi
ok "usando: $GRADLE_BIN"

# ============================================================================
# Paso 1: BUILD
# ============================================================================
log "Paso 1: build local (assembleDebug)"

# Limpiar cache si hace falta (rara vez)
build_start=$(date +%s)

# Flags del build (espejos Aliyun ya en gradle.properties del proyecto)
BUILD_FLAGS=(
  "--no-daemon"
  "--max-workers=1"
  "-Dorg.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m"
  "assembleDebug"
)

# Mostrar output en vivo, capturar exit code
set +e
$GRADLE_BIN "${BUILD_FLAGS[@]}"
build_rc=$?
set -e
build_end=$(date +%s)
build_duration=$(( build_end - build_start ))

if [[ $build_rc -ne 0 ]]; then
  err "BUILD FALLO (rc=$build_rc, ${build_duration}s)"
  warn "PUSH ABORTADO — no se subio nada a GitHub"
  warn "revisa el log de gradle arriba"
  exit 4
fi
ok "BUILD OK (${build_duration}s)"

# Verificar APK generado
apk_path="app/build/outputs/apk/debug/app-debug.apk"
if [[ ! -f "$apk_path" ]]; then
  warn "no se encontro APK en $apk_path (build OK pero sin output?)"
else
  apk_size=$(du -h "$apk_path" | cut -f1)
  ok "APK generado: $apk_path ($apk_size)"
fi

if $BUILD_ONLY; then
  ok "modo --build-only: terminando aqui"
  exit 0
fi

# ============================================================================
# Paso 2: Commit si hay cambios
# ============================================================================
has_changes=false
if [[ -n "$(git status --porcelain)" ]]; then
  has_changes=true
fi

if ! $has_changes && [[ -z "$COMMIT_MSG" ]]; then
  log "Paso 2: sin cambios que commitear"
else
  log "Paso 2: commit"
  if [[ -z "$COMMIT_MSG" ]]; then
    ts=$(date +"%Y-%m-%d %H:%M")
    apk_v=$(grep -m1 "versionName" app/build.gradle* 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "?")
    COMMIT_MSG="[safe-push] build OK v${apk_v} — ${ts}"
  fi
  git add -A
  if git commit -m "$COMMIT_MSG" >/dev/null 2>&1; then
    ok "commit: $COMMIT_MSG"
  else
    warn "commit fallo o no habia cambios"
  fi
fi

# ============================================================================
# Paso 3: CHANGELOG.md
# ============================================================================
if $UPDATE_CHANGELOG && [[ -f "CHANGELOG.md" ]] || $UPDATE_CHANGELOG; then
  log "Paso 3: CHANGELOG.md"
  if [[ ! -f "CHANGELOG.md" ]]; then
    cat > CHANGELOG.md <<'EOF'
# CHANGELOG — Wave

Cambios publicados via safe-push.sh. Build OK = compilacion local verde antes del push.
EOF
  fi
  ts=$(date +"%Y-%m-%d %H:%M")
  last_hash=$(git log -1 --format="%h" 2>/dev/null || echo "?")
  apk_v=$(grep -m1 "versionName" app/build.gradle* 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "?")
  msg_for_log="${COMMIT_MSG:-[sin cambios, solo build verification]}"

  # Insertar nueva entrada despues del header (linea 3)
  tmp=$(mktemp)
  head -3 CHANGELOG.md > "$tmp"
  echo "- **$ts** ($last_hash) v$apk_v — $msg_for_log" >> "$tmp"
  echo "  - build: OK (${build_duration}s), APK $apk_size" >> "$tmp"
  tail -n +4 CHANGELOG.md >> "$tmp"
  mv "$tmp" CHANGELOG.md
  git add CHANGELOG.md
  if ! git diff --cached --quiet CHANGELOG.md 2>/dev/null; then
    git commit --amend --no-edit >/dev/null 2>&1 || true
  fi
  ok "CHANGELOG.md actualizado"
fi

# ============================================================================
# Paso 4: Push
# ============================================================================
log "Paso 4: push"

# Configurar origin con token si hace falta
origin_url=$(git remote get-url origin 2>/dev/null || echo "")
token_pushed=0
if [[ "$origin_url" == https://github.com/* ]] && [[ -n "${WAVE_GITHUB_TOKEN:-}" ]]; then
  user_name=$(git config user.name 2>/dev/null || echo "Danielbarrantesv")
  push_url="${origin_url/https:\/\//https:\/\/${user_name}:${WAVE_GITHUB_TOKEN}@}"
  git remote set-url origin "$push_url"
  token_pushed=1
fi

restore_origin() {
  if [[ $token_pushed -eq 1 ]]; then
    git remote set-url origin "$origin_url" 2>/dev/null || true
  fi
}
trap restore_origin EXIT

current_branch=$(git rev-parse --abbrev-ref HEAD)
if git push origin "$current_branch" 2>&1 | tail -3; then
  ok "push OK a origin/$current_branch"
else
  err "fallo el push"
  warn "BUILD y COMMIT estan OK localmente, NO se perdieron"
  warn "verifica WAVE_GITHUB_TOKEN y permisos"
  exit 5
fi

ok "safe-push completo: build OK + commit + push + CHANGELOG"

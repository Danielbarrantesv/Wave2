#!/usr/bin/env bash
# sync.sh — Auto-commit + push de cambios pendientes en wave-app.
#
# Disenado para "no perder cambios": si hay algo sin commitear, lo commitea
# y lo pushea. Si no hay nada, solo hace pull --ff-only.
#
# Mensaje de commit automatico con:
#   - timestamp
#   - count de archivos cambiados
#   - listado corto de archivos principales
# O override con -m "mensaje".
#
# NO hace build (eso es safe-push.sh). Use sync.sh cuando quieras guardar
# rapido y safe-push.sh cuando quieras publicar una version estable.
#
# Uso:
#   ./sync.sh                        # commit auto + push
#   ./sync.sh -m "fix: equalizer"    # commit con mensaje + push
#   ./sync.sh --no-push              # solo commit, no push
#   ./sync.sh --stash <nombre>       # stash con nombre descriptivo
#
# Variables:
#   WAVE_GITHUB_TOKEN  PAT de GitHub (requerido para push si repo privado)

set -euo pipefail

WAVE_APP_DIR="${WAVE_APP_DIR:-/home/z/my-project/wave-app}"
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$WAVE_APP_DIR/.git" ]]; then
  echo "[ERR] $WAVE_APP_DIR no es un repo git" >&2
  echo "      ejecuta ./workon.sh primero" >&2
  exit 2
fi
cd "$WAVE_APP_DIR"

# Colores
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; NC=""
fi
log()  { printf "%s[sync]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf "%s  [OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s [ERR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# Args
COMMIT_MSG=""
DO_PUSH=true
STASH_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) COMMIT_MSG="$2"; shift 2 ;;
    --no-push) DO_PUSH=false; shift ;;
    --stash) STASH_NAME="$2"; shift 2 ;;
    --help|-h)
      cat <<USAGE
Uso: sync.sh [-m "mensaje"] [--no-push] [--stash NOMBRE]

Sin argumentos     commit automatico + push
-m "mensaje"       commit con mensaje custom + push
--no-push          solo commit (guardar cambios), no subir
--stash NOMBRE     guarda cambios en stash con nombre (no commitea)

Variables:
  WAVE_GITHUB_TOKEN  PAT de GitHub (para push en repo privado)
USAGE
      exit 0 ;;
    *) err "argumento desconocido: $1"; exit 2 ;;
  esac
done

# ============================================================================
# Modo stash: guarda cambios sin commitear
# ============================================================================
if [[ -n "$STASH_NAME" ]]; then
  if [[ -z "$(git status --porcelain)" ]]; then
    ok "nada que stashear"
    exit 0
  fi
  stash_full="wave-${STASH_NAME}-$(date +%Y%m%d-%H%M%S)"
  git add -A
  if git stash push -u -m "$stash_full" >/dev/null; then
    ok "cambios guardados en stash: $stash_full"
    log "para recuperar: git stash pop  |  git stash list"
    exit 0
  else
    err "fallo el stash"
    exit 3
  fi
fi

# ============================================================================
# Verificar estado
# ============================================================================
if [[ -z "$(git status --porcelain)" ]]; then
  log "working tree limpio"
  # Hacer pull --ff-only para mantenerse al dia
  if $DO_PUSH; then
    log "intentando pull --ff-only"
    if git pull --ff-only origin main --quiet 2>/dev/null; then
      ok "al dia con origin/main"
    else
      warn "no se pudo hacer pull --ff-only (posible divergencia)"
    fi
  fi
  ok "nada que sincronizar"
  exit 0
fi

# ============================================================================
# Commit
# ============================================================================
staged_count=$(git status --porcelain | grep -c '^[MADR]' || true)
untracked_count=$(git status --porcelain | grep -c '^??' || true)
modified_count=$(git status --porcelain | grep -c '^.M' || true)

log "archivos: $staged_count staged, $modified_count modified, $untracked_count untracked"

# Auto-generar mensaje si no se dio -m
if [[ -z "$COMMIT_MSG" ]]; then
  ts=$(date +"%Y-%m-%d %H:%M")
  total=$((staged_count + modified_count + untracked_count))
  # Top 3 archivos modificados (por nombre, sin path completo)
  top_files=$(git status --porcelain | awk '{print $2}' | \
    sed 's|.*/||' | head -3 | tr '\n' ',' | sed 's/,$//')
  COMMIT_MSG="[sync] ${total} archivos (${top_files}) — ${ts}"
fi

# Stage todo
git add -A

if git diff --cached --quiet; then
  warn "nada que commitear tras stage (archivos vacios?)"
  exit 0
fi

# Commit
if git commit -m "$COMMIT_MSG" >/dev/null 2>&1; then
  ok "commit: $COMMIT_MSG"
else
  err "fallo el commit"
  git status --short
  exit 4
fi

# ============================================================================
# Push
# ============================================================================
if ! $DO_PUSH; then
  ok "commit hecho (sin push por --no-push)"
  log "para subir despues: ./sync.sh   o   ./safe-push.sh"
  exit 0
fi

# Configurar origin con token si hace falta
origin_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$origin_url" == https://github.com/* ]] && [[ -n "${WAVE_GITHUB_TOKEN:-}" ]]; then
  # Reescribir URL temporalmente para push con token
  user_name=$(git config user.name 2>/dev/null || echo "Danielbarrantesv")
  push_url="${origin_url/https:\/\//https:\/\/${user_name}:${WAVE_GITHUB_TOKEN}@}"
  git remote set-url origin "$push_url"
  trap 'git remote set-url origin "$origin_url"' EXIT
fi

current_branch=$(git rev-parse --abbrev-ref HEAD)
log "push $current_branch -> origin"

if git push origin "$current_branch" 2>&1 | tail -3; then
  ok "push OK"
else
  err "fallo el push"
  warn "los cambios estan commiteados localmente, NO se perdieron"
  warn "verifica WAVE_GITHUB_TOKEN y permisos del repo"
  exit 5
fi

ok "sincronizacion completa"

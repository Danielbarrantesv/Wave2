#!/usr/bin/env bash
# recover.sh — Recuperacion ante desastre.
#
# Casos de uso:
#   - El sandbox se reciclo y perdimos wave-app completo
#   - El working tree de wave-app esta corrupto/inutilizable
#   - Queremos empezar limpio desde GitHub como fuente de verdad
#
# Hace:
#   1. Backup de cambios sin commitear a un tar en /tmp (por si acaso)
#   2. Elimina wave-app/ completo
#   3. Re-clona desde GitHub
#   4. Verifica toolchain (bootstrap.sh --check)
#   5. Ejecuta install-hooks.sh
#   6. Ejecuta status.sh
#
# NUNCA hace force-push ni borra datos en GitHub. Solo reconstruye local.
#
# Uso:
#   ./recover.sh                      # recuperacion completa
#   ./recover.sh --no-backup          # no hace backup de cambios locales
#   ./recover.sh --keep-toolchain     # no toca el toolchain
#   ./recover.sh --dry-run            # solo muestra que haria

set -euo pipefail

WAVE_APP_DIR="${WAVE_APP_DIR:-/home/z/my-project/wave-app}"
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE_TOOLCHAIN_DIR="${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}"
WAVE_REPO="${WAVE_REPO:-https://github.com/Danielbarrantesv/wave-app.git}"

# Colores
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; BOLD=""; NC=""
fi
log()  { printf "%s[recover]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()   { printf "%s  [OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s [ERR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# Args
DO_BACKUP=true
KEEP_TOOLCHAIN=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-backup) DO_BACKUP=false; shift ;;
    --keep-toolchain) KEEP_TOOLCHAIN=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
      cat <<USAGE
Uso: recover.sh [--no-backup] [--keep-toolchain] [--dry-run]

Recuperacion ante desastre: reconstruye wave-app desde GitHub.

--no-backup        No hace backup de cambios locales sin commitear (poco recomendado)
--keep-toolchain   No toca el toolchain (bootstrap.sh)
--dry-run          Solo muestra que haria, no ejecuta

Variables:
  WAVE_APP_DIR       Donde esta/estara wave-app
  WAVE_REPO          URL del repo (default: github.com/Danielbarrantesv/wave-app)
  WAVE_GITHUB_TOKEN  PAT para repo privado
USAGE
      exit 0 ;;
    *) err "argumento desconocido: $1"; exit 2 ;;
  esac
done

# ============================================================================
# Confirmacion interactiva
# ============================================================================
if ! $DRY_RUN; then
  echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
  echo "${BOLD}  RECUPERACION ANTE DESASTRE — Wave${NC}"
  echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo "  Esto va a:"
  echo "    1. $([[ $DO_BACKUP == "true" ]] && echo "BACKUP cambios locales a /tmp/wave-recover-<ts>.tar.gz" || echo "SIN backup de cambios locales")"
  echo "    2. BORRAR $WAVE_APP_DIR completo"
  echo "    3. RE-CLONAR desde $WAVE_REPO"
  $KEEP_TOOLCHAIN || echo "    4. Verificar/instalar toolchain"
  echo "    5. Instalar git hooks"
  echo "    6. Mostrar status final"
  echo ""
  read -rp "Continuar? [escribe SI]: " confirm
  if [[ "$confirm" != "SI" ]]; then
    warn "abortado por el usuario"
    exit 0
  fi
fi

# ============================================================================
# Ejecutar
# ============================================================================
ts=$(date +%Y%m%d-%H%M%S)

# Paso 1: Backup de cambios locales
if $DO_BACKUP && [[ -d "$WAVE_APP_DIR/.git" ]]; then
  log "Paso 1: backup de cambios locales sin commitear"
  if $DRY_RUN; then echo "  [DRY-RUN] backup a /tmp/wave-recover-$ts.tar.gz"; else
    backup_file="/tmp/wave-recover-$ts.tar.gz"
    # Stash incluyendo untracked
    cd "$WAVE_APP_DIR"
    if [[ -n "$(git status --porcelain)" ]]; then
      # Crear tar con archivos modificados + untracked
      file_list=$(git status --porcelain | awk '{print $2}')
      if tar -czf "$backup_file" $file_list 2>/dev/null; then
        ok "backup en $backup_file ($(du -h "$backup_file" | cut -f1))"
      else
        warn "backup fallo (algun archivo no accesible?) — continuando igual"
      fi
    else
      ok "sin cambios locales que respaldar"
    fi
    cd -
  fi
else
  log "Paso 1: backup omitido (--no-backup o sin repo)"
fi

# Paso 2: Eliminar wave-app
log "Paso 2: eliminar $WAVE_APP_DIR"
if $DRY_RUN; then echo "  [DRY-RUN] rm -rf $WAVE_APP_DIR"; else
  rm -rf "$WAVE_APP_DIR"
  ok "eliminado"
fi

# Paso 3: Re-clone
log "Paso 3: clone desde $WAVE_REPO"
clone_url="$WAVE_REPO"
if [[ -n "${WAVE_GITHUB_TOKEN:-}" ]] && [[ "$clone_url" == https://github.com/* ]]; then
  clone_url="${clone_url/https:\/\//https:\/\/Danielbarrantesv:${WAVE_GITHUB_TOKEN}@}"
fi
if $DRY_RUN; then echo "  [DRY-RUN] git clone $WAVE_REPO $WAVE_APP_DIR"; else
  if git clone "$clone_url" "$WAVE_APP_DIR"; then
    # Reescribir origin sin token
    git -C "$WAVE_APP_DIR" remote set-url origin "$WAVE_REPO"
    ok "repo clonado"
  else
    err "fallo el clone"
    exit 3
  fi
fi

# Paso 4: Toolchain
if ! $KEEP_TOOLCHAIN; then
  log "Paso 4: toolchain"
  if $DRY_RUN; then echo "  [DRY-RUN] bootstrap.sh --check + bootstrap.sh si hace falta"; else
    if ! bash "$TOOLKIT_DIR/bootstrap.sh" --check >/dev/null 2>&1; then
      warn "toolchain incompleto — lanzando bootstrap.sh"
      bash "$TOOLKIT_DIR/bootstrap.sh"
    else
      ok "toolchain completo"
    fi
  fi
fi

# Paso 5: Hooks
log "Paso 5: instalar git hooks"
if $DRY_RUN; then echo "  [DRY-RUN] install-hooks.sh"; else
  bash "$TOOLKIT_DIR/install-hooks.sh" --dir "$WAVE_APP_DIR"
fi

# Paso 6: Status
log "Paso 6: status"
if ! $DRY_RUN; then
  bash "$TOOLKIT_DIR/status.sh"
fi

ok "recuperacion completa — wave-app listo"
if ! $DRY_RUN && [[ -f "/tmp/wave-recover-$ts.tar.gz" ]]; then
  echo ""
  warn "si perdiste algo importante, revisa: /tmp/wave-recover-$ts.tar.gz"
fi

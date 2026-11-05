#!/usr/bin/env bash
# install-hooks.sh — Instala git hooks en wave-app/.git/hooks/
#
# Actualmente instala:
#   pre-push: ejecuta ./safe-push.sh --build-only antes de cualquier push.
#             Si el build falla, el push se aborta.
#
# Esto materializa la regla 13.1 de la spec Wave:
#   "Compilar localmente antes de cada push"
#
# Uso:
#   ./install-hooks.sh                # instala en wave-app
#   ./install-hooks.sh --dir /path    # instala en otro repo
#   ./install-hooks.sh --uninstall    # quita los hooks

set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE_APP_DIR="${WAVE_APP_DIR:-/home/z/my-project/wave-app}"

TARGET_DIR=""
UNINSTALL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) TARGET_DIR="$2"; shift 2 ;;
    --uninstall) UNINSTALL=true; shift ;;
    --help|-h)
      cat <<USAGE
Uso: install-hooks.sh [--dir DIR] [--uninstall]

Sin argumentos   instala pre-push hook en $WAVE_APP_DIR
--dir DIR        instala en otro repo
--uninstall      quita los hooks wave-toolkit
USAGE
      exit 0 ;;
    *) echo "arg desconocido: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TARGET_DIR" ]] || TARGET_DIR="$WAVE_APP_DIR"

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "[ERR] $TARGET_DIR no es un repo git" >&2
  exit 2
fi

hooks_dir="$TARGET_DIR/.git/hooks"
mkdir -p "$hooks_dir"

# ============================================================================
# Hook pre-push
# ============================================================================
hook_file="$hooks_dir/pre-push"
marker="# wave-toolkit-managed"

if $UNINSTALL; then
  if [[ -f "$hook_file" ]] && grep -q "$marker" "$hook_file" 2>/dev/null; then
    rm "$hook_file"
    echo "[OK] pre-push hook desinstalado"
  else
    echo "[OK] no habia hook wave-toolkit que desinstalar"
  fi
  exit 0
fi

cat > "$hook_file" <<'HOOK_EOF'
#!/usr/bin/env bash
# pre-push hook — gestionado por wave-toolkit
# wave-toolkit-managed

# Lee stdin (refs being pushed) y descarta
while read -r _local _remote _sha_local _sha_remote; do :; done

# Solo ejecutar build si estamos pusheando a main
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$current_branch" != "main" ]]; then
  echo "[pre-push] branch no-main ($current_branch), saltando build check"
  exit 0
fi

# Localizar toolkit
toolkit_dir=""
for candidate in \
  "$(git rev-parse --git-common-dir 2>/dev/null)/../../scripts/wave-toolkit" \
  "$HOME/wave-toolkit" \
  "/home/z/my-project/scripts/wave-toolkit"; do
  if [[ -f "$candidate/safe-push.sh" ]]; then
    toolkit_dir="$candidate"; break
  fi
done

if [[ -z "$toolkit_dir" ]]; then
  echo "[pre-push] WARN: no se encontro wave-toolkit, saltando build check"
  exit 0
fi

# Skip si la variable WAVE_SKIP_BUILD_CHECK esta seteada
if [[ -n "${WAVE_SKIP_BUILD_CHECK:-}" ]]; then
  echo "[pre-push] WAVE_SKIP_BUILD_CHECK set, saltando build check"
  exit 0
fi

echo "[pre-push] ejecutando build verification (regla 13.1 spec Wave)"
echo "[pre-push] usa WAVE_SKIP_BUILD_CHECK=1 para saltar en emergencias"

# Ejecutar build-only (no commitea, no pushea — solo compila)
if bash "$toolkit_dir/safe-push.sh" --build-only; then
  echo "[pre-push] BUILD OK — push permitido"
  exit 0
else
  echo "[pre-push] BUILD FALLO — push ABORTADO" >&2
  echo "[pre-push] arregla el build y reintenta, o usa WAVE_SKIP_BUILD_CHECK=1 si es emergencia" >&2
  exit 1
fi
HOOK_EOF

chmod +x "$hook_file"
echo "[OK] pre-push hook instalado en $hook_file"
echo "     verificara build antes de cualquier push a main"
echo "     para emergencias: WAVE_SKIP_BUILD_CHECK=1 git push ..."
echo "     para desinstalar: $TOOLKIT_DIR/install-hooks.sh --uninstall"

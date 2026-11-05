#!/usr/bin/env bash
# status.sh — Dashboard de salud del proyecto wave-app.
#
# Muestra:
#   - Estado git (branch, cambios, ultimo commit, divergence con origin)
#   - Estado del toolchain (JDK, Gradle, Android SDK)
#   - Estado del build (APK artifacts, ultimo build time)
#   - Estado de GitHub Actions (si gh CLI disponible o via API)
#   - Sugerencias (que hacer ahora)
#
# Uso:
#   ./status.sh
#   ./status.sh --json    # salida JSON para integracion

set -euo pipefail

WAVE_APP_DIR="${WAVE_APP_DIR:-/home/z/my-project/wave-app}"
TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE_TOOLCHAIN_DIR="${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}"

OUTPUT_MODE="text"
[[ "${1:-}" == "--json" ]] && OUTPUT_MODE="json"

if [[ ! -d "$WAVE_APP_DIR/.git" ]]; then
  if [[ "$OUTPUT_MODE" == "json" ]]; then
    echo '{"error":"repo no encontrado","wave_app_dir":"'$WAVE_APP_DIR'"}'
  else
    echo "[ERR] $WAVE_APP_DIR no es un repo git — ejecuta ./workon.sh" >&2
  fi
  exit 2
fi
cd "$WAVE_APP_DIR"

# ============================================================================
# Recoleccion de datos
# ============================================================================
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(detached)")
last_commit_hash=$(git log -1 --format="%h" 2>/dev/null || echo "?")
last_commit_msg=$(git log -1 --format="%s" 2>/dev/null || echo "(sin commits)")
last_commit_date=$(git log -1 --format="%ci" 2>/dev/null | cut -d' ' -f1 || echo "?")

changes_count=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
changes_untracked=$(git status --porcelain 2>/dev/null | grep -c '^??' || echo "0")
changes_modified=$(git status --porcelain 2>/dev/null | grep -c '^.M' || echo "0")
changes_staged=$(git status --porcelain 2>/dev/null | grep -c '^[MADR]' || echo "0")

# Divergencia con origin
ahead=0; behind=0
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  ahead=$(git rev-list --count origin/main..HEAD 2>/dev/null || echo "0")
  behind=$(git rev-list --count HEAD..origin/main 2>/dev/null || echo "0")
fi

# Toolchain
jdk_version=""; gradle_version=""; sdk_platform=""; sdk_buildtools=""
if [[ -x "$WAVE_TOOLCHAIN_DIR/jdk/bin/javac" ]]; then
  jdk_version=$("$WAVE_TOOLCHAIN_DIR/jdk/bin/javac" -version 2>&1 | awk '{print $2}')
fi
if [[ -x "$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" ]]; then
  gradle_version=$("$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" --version 2>/dev/null | awk '/Gradle /{print $2}' || echo "?")
fi
if [[ -d "$WAVE_TOOLCHAIN_DIR/android-sdk/platforms/android-36" ]]; then
  sdk_platform="36"
fi
if [[ -d "$WAVE_TOOLCHAIN_DIR/android-sdk/build-tools/36.0.0" ]]; then
  sdk_buildtools="36.0.0"
fi

# Build artifacts
apk_count=0; apk_latest=""; apk_size=""
apk_dir="app/build/outputs/apk/debug"
if [[ -d "$apk_dir" ]]; then
  apk_count=$(find "$apk_dir" -name "*.apk" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$apk_count" -gt 0 ]]; then
    apk_latest=$(ls -t "$apk_dir"/*.apk 2>/dev/null | head -1)
    apk_size=$(du -h "$apk_latest" | cut -f1)
    apk_latest=$(basename "$apk_latest")
  fi
fi

# Hook pre-push
hook_installed=$([[ -x ".git/hooks/pre-push" ]] && echo "true" || echo "false")

# App version
app_version=""
if ls app/build.gradle* >/dev/null 2>&1; then
  app_version=$(grep -m1 "versionName" app/build.gradle* 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/' || echo "?")
fi

# CHANGELOG
changelog_entries=0
if [[ -f "CHANGELOG.md" ]]; then
  changelog_entries=$(grep -c '^\-' CHANGELOG.md 2>/dev/null || echo "0")
fi

# ============================================================================
# Salida JSON
# ============================================================================
if [[ "$OUTPUT_MODE" == "json" ]]; then
  cat <<JSON
{
  "wave_app_dir": "$WAVE_APP_DIR",
  "branch": "$current_branch",
  "last_commit": {"hash": "$last_commit_hash", "message": "$last_commit_msg", "date": "$last_commit_date"},
  "changes": {"total": $changes_count, "staged": $changes_staged, "modified": $changes_modified, "untracked": $changes_untracked},
  "remote": {"ahead": $ahead, "behind": $behind},
  "toolchain": {
    "jdk": "${jdk_version:-missing}",
    "gradle": "${gradle_version:-missing}",
    "android_platform": "${sdk_platform:-missing}",
    "android_build_tools": "${sdk_buildtools:-missing}"
  },
  "build": {"apk_count": $apk_count, "apk_latest": "${apk_latest:-none}", "apk_size": "${apk_size:-}"},
  "hooks": {"pre_push": $hook_installed},
  "app_version": "${app_version:-unknown}",
  "changelog_entries": $changelog_entries
}
JSON
  exit 0
fi

# ============================================================================
# Salida texto (dashboard)
# ============================================================================
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; BOLD=""; DIM=""; NC=""
fi

# Semaforo
status_color="$GREEN"
status_text="SALUDABLE"
suggestions=()

if [[ "$changes_count" -gt 0 ]]; then
  status_color="$YELLOW"; status_text="CAMBIOS PENDIENTES"
  suggestions+=("commitea con: ./sync.sh")
fi
if [[ "$behind" -gt 0 ]]; then
  status_color="$YELLOW"; status_text="DETras DE ORIGIN"
  suggestions+=("actualiza con: git pull --ff-only origin main")
fi
if [[ -z "$jdk_version" ]] || [[ -z "$gradle_version" ]] || [[ -z "$sdk_platform" ]]; then
  status_color="$RED"; status_text="TOOLCHAIN INCOMPLETO"
  suggestions+=("instala: bash $TOOLKIT_DIR/bootstrap.sh")
fi
if [[ "$hook_installed" != "true" ]]; then
  suggestions+=("instala pre-push hook: $TOOLKIT_DIR/install-hooks.sh")
fi

echo ""
echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo "${BOLD}  Wave — Status dashboard$(date +"  %Y-%m-%d %H:%M")${NC}"
echo "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""
printf "  %sEstado:%s %s%s%s\n" "$BOLD" "$NC" "$status_color" "$status_text" "$NC"
echo ""
echo "${CYAN}Git:${NC}"
printf "  Branch:        %s\n" "$current_branch"
printf "  Ultimo commit: %s — %s (%s)\n" "$last_commit_hash" "$last_commit_msg" "$last_commit_date"
printf "  Cambios:       %s total (%s staged, %s modified, %s untracked)\n" \
  "$changes_count" "$changes_staged" "$changes_modified" "$changes_untracked"
printf "  vs origin:     %s ahead, %s behind\n" "$ahead" "$behind"
printf "  Hook pre-push: %s\n" "$([[ $hook_installed == "true" ]] && echo "${GREEN}instalado${NC}" || echo "${YELLOW}no instalado${NC}")"
echo ""
echo "${CYAN}App:${NC}"
printf "  Version:       %s\n" "${app_version:-(no encontrada)}"
printf "  CHANGELOG:     %s entradas\n" "$changelog_entries"
echo ""
echo "${CYAN}Toolchain:${NC}"
printf "  JDK:           %s\n" "${jdk_version:-${RED}missing${NC}}"
printf "  Gradle:        %s\n" "${gradle_version:-${RED}missing${NC}}"
printf "  Android API:   %s\n" "${sdk_platform:-${RED}missing${NC}}"
printf "  Build tools:   %s\n" "${sdk_buildtools:-${RED}missing${NC}}"
echo ""
echo "${CYAN}Build artifacts:${NC}"
printf "  APK count:     %s\n" "$apk_count"
if [[ "$apk_count" -gt 0 ]]; then
  printf "  APK latest:    %s (%s)\n" "$apk_latest" "$apk_size"
else
  printf "  APK latest:    %s%s%s (compila con ./safe-push.sh)%s\n" "$DIM" "(ninguno)" "$YELLOW" "$NC"
fi
echo ""

if [[ ${#suggestions[@]} -gt 0 ]]; then
  echo "${YELLOW}Sugerencias:${NC}"
  for s in "${suggestions[@]}"; do
    printf "  • %s\n" "$s"
  done
  echo ""
fi

echo "${DIM}status.sh --json para salida maquina${NC}"
echo ""

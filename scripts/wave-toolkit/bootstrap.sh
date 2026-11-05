#!/usr/bin/env bash
# bootstrap.sh — Instala el toolchain de desarrollo de Wave de forma idempotente.
#
# Toolchain objetivo (segun spec Wave 2.4.0 cap. 2 y 13):
#   - JDK 21 (Temurin / OpenJDK 21) con javac
#   - Gradle 8.14.3
#   - Android SDK: cmdline-tools latest, platform-tools, platforms;android-36, build-tools;36.0.0
#   - Espejos Aliyun primero, oficiales despues
#
# Diseno:
#   - Idempotente: si ya esta instalado y la version coincide, no hace nada.
#   - Marker files en $WAVE_TOOLCHAIN_DIR/.markers/ para evitar reinstalaciones.
#   - Sin sudo: todo va a $WAVE_TOOLCHAIN_DIR (por defecto $HOME/wave-toolchain).
#   - Tolerante a fallos de red: reintentos con backoff.
#
# Uso:
#   ./bootstrap.sh                 # instala todo lo que falte
#   ./bootstrap.sh --check         # solo verifica, no instala
#   ./bootstrap.sh --force         # reinstala desde cero
#
# Salida: 0 si todo OK, !=0 si fallo algo critical.

set -euo pipefail

# ============================================================================
# Configuracion
# ============================================================================
WAVE_TOOLCHAIN_DIR="${WAVE_TOOLCHAIN_DIR:-$HOME/wave-toolchain}"
WAVE_MARKERS_DIR="$WAVE_TOOLCHAIN_DIR/.markers"

JDK_VERSION="21"
JDK_VENDOR="temurin"
GRADLE_VERSION="8.14.3"
ANDROID_API_LEVEL="36"
ANDROID_BUILD_TOOLS="36.0.0"
ANDROID_CMDLINE_TOOLS_VERSION="11076708"  # latest stable as of 2026

# Espejos (Aliyun primero segun regla 13.1 de la spec)
GRADLE_MIRRORS=(
  "https://mirrors.aliyun.com/macports/distfiles/gradle/"
  "https://services.gradle.org/distributions/"
)
CMDLINE_TOOLS_MIRRORS=(
  "https://mirrors.aliyun.com/android.googlesource.com/"
  "https://dl.google.com/android/repository/"
)

# Colores (Wave brand #32C98B)
if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'
  CYAN=$'\033[0;36m'
  YELLOW=$'\033[1;33m'
  RED=$'\033[0;31m'
  NC=$'\033[0m'
else
  GREEN=""; CYAN=""; YELLOW=""; RED=""; NC=""
fi

log()   { printf "%s[bootstrap]%s %s\n" "$CYAN" "$NC" "$*"; }
ok()    { printf "%s[OK]%s %s\n" "$GREEN" "$NC" "$*"; }
warn()  { printf "%s[WARN]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()   { printf "%s[ERR]%s %s\n" "$RED" "$NC" "$*" >&2; }

# ============================================================================
# Setup de directorios
# ============================================================================
mkdir -p "$WAVE_TOOLCHAIN_DIR" "$WAVE_MARKERS_DIR" \
         "$WAVE_TOOLCHAIN_DIR/jdk" \
         "$WAVE_TOOLCHAIN_DIR/gradle" \
         "$WAVE_TOOLCHAIN_DIR/android-sdk"

# ============================================================================
# Helpers
# ============================================================================
download() {
  local url="$1" dest="$2"
  local tmp="${dest}.part"
  local attempt=1 max=3
  while (( attempt <= max )); do
    log "descargando $url (intento $attempt/$max)"
    if curl --fail --location --connect-timeout 30 --max-time 600 \
            --retry 2 --silent --show-error -o "$tmp" "$url"; then
      mv "$tmp" "$dest"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep $((attempt * 5))
  done
  err "no se pudo descargar $url tras $max intentos"
  rm -f "$tmp"
  return 1
}

marker_set() { echo "$2" > "$WAVE_MARKERS_DIR/$1"; }
marker_get() { [[ -f "$WAVE_MARKERS_DIR/$1" ]] && cat "$WAVE_MARKERS_DIR/$1" || echo ""; }
marker_ok()  { [[ -f "$WAVE_MARKERS_DIR/$1" ]] && [[ "$(marker_get $1)" == "$2" ]]; }

# ============================================================================
# Componente 1: JDK 21
# ============================================================================
install_jdk() {
  local marker="jdk-${JDK_VENDOR}-${JDK_VERSION}"
  if marker_ok "$marker" "$marker" && [[ -x "$WAVE_TOOLCHAIN_DIR/jdk/bin/javac" ]]; then
    ok "JDK $JDK_VERSION ya instalado en $WAVE_TOOLCHAIN_DIR/jdk"
    return 0
  fi

  # Detectar JDK 21 del sistema (con javac) antes de descargar
  if command -v javac >/dev/null 2>&1; then
    local sys_jv
    sys_jv=$(javac -version 2>&1 | awk '{print $2}')
    if [[ "$sys_jv" == "$JDK_VERSION"* ]]; then
      local sys_home
      sys_home=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
      log "JDK $JDK_VERSION del sistema detectado en $sys_home, enlazando"
      ln -sfn "$sys_home" "$WAVE_TOOLCHAIN_DIR/jdk"
      marker_set "$marker" "$marker"
      ok "JDK $JDK_VERSION (sistema) enlazado"
      return 0
    fi
  fi

  log "instalando JDK $JDK_VENDOR $JDK_VERSION"
  warn "descarga automatica de JDK Temurin requiere adoptium API; instalando via paquete del sistema si disponible"

  # Intentar via gestor de paquetes (Linux Debian/Ubuntu)
  if command -v apt-get >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
      sudo apt-get install -y "openjdk-${JDK_VERSION}-jdk-headless" 2>/dev/null || \
        sudo apt-get install -y "temurin-${JDK_VERSION}-jdk" 2>/dev/null || true
    else
      warn "no hay sudo sin password; no se puede instalar JDK via apt-get"
    fi
  fi

  # Verificar de nuevo
  if command -v javac >/dev/null 2>&1; then
    local sys_jv
    sys_jv=$(javac -version 2>&1 | awk '{print $2}')
    if [[ "$sys_jv" == "$JDK_VERSION"* ]]; then
      local sys_home
      sys_home=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
      ln -sfn "$sys_home" "$WAVE_TOOLCHAIN_DIR/jdk"
      marker_set "$marker" "$marker"
      ok "JDK $JDK_VERSION instalado via sistema"
      return 0
    fi
  fi

  # Fallback: descargar Temurin (Linux x64)
  local arch="x64"
  local os="linux"
  local temurin_url="https://api.adoptium.net/v3/binary/latest/${JDK_VERSION}/ga/${os}/${arch}/jdk/hotspot/normal/eclipse"
  local pkg="$WAVE_TOOLCHAIN_DIR/jdk.tar.gz"
  if download "$temurin_url" "$pkg"; then
    tar -xzf "$pkg" -C "$WAVE_TOOLCHAIN_DIR/jdk" --strip-components=1
    rm "$pkg"
    marker_set "$marker" "$marker"
    ok "JDK $JDK_VERSION (Temurin) instalado"
    return 0
  fi

  err "no se pudo instalar JDK $JDK_VERSION"
  return 1
}

# ============================================================================
# Componente 2: Gradle 8.14.3
# ============================================================================
install_gradle() {
  local marker="gradle-${GRADLE_VERSION}"
  if marker_ok "$marker" "$marker" && [[ -x "$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" ]]; then
    ok "Gradle $GRADLE_VERSION ya instalado"
    return 0
  fi

  # Detectar gradle del sistema con version correcta
  if command -v gradle >/dev/null 2>&1; then
    local sys_gradle
    sys_gradle=$(gradle --version 2>/dev/null | awk '/Gradle /{print $2}')
    if [[ "$sys_gradle" == "$GRADLE_VERSION" ]]; then
      log "Gradle $GRADLE_VERSION del sistema detectado"
      mkdir -p "$WAVE_TOOLCHAIN_DIR/gradle"
      ln -sfn "$(command -v gradle)" "$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" 2>/dev/null || true
      marker_set "$marker" "$marker"
      ok "Gradle $GRADLE_VERSION (sistema)"
      return 0
    fi
  fi

  log "instalando Gradle $GRADLE_VERSION"
  local pkg="$WAVE_TOOLCHAIN_DIR/gradle.zip"
  local downloaded=false
  for mirror in "${GRADLE_MIRRORS[@]}"; do
    local url="${mirror}gradle-${GRADLE_VERSION}-bin.zip"
    if download "$url" "$pkg"; then
      downloaded=true
      break
    fi
  done
  if ! $downloaded; then
    err "no se pudo descargar Gradle $GRADLE_VERSION"
    return 1
  fi
  unzip -q -o "$pkg" -d "$WAVE_TOOLCHAIN_DIR/gradle-tmp"
  rm -rf "$WAVE_TOOLCHAIN_DIR/gradle"
  mv "$WAVE_TOOLCHAIN_DIR/gradle-tmp/gradle-${GRADLE_VERSION}" "$WAVE_TOOLCHAIN_DIR/gradle"
  rm -rf "$WAVE_TOOLCHAIN_DIR/gradle-tmp" "$pkg"
  marker_set "$marker" "$marker"
  ok "Gradle $GRADLE_VERSION instalado"
}

# ============================================================================
# Componente 3: Android SDK
# ============================================================================
install_android_sdk() {
  local marker="android-sdk-${ANDROID_API_LEVEL}"
  if marker_ok "$marker" "$marker"; then
    ok "Android SDK (API $ANDROID_API_LEVEL) ya instalado"
    return 0
  fi

  local sdk_root="$WAVE_TOOLCHAIN_DIR/android-sdk"
  local cmdline_dir="$sdk_root/cmdline-tools"

  # Si ya hay cmdline-tools, saltar descarga
  if [[ ! -d "$cmdline_dir/latest" ]]; then
    log "instalando Android cmdline-tools"
    mkdir -p "$cmdline_dir"
    local pkg="$sdk_root/cmdline-tools.zip"
    local downloaded=false
    for mirror in "${CMDLINE_TOOLS_MIRRORS[@]}"; do
      local url="${mirror}commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
      if download "$url" "$pkg"; then
        downloaded=true
        break
      fi
    done
    if ! $downloaded; then
      err "no se pudo descargar Android cmdline-tools"
      return 1
    fi
    unzip -q -o "$pkg" -d "$cmdline_dir/tmp"
    mv "$cmdline_dir/tmp/cmdline-tools" "$cmdline_dir/latest"
    rm -rf "$cmdline_dir/tmp" "$pkg"
  fi
  ok "cmdline-tools presente"

  # sdkmanager con espejos Aliyun
  local sdkmanager="$cmdline_dir/latest/bin/sdkmanager"
  chmod +x "$sdkmanager"

  # Configurar mirrors en global config
  mkdir -p "$sdk_root/.cfg"
  cat > "$sdk_root/.cfg/repositories.cfg" <<'EOF'
aidks=sources,Aliyun,https://maven.aliyun.com/repository/google
aidkps=sources,AliyunPublic,https://maven.aliyun.com/repository/public
EOF

  log "aceptando licencias y descargando paquetes SDK (esto puede tardar varios minutos)"
  export ANDROID_SDK_ROOT="$sdk_root"
  export ANDROID_HOME="$sdk_root"

  # Aceptar licencias automaticamente
  yes | "$sdkmanager" --licenses >/dev/null 2>&1 || true

  # Paquetes objetivo
  local packages=(
    "platform-tools"
    "platforms;android-${ANDROID_API_LEVEL}"
    "build-tools;${ANDROID_BUILD_TOOLS}"
  )

  # Usar mirror HTTP para descargas del SDK (proxy Aliyun para dl.google.com)
  for pkg in "${packages[@]}"; do
    log "instalando $pkg"
    if ! "$sdkmanager" --install "$pkg" 2>&1 | tail -5; then
      err "fallo instalando $pkg"
      return 1
    fi
  done

  marker_set "$marker" "$marker"
  ok "Android SDK API $ANDROID_API_LEVEL + build-tools $ANDROID_BUILD_TOOLS instalado"
}

# ============================================================================
# Generar env.sh — variables de entorno listas para sourcear
# ============================================================================
write_env_sh() {
  local env_file="$WAVE_TOOLCHAIN_DIR/env.sh"
  cat > "$env_file" <<EOF
# Generado por bootstrap.sh — no editar a mano
export WAVE_TOOLCHAIN_DIR="$WAVE_TOOLCHAIN_DIR"
export JAVA_HOME="$WAVE_TOOLCHAIN_DIR/jdk"
export GRADLE_HOME="$WAVE_TOOLCHAIN_DIR/gradle"
export ANDROID_HOME="$WAVE_TOOLCHAIN_DIR/android-sdk"
export ANDROID_SDK_ROOT="$WAVE_TOOLCHAIN_DIR/android-sdk"
export PATH="\$JAVA_HOME/bin:\$GRADLE_HOME/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"

# Verificacion rapida
wave_env_ready() {
  [[ -x "\$JAVA_HOME/bin/javac" ]] && [[ -x "\$GRADLE_HOME/bin/gradle" ]] && \\
  [[ -d "\$ANDROID_HOME/platforms/android-${ANDROID_API_LEVEL}" ]] && \\
  [[ -d "\$ANDROID_HOME/build-tools/${ANDROID_BUILD_TOOLS}" ]]
}
EOF
  ok "env.sh escrito en $env_file"
}

# ============================================================================
# Modo --check
# ============================================================================
do_check() {
  log "verificando toolchain"
  local all_ok=true

  if [[ -x "$WAVE_TOOLCHAIN_DIR/jdk/bin/javac" ]]; then
    local jv
    jv=$("$WAVE_TOOLCHAIN_DIR/jdk/bin/javac" -version 2>&1 | awk '{print $2}')
    ok "JDK: $jv"
  else
    err "JDK: ausente"; all_ok=false
  fi

  if [[ -x "$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" ]]; then
    local gv
    gv=$("$WAVE_TOOLCHAIN_DIR/gradle/bin/gradle" --version 2>/dev/null | awk '/Gradle /{print $2}')
    ok "Gradle: $gv"
  else
    err "Gradle: ausente"; all_ok=false
  fi

  if [[ -d "$WAVE_TOOLCHAIN_DIR/android-sdk/platforms/android-${ANDROID_API_LEVEL}" ]]; then
    ok "Android platform: API $ANDROID_API_LEVEL"
  else
    err "Android platform: ausente"; all_ok=false
  fi

  if [[ -d "$WAVE_TOOLCHAIN_DIR/android-sdk/build-tools/${ANDROID_BUILD_TOOLS}" ]]; then
    ok "Android build-tools: $ANDROID_BUILD_TOOLS"
  else
    err "Android build-tools: ausente"; all_ok=false
  fi

  if $all_ok; then
    ok "toolchain COMPLETO"
    return 0
  else
    err "toolchain INCOMPLETO — ejecuta ./bootstrap.sh"
    return 1
  fi
}

# ============================================================================
# Main
# ============================================================================
main() {
  local mode="${1:-install}"

  case "$mode" in
    --check) do_check; exit $? ;;
    --force)
      log "modo --force: borrando markers y reinstalando"
      rm -rf "$WAVE_MARKERS_DIR"/* ;;
    --help|-h)
      cat <<USAGE
Uso: bootstrap.sh [--check|--force|--help]

Sin argumentos    Instala JDK 21 + Gradle 8.14.3 + Android SDK 36 (idempotente)
--check           Solo verifica, no instala
--force           Reinstala desde cero
--help            Esta ayuda

Variables de entorno configurables:
  WAVE_TOOLCHAIN_DIR  (default: \$HOME/wave-toolchain)

Despues de instalar, hacer:
  source \$WAVE_TOOLCHAIN_DIR/env.sh
USAGE
      exit 0 ;;
  esac

  log "WAVE_TOOLCHAIN_DIR=$WAVE_TOOLCHAIN_DIR"

  install_jdk         || { err "fallo JDK";         exit 1; }
  install_gradle      || { err "fallo Gradle";      exit 2; }
  install_android_sdk || { err "fallo Android SDK"; exit 3; }

  write_env_sh

  ok "toolchain COMPLETO"
  log "para activar el entorno en tu shell: source $WAVE_TOOLCHAIN_DIR/env.sh"
}

main "$@"

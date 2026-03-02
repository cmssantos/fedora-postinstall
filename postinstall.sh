#!/usr/bin/env bash
# =============================================================================
# Fedora 43 — Pós-instalação VAIO FE15
# Intel Core i5/i7 11ª/12ª Gen · Intel Iris Xe
#
# Funcionalidades:
#   - Inibe suspend/sleep durante toda a execução (systemd-inhibit)
#   - Retomada automática por etapa  → /tmp/.postinstall_step
#   - Log completo com timestamp     → /tmp/postinstall.log
#   - Controle real de falhas        → resumo final com ✅ / ❌ por etapa
#   - --skip-broken em todos os dnf install
#
# Etapas:
#    1.  Otimização do DNF5
#    2.  Atualização do sistema
#    3.  RPM Fusion
#    4.  Codecs e multimídia
#    5.  Drivers Intel Iris Xe
#    6.  Gerenciamento de energia (TLP + tuned)
#    7.  Hardware (Wi-Fi, Bluetooth, Suspend)
#    8.  GNOME
#    9.  Pacotes essenciais + Google Chrome
#   10.  Fontes de desenvolvimento e sistema
#   11.  Ambiente de desenvolvimento (.NET · VS Code · ferramentas)
#   12.  Flathub + apps Flatpak
#   13.  Snapper — snapshots Btrfs via DNF5 Actions plugin
#   14.  Firewall
#   15.  Zsh + Oh My Zsh
#   16.  Podman (Docker-compatible)
# =============================================================================

set -uo pipefail

# =============================================================================
# CONFIGURAÇÃO GLOBAL
# =============================================================================

readonly LOG_FILE="/tmp/postinstall.log"
readonly STEP_FILE="/tmp/.postinstall_step"
readonly STATUS_FILE="/tmp/.postinstall_status"
readonly TOTAL_STEPS=16

# Cores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# =============================================================================
# HELPERS
# =============================================================================

_log()    { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; _log "INFO:  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; _log "OK:    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; _log "AVISO: $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*"; _log "ERRO:  $*"; }

section() {
  local step="$1"; shift
  echo -e "\n${BOLD}${CYAN}━━━ [${step}/${TOTAL_STEPS}] $* ━━━${NC}"
  _log ""; _log "══════ ETAPA ${step}/${TOTAL_STEPS}: $* ══════"
}

# Progresso
save_step()  { echo "$1" > "$STEP_FILE"; }
last_step()  { [[ -f "$STEP_FILE" ]] && cat "$STEP_FILE" || echo "0"; }
should_run() { local last; last=$(last_step); [[ "$1" -gt "$last" ]]; }

# Status por etapa
mark_ok()   { echo "${1}|${2}|ok|${3:-}"   >> "$STATUS_FILE"; }
mark_fail() { echo "${1}|${2}|fail|${3:-}" >> "$STATUS_FILE"; }

# dnf install com --skip-broken e rastreamento
dnf_install() {
  local desc="$1"; shift
  info "Instalando: $desc"
  if sudo dnf install -y --skip-broken "$@" 2>&1 | tee -a "$LOG_FILE"; then
    _log "dnf OK: $desc"; return 0
  else
    warn "dnf teve problemas: $desc"; return 1
  fi
}

# gsettings com rastreamento de erro (usa variável STEP_ERRORS do escopo pai)
apply_gsetting() {
  local schema="$1" key="$2" value="$3"
  if gsettings set "$schema" "$key" "$value" 2>&1 | tee -a "$LOG_FILE"; then
    _log "gsettings OK: $schema $key = $value"
  else
    warn "gsettings falhou: $schema $key"
    STEP_ERRORS=$((STEP_ERRORS + 1))
  fi
}

# =============================================================================
# VERIFICAÇÕES INICIAIS
# =============================================================================

if [[ $EUID -eq 0 ]]; then
  echo -e "${RED}[ERRO]${NC} Não execute como root. Use um usuário comum com sudo."
  exit 1
fi

if ! command -v dnf &>/dev/null; then
  echo -e "${RED}[ERRO]${NC} Este script requer dnf (Fedora/RHEL)."
  exit 1
fi

# Inibe suspend/sleep/idle durante toda a execução.
# Re-executa o próprio script sob systemd-inhibit na primeira vez.
if [[ -z "${INHIBITED:-}" ]]; then
  if command -v systemd-inhibit &>/dev/null; then
    echo -e "${BLUE}[INFO]${NC}  Bloqueando suspend/sleep durante a instalação..."
    exec systemd-inhibit \
      --what="sleep:idle:handle-lid-switch" \
      --who="fedora43-postinstall" \
      --why="Instalação em andamento — não suspender" \
      --mode="block" \
      env INHIBITED=1 bash "$0" "$@"
  else
    echo -e "${YELLOW}[AVISO]${NC} systemd-inhibit não encontrado — suspend não será bloqueado"
  fi
fi

# Inicializa arquivos de controle
{
  echo "=================================================="
  echo " Fedora 43 Pós-instalação — $(date)"
  echo "=================================================="
} >> "$LOG_FILE"

[[ -f "$STATUS_FILE" ]] || touch "$STATUS_FILE"

# =============================================================================
# CABEÇALHO
# =============================================================================

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   Fedora 43 — Pós-instalação VAIO FE15               ║"
echo "  ║   Intel Iris Xe · .NET · GNOME · Zsh · Podman        ║"
echo "  ╠══════════════════════════════════════════════════════╣"
printf "  ║  📄 Log:       %-37s║\n" "$LOG_FILE"
printf "  ║  🔖 Progresso: %-37s║\n" "$STEP_FILE"
printf "  ║  📋 Etapas:    %-37s║\n" "$TOTAL_STEPS etapas no total"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

LAST=$(last_step)
if [[ "$LAST" -gt 0 ]]; then
  warn "Progresso anterior: etapas 1–${LAST} já concluídas."
  warn "Retomando da etapa $((LAST + 1))..."
  echo ""
  read -rp "  Pressione ENTER para continuar ou Ctrl+C para cancelar..."
else
  read -rp "  Pressione ENTER para iniciar ou Ctrl+C para cancelar..."
fi
echo ""

# =============================================================================
# ETAPA 1 — OTIMIZAÇÃO DO DNF5
# =============================================================================
if should_run 1; then
  section 1 "Otimizando DNF5"
  STEP_ERRORS=0

  DNF_CONF="/etc/dnf/dnf.conf"

  # max_parallel_downloads — padrão é 3, aumentar para 10 acelera muito
  if ! grep -q "^max_parallel_downloads" "$DNF_CONF" 2>/dev/null; then
    echo "max_parallel_downloads=10" | sudo tee -a "$DNF_CONF" > /dev/null \
      && success "max_parallel_downloads=10 configurado" \
      || { warn "Falha ao configurar max_parallel_downloads"; STEP_ERRORS=$((STEP_ERRORS+1)); }
  else
    sudo sed -i 's/^max_parallel_downloads=.*/max_parallel_downloads=10/' "$DNF_CONF"
    info "max_parallel_downloads já existia — atualizado para 10"
  fi

  # fastestmirror — seleciona o espelho mais rápido automaticamente
  if ! grep -q "^fastestmirror" "$DNF_CONF" 2>/dev/null; then
    echo "fastestmirror=True" | sudo tee -a "$DNF_CONF" > /dev/null \
      && success "fastestmirror=True configurado" \
      || { warn "Falha ao configurar fastestmirror"; STEP_ERRORS=$((STEP_ERRORS+1)); }
  else
    info "fastestmirror já configurado"
  fi

  _log "Conteúdo de $DNF_CONF:"
  grep -E "max_parallel|fastestmirror|keepcache" "$DNF_CONF" | tee -a "$LOG_FILE" || true

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 1 "Otimização DNF5"
  else
    mark_fail 1 "Otimização DNF5" "falha ao editar dnf.conf"
  fi
  save_step 1
fi

# =============================================================================
# ETAPA 2 — ATUALIZAÇÃO DO SISTEMA
# =============================================================================
if should_run 2; then
  section 2 "Atualizando o sistema"
  STEP_ERRORS=0

  if sudo dnf upgrade --refresh -y 2>&1 | tee -a "$LOG_FILE"; then
    success "Sistema atualizado"
    mark_ok 2 "Atualização do sistema"
  else
    warn "dnf upgrade retornou erro — verifique o log"
    mark_fail 2 "Atualização do sistema" "dnf upgrade com erro"
    STEP_ERRORS=1
  fi
  save_step 2
fi

# =============================================================================
# ETAPA 3 — RPM FUSION
# =============================================================================
if should_run 3; then
  section 3 "Habilitando RPM Fusion"
  STEP_ERRORS=0
  FEDORA_VERSION=$(rpm -E %fedora)

  if ! rpm -q rpmfusion-free-release &>/dev/null; then
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" \
      2>&1 | tee -a "$LOG_FILE" || STEP_ERRORS=$((STEP_ERRORS+1))
  else
    info "RPM Fusion já está instalado"
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "RPM Fusion habilitado"
    mark_ok 3 "RPM Fusion"
  else
    mark_fail 3 "RPM Fusion" "falha ao instalar repositórios"
  fi
  save_step 3
fi

# =============================================================================
# ETAPA 4 — CODECS E MULTIMÍDIA
# =============================================================================
if should_run 4; then
  section 4 "Instalando codecs e multimídia"
  STEP_ERRORS=0

  # swap ffmpeg-free → ffmpeg completo (RPM Fusion)
  if sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>&1 | tee -a "$LOG_FILE"; then
    success "ffmpeg completo instalado"
  else
    warn "swap ffmpeg falhou — pode já estar instalado ou RPM Fusion ainda não disponível"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  dnf_install "codecs GStreamer + multimídia" \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-free-extras \
    gstreamer1-plugins-good \
    gstreamer1-plugins-base \
    gstreamer1-plugin-openh264 \
    gstreamer1-vaapi \
    lame \
    x264 \
    x265 \
    opus-tools || STEP_ERRORS=$((STEP_ERRORS+1))

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "Codecs instalados"
    mark_ok 4 "Codecs e multimídia"
  else
    mark_fail 4 "Codecs e multimídia" "alguns pacotes falharam"
  fi
  save_step 4
fi

# =============================================================================
# ETAPA 5 — DRIVERS INTEL IRIS XE
# =============================================================================
if should_run 5; then
  section 5 "Configurando drivers Intel Iris Xe"
  STEP_ERRORS=0

  dnf_install "drivers Intel Iris Xe + Vulkan" \
    intel-media-driver \
    libva-intel-driver \
    libva-utils \
    mesa-dri-drivers \
    mesa-vulkan-drivers \
    vulkan-tools \
    intel-gpu-tools || STEP_ERRORS=$((STEP_ERRORS+1))

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "Drivers Intel Iris Xe instalados"
    if command -v vainfo &>/dev/null; then
      info "Verificando VA-API:"
      vainfo 2>&1 | grep -E "VA-API|profile" | head -5 | tee -a "$LOG_FILE" || true
    fi
    mark_ok 5 "Drivers Intel Iris Xe"
  else
    mark_fail 5 "Drivers Intel Iris Xe" "falha ao instalar drivers"
  fi
  save_step 5
fi

# =============================================================================
# ETAPA 6 — GERENCIAMENTO DE ENERGIA (TLP + tuned)
# =============================================================================
if should_run 6; then
  section 6 "Configurando gerenciamento de energia (TLP + tuned)"
  STEP_ERRORS=0

  dnf_install "TLP" tlp tlp-rdw || STEP_ERRORS=$((STEP_ERRORS+1))

  if sudo systemctl enable --now tlp 2>&1 | tee -a "$LOG_FILE"; then
    success "TLP ativo"
  else
    warn "Falha ao ativar TLP"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  # power-profiles-daemon conflita com TLP — mascarar
  sudo systemctl mask power-profiles-daemon 2>/dev/null | tee -a "$LOG_FILE" || true

  dnf_install "tuned" tuned tuned-utils || STEP_ERRORS=$((STEP_ERRORS+1))

  if sudo systemctl enable --now tuned 2>&1 | tee -a "$LOG_FILE"; then
    sudo tuned-adm profile balanced 2>&1 | tee -a "$LOG_FILE" || true
    ACTIVE_PROFILE=$(sudo tuned-adm active 2>/dev/null | awk '{print $NF}' || echo "desconhecido")
    success "tuned ativo — perfil: ${ACTIVE_PROFILE}"
    info "Para maior performance: sudo tuned-adm profile throughput-performance"
    info "Para máxima economia:   sudo tuned-adm profile powersave"
  else
    warn "Falha ao ativar tuned"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 6 "Gerenciamento de energia (TLP + tuned)"
  else
    mark_fail 6 "Gerenciamento de energia" "TLP ou tuned com problemas"
  fi
  save_step 6
fi

# =============================================================================
# ETAPA 7 — HARDWARE (Wi-Fi, Bluetooth, Suspend)
# =============================================================================
if should_run 7; then
  section 7 "Configurando hardware (Wi-Fi, Bluetooth, Suspend)"
  STEP_ERRORS=0

  dnf_install "firmware Intel Wi-Fi + Bluetooth" \
    iwl7260-firmware \
    iwl8000-firmware \
    iwl3160-firmware \
    iwl5000-firmware \
    alsa-utils \
    alsa-firmware \
    bluez \
    bluez-tools || STEP_ERRORS=$((STEP_ERRORS+1))

  # Suspend ao fechar a tampa
  LOGIND_CONF="/etc/systemd/logind.conf"
  if grep -q "^#HandleLidSwitch=" "$LOGIND_CONF" 2>/dev/null; then
    sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' "$LOGIND_CONF" \
      && success "HandleLidSwitch=suspend configurado" \
      || { warn "Falha ao configurar HandleLidSwitch"; STEP_ERRORS=$((STEP_ERRORS+1)); }
  elif ! grep -q "^HandleLidSwitch=" "$LOGIND_CONF" 2>/dev/null; then
    echo "HandleLidSwitch=suspend" | sudo tee -a "$LOGIND_CONF" > /dev/null \
      && success "HandleLidSwitch=suspend adicionado" \
      || { warn "Falha ao adicionar HandleLidSwitch"; STEP_ERRORS=$((STEP_ERRORS+1)); }
  else
    info "HandleLidSwitch já configurado"
  fi

  sudo systemctl restart systemd-logind 2>&1 | tee -a "$LOG_FILE" || true

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "Hardware configurado"
    mark_ok 7 "Hardware (Wi-Fi, Bluetooth, Suspend)"
  else
    mark_fail 7 "Hardware" "alguns itens com falha"
  fi
  save_step 7
fi

# =============================================================================
# ETAPA 8 — GNOME
# =============================================================================
if should_run 8; then
  section 8 "Ajustando GNOME"
  STEP_ERRORS=0

  dnf_install "GNOME extras" \
    gnome-tweaks \
    gnome-extensions-app \
    dconf-editor \
    gnome-shell-extension-appindicator || STEP_ERRORS=$((STEP_ERRORS+1))

  # Aparência e usabilidade
  apply_gsetting org.gnome.desktop.wm.preferences      button-layout           'appmenu:minimize,maximize,close'
  apply_gsetting org.gnome.desktop.peripherals.keyboard numlock-state           true
  apply_gsetting org.gnome.desktop.interface            show-battery-percentage true
  apply_gsetting org.gnome.desktop.interface            clock-show-weekday      true
  apply_gsetting org.gnome.desktop.interface            clock-show-seconds      false
  apply_gsetting org.gnome.desktop.interface            color-scheme            'prefer-dark'

  # Night Light (reduz luz azul à noite — bom para os olhos durante dev)
  apply_gsetting org.gnome.settings-daemon.plugins.color night-light-enabled    true
  apply_gsetting org.gnome.settings-daemon.plugins.color night-light-temperature 4000

  # Touchpad
  apply_gsetting org.gnome.desktop.peripherals.touchpad tap-to-click            true
  apply_gsetting org.gnome.desktop.peripherals.touchpad natural-scroll          false
  apply_gsetting org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "GNOME configurado"
    mark_ok 8 "GNOME"
  else
    mark_fail 8 "GNOME" "alguns gsettings falharam (verifique o log)"
  fi
  save_step 8
fi

# =============================================================================
# ETAPA 9 — PACOTES ESSENCIAIS + GOOGLE CHROME
# =============================================================================
if should_run 9; then
  section 9 "Instalando pacotes essenciais e Google Chrome"
  STEP_ERRORS=0

  dnf_install "utilitários essenciais" \
    git \
    curl \
    wget \
    vim \
    neovim \
    htop \
    btop \
    p7zip \
    p7zip-plugins \
    unrar \
    fastfetch \
    file-roller \
    gnome-disk-utility \
    timeshift \
    xclip \
    xdotool \
    tree \
    fd-find \
    ripgrep \
    bat \
    fzf || STEP_ERRORS=$((STEP_ERRORS+1))

  dnf_install "multimídia e produtividade" \
    vlc \
    gimp \
    libreoffice \
    libreoffice-langpack-pt-BR \
    evince \
    rhythmbox \
    transmission-gtk || STEP_ERRORS=$((STEP_ERRORS+1))

  # Google Chrome
  if ! command -v google-chrome-stable &>/dev/null && ! command -v google-chrome &>/dev/null; then
    info "Adicionando repositório Google Chrome..."
    sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub \
      2>&1 | tee -a "$LOG_FILE" || STEP_ERRORS=$((STEP_ERRORS+1))

    sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null << 'CHROMEREPO'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
CHROMEREPO

    dnf_install "Google Chrome" google-chrome-stable || STEP_ERRORS=$((STEP_ERRORS+1))

    if command -v google-chrome-stable &>/dev/null || command -v google-chrome &>/dev/null; then
      success "Google Chrome instalado"
    else
      warn "Google Chrome não encontrado após instalação"
      STEP_ERRORS=$((STEP_ERRORS+1))
    fi
  else
    info "Google Chrome já está instalado"
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 9 "Pacotes essenciais + Google Chrome"
  else
    mark_fail 9 "Pacotes essenciais + Google Chrome" "alguns pacotes falharam"
  fi
  save_step 9
fi

# =============================================================================
# ETAPA 10 — FONTES
# =============================================================================
if should_run 10; then
  section 10 "Instalando fontes de desenvolvimento e sistema"
  STEP_ERRORS=0

  # Dependências para instalação de fontes
  dnf_install "dependências de fontes" \
    fontconfig \
    cabextract \
    xorg-x11-font-utils || STEP_ERRORS=$((STEP_ERRORS+1))

  # Fontes disponíveis nos repositórios Fedora/RPM Fusion
  dnf_install "fontes via repositório" \
    fira-code-fonts \
    mozilla-fira-mono-fonts \
    google-roboto-fonts \
    google-noto-fonts-common \
    google-noto-emoji-fonts \
    liberation-fonts \
    adobe-source-code-pro-fonts \
    adobe-source-sans-pro-fonts \
    adobe-source-serif-pro-fonts || STEP_ERRORS=$((STEP_ERRORS+1))

  # Microsoft Core Fonts (Arial, Times New Roman, etc.) — via RPM Fusion nonfree
  if ! dnf_install "Microsoft Core Fonts" mscore-fonts-all; then
    warn "mscore-fonts-all indisponível — pulando (requer RPM Fusion nonfree)"
  fi

  # Fonte Inter — não está nos repos, instalar via release oficial
  FONTS_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONTS_DIR"

  if ! fc-list | grep -qi "inter"; then
    info "Instalando fonte Inter..."
    INTER_URL="https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
    INTER_TMP=$(mktemp -d)
    if curl -fsSL "$INTER_URL" -o "${INTER_TMP}/inter.zip" 2>&1 | tee -a "$LOG_FILE"; then
      unzip -q "${INTER_TMP}/inter.zip" -d "${INTER_TMP}/inter" 2>/dev/null || true
      find "${INTER_TMP}/inter" -name "*.ttf" -o -name "*.otf" | \
        xargs -I{} cp {} "$FONTS_DIR/" 2>/dev/null || true
      rm -rf "$INTER_TMP"
      success "Fonte Inter instalada"
    else
      warn "Falha ao baixar Inter — verifique conexão"
      rm -rf "$INTER_TMP"
    fi
  else
    info "Fonte Inter já instalada"
  fi

  # JetBrains Mono — não está nos repos, instalar via release oficial
  if ! fc-list | grep -qi "jetbrains mono"; then
    info "Instalando JetBrains Mono..."
    JB_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip"
    JB_TMP=$(mktemp -d)
    if curl -fsSL "$JB_URL" -o "${JB_TMP}/jb.zip" 2>&1 | tee -a "$LOG_FILE"; then
      unzip -q "${JB_TMP}/jb.zip" -d "${JB_TMP}/jb" 2>/dev/null || true
      find "${JB_TMP}/jb/fonts" -name "*.ttf" 2>/dev/null | \
        xargs -I{} cp {} "$FONTS_DIR/" 2>/dev/null || \
        find "${JB_TMP}/jb" -name "*.ttf" | xargs -I{} cp {} "$FONTS_DIR/" 2>/dev/null || true
      rm -rf "$JB_TMP"
      success "JetBrains Mono instalado"
    else
      warn "Falha ao baixar JetBrains Mono"
      rm -rf "$JB_TMP"
    fi
  else
    info "JetBrains Mono já instalado"
  fi

  # JetBrains Mono Nerd Font — versão com ícones (essencial para terminal/Zsh)
  if ! fc-list | grep -qi "jetbrainsmono nerd"; then
    info "Instalando JetBrains Mono Nerd Font..."
    NERD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip"
    NERD_TMP=$(mktemp -d)
    if curl -fsSL "$NERD_URL" -o "${NERD_TMP}/nerd.zip" 2>&1 | tee -a "$LOG_FILE"; then
      unzip -q "${NERD_TMP}/nerd.zip" -d "${NERD_TMP}/nerd" 2>/dev/null || true
      # Instalar apenas Regular e Bold para não poluir demais
      find "${NERD_TMP}/nerd" -name "*Regular*" -o -name "*Bold*" -o -name "*Mono*" | \
        grep -E "\.(ttf|otf)$" | xargs -I{} cp {} "$FONTS_DIR/" 2>/dev/null || \
        find "${NERD_TMP}/nerd" -name "*.ttf" | head -20 | xargs -I{} cp {} "$FONTS_DIR/" 2>/dev/null || true
      rm -rf "$NERD_TMP"
      success "JetBrains Mono Nerd Font instalado"
    else
      warn "Falha ao baixar Nerd Font"
      rm -rf "$NERD_TMP"
    fi
  else
    info "JetBrains Mono Nerd Font já instalado"
  fi

  # Atualiza cache de fontes
  fc-cache -fv "$FONTS_DIR" 2>&1 | tee -a "$LOG_FILE" || true
  sudo fc-cache -fv 2>&1 | tee -a "$LOG_FILE" || true

  # Renderização GNOME — antialiasing e hinting otimizados
  apply_gsetting org.gnome.desktop.interface font-antialiasing 'rgba'
  apply_gsetting org.gnome.desktop.interface font-hinting      'slight'

  # Fontes padrão do sistema (Interface → Inter, Monospace → JetBrains Mono)
  if fc-list | grep -qi "inter"; then
    apply_gsetting org.gnome.desktop.interface font-name          'Inter 11'
    apply_gsetting org.gnome.desktop.interface document-font-name 'Inter 11'
  fi
  if fc-list | grep -qi "jetbrains mono"; then
    apply_gsetting org.gnome.desktop.interface monospace-font-name 'JetBrains Mono 12'
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "Fontes instaladas e renderização configurada"
    mark_ok 10 "Fontes (Inter · JetBrains Mono · Nerd · Source Code Pro)"
  else
    mark_fail 10 "Fontes" "alguns itens falharam"
  fi
  save_step 10
fi

# =============================================================================
# ETAPA 11 — AMBIENTE DE DESENVOLVIMENTO
# =============================================================================
if should_run 11; then
  section 11 "Instalando ambiente de desenvolvimento"
  STEP_ERRORS=0

  # Build tools e utilitários dev
  sudo dnf groupinstall -y "Development Tools" 2>&1 | tee -a "$LOG_FILE" \
    || STEP_ERRORS=$((STEP_ERRORS+1))

  dnf_install "ferramentas de desenvolvimento" \
    make \
    cmake \
    ninja-build \
    gcc \
    gcc-c++ \
    gdb \
    strace \
    ltrace \
    valgrind \
    jq \
    yq \
    httpie \
    gh \
    sqlite \
    sqlite-devel \
    openssl \
    openssl-devel \
    zlib-devel \
    readline-devel || STEP_ERRORS=$((STEP_ERRORS+1))

  # .NET SDK 9
  info "Instalando .NET SDK 9..."
  dnf_install ".NET SDK 9" dotnet-sdk-9.0 || STEP_ERRORS=$((STEP_ERRORS+1))

  if command -v dotnet &>/dev/null; then
    DOTNET_VER=$(dotnet --version 2>/dev/null || echo "instalado")
    success ".NET instalado: ${DOTNET_VER}"
    # Telemetria do .NET — desabilitar
    if ! grep -q "DOTNET_CLI_TELEMETRY_OPTOUT" "$HOME/.bashrc" 2>/dev/null; then
      echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >> "$HOME/.bashrc"
      _log "DOTNET_CLI_TELEMETRY_OPTOUT=1 adicionado ao .bashrc"
    fi
  else
    warn ".NET não encontrado no PATH após instalação"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  # VS Code
  if ! command -v code &>/dev/null; then
    info "Adicionando repositório VS Code..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc \
      2>&1 | tee -a "$LOG_FILE" || STEP_ERRORS=$((STEP_ERRORS+1))

    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null << 'VSCODEREPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
VSCODEREPO

    dnf_install "VS Code" code || STEP_ERRORS=$((STEP_ERRORS+1))
  else
    info "VS Code já está instalado"
  fi

  # Extensões VS Code
  if command -v code &>/dev/null; then
    info "Instalando extensões do VS Code..."
    EXTENSIONS_FAILED=0

    declare -A VSCODE_EXT=(
      # C# / .NET
      ["ms-dotnettools.csharp"]="C# (OmniSharp)"
      ["ms-dotnettools.csdevkit"]="C# Dev Kit"
      ["ms-dotnettools.vscode-dotnet-runtime"]=".NET Runtime"
      ["formulahendry.dotnet-test-explorer"]="Test Explorer"
      # Qualidade de código
      ["editorconfig.editorconfig"]="EditorConfig"
      ["streetsidesoftware.code-spell-checker"]="Spell Checker"
      ["usernamehw.errorlens"]="Error Lens (inline errors)"
      ["sonarsource.sonarlint-vscode"]="SonarLint"
      # Git
      ["eamodio.gitlens"]="GitLens"
      ["mhutchie.git-graph"]="Git Graph"
      # Produtividade
      ["ms-vscode.live-server"]="Live Server"
      ["christian-kohler.path-intellisense"]="Path IntelliSense"
      ["pkief.material-icon-theme"]="Material Icon Theme"
      ["zhuangtongfa.material-theme"]="One Dark Pro"
      # Docker / Containers
      ["ms-azuretools.vscode-docker"]="Docker"
      # REST / API
      ["humao.rest-client"]="REST Client"
      # YAML / JSON / TOML
      ["redhat.vscode-yaml"]="YAML"
      ["tamasfe.even-better-toml"]="TOML"
      # Markdown
      ["yzhang.markdown-all-in-one"]="Markdown All in One"
    )

    for ext in "${!VSCODE_EXT[@]}"; do
      if code --install-extension "$ext" --force 2>&1 | tee -a "$LOG_FILE"; then
        _log "Extensão OK: ${VSCODE_EXT[$ext]}"
      else
        warn "Falha: ${VSCODE_EXT[$ext]} ($ext)"
        EXTENSIONS_FAILED=$((EXTENSIONS_FAILED+1))
      fi
    done

    if [[ $EXTENSIONS_FAILED -eq 0 ]]; then
      success "Todas as extensões VS Code instaladas"
    else
      warn "${EXTENSIONS_FAILED} extensão(ões) falharam — instale manualmente"
      STEP_ERRORS=$((STEP_ERRORS+1))
    fi
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 11 "Ambiente de desenvolvimento (.NET · VS Code · ferramentas)"
  else
    mark_fail 11 "Ambiente de desenvolvimento" "${STEP_ERRORS} item(ns) com falha"
  fi
  save_step 11
fi

# =============================================================================
# ETAPA 12 — FLATHUB + APPS FLATPAK
# =============================================================================
if should_run 12; then
  section 12 "Configurando Flathub + apps Flatpak"
  STEP_ERRORS=0

  if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
      2>&1 | tee -a "$LOG_FILE"; then
    success "Flathub configurado"
  else
    warn "Falha ao configurar Flathub"
    mark_fail 12 "Flathub" "flatpak remote-add falhou"
    STEP_ERRORS=1
    save_step 12
    # Não instala apps se Flathub falhou
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    # Apps úteis via Flathub (que não têm boa versão RPM ou precisam de sandbox)
    FLATPAK_APPS=(
      "com.discordapp.Discord"          # Discord
      "org.telegram.desktop"            # Telegram
      "com.spotify.Client"              # Spotify
      "com.obsproject.Studio"           # OBS Studio
      "org.flameshot.Flameshot"         # Screenshots
      "com.github.flxzt.rnote"          # Notas/desenho
      "io.github.flattool.Warehouse"    # Gerenciar Flatpaks
    )

    info "Instalando apps via Flathub..."
    FLATPAK_FAILED=0
    for app in "${FLATPAK_APPS[@]}"; do
      app_id="${app%%#*}"
      if flatpak install -y flathub "$app_id" 2>&1 | tee -a "$LOG_FILE"; then
        _log "Flatpak OK: $app_id"
      else
        warn "Flatpak falhou: $app_id"
        FLATPAK_FAILED=$((FLATPAK_FAILED+1))
      fi
    done

    if [[ $FLATPAK_FAILED -eq 0 ]]; then
      success "Apps Flatpak instalados"
      mark_ok 12 "Flathub + apps Flatpak"
    else
      warn "${FLATPAK_FAILED} app(s) Flatpak falharam"
      mark_fail 12 "Flathub + apps Flatpak" "${FLATPAK_FAILED} apps falharam"
    fi
  fi
  save_step 12
fi

# =============================================================================
# ETAPA 13 — SNAPPER (snapshots Btrfs via DNF5 Actions)
# =============================================================================
if should_run 13; then
  section 13 "Configurando Snapper (snapshots Btrfs — DNF5 Actions)"
  STEP_ERRORS=0

  ROOT_FS=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "desconhecido")

  if [[ "$ROOT_FS" != "btrfs" ]]; then
    warn "Filesystem raiz não é Btrfs (detectado: ${ROOT_FS}) — pulando Snapper."
    mark_fail 13 "Snapper" "filesystem raiz não é Btrfs (é: ${ROOT_FS})"
  else
    # snap-pac é para Arch/Pacman e NÃO funciona no Fedora.
    # python3-dnf-plugin-snapper é para DNF4 e NÃO funciona no DNF5 (Fedora 41+).
    # Solução correta: libdnf5-plugin-actions + snapper.actions
    dnf_install "Snapper + DNF5 Actions plugin" \
      snapper \
      btrfs-assistant \
      libdnf5-plugin-actions || STEP_ERRORS=$((STEP_ERRORS+1))

    # Criar configuração para /
    if ! snapper -c root list &>/dev/null 2>&1; then
      sudo snapper -c root create-config / 2>&1 | tee -a "$LOG_FILE" \
        || STEP_ERRORS=$((STEP_ERRORS+1))
      success "Configuração snapper para / criada"
    else
      info "Configuração snapper para / já existe"
    fi

    # Limites de retenção
    sudo snapper -c root set-config \
      NUMBER_LIMIT=10 \
      NUMBER_LIMIT_IMPORTANT=5 \
      TIMELINE_CREATE=yes \
      TIMELINE_LIMIT_HOURLY=3 \
      TIMELINE_LIMIT_DAILY=7 \
      TIMELINE_LIMIT_WEEKLY=2 \
      TIMELINE_LIMIT_MONTHLY=1 \
      TIMELINE_LIMIT_YEARLY=0 \
      2>&1 | tee -a "$LOG_FILE" || STEP_ERRORS=$((STEP_ERRORS+1))

    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer \
      2>&1 | tee -a "$LOG_FILE" || STEP_ERRORS=$((STEP_ERRORS+1))

    # Arquivo de actions para DNF5 — cria snapshots pre/post em cada transação dnf
    ACTIONS_DIR="/etc/dnf/libdnf5-plugins/actions.d"
    ACTIONS_FILE="${ACTIONS_DIR}/snapper.actions"

    if [[ ! -f "$ACTIONS_FILE" ]]; then
      sudo mkdir -p "$ACTIONS_DIR"
      sudo tee "$ACTIONS_FILE" > /dev/null << 'SNAPACTIONS'
# Snapper pre/post snapshots para DNF5
# Substitui python3-dnf-plugin-snapper (DNF4) — compatível com Fedora 41+ / DNF5

# Captura o comando dnf que está sendo executado
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"

# Cria snapshot PRE antes da transação
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '${tmp.cmd}')"

# Cria snapshot POST após a transação (somente se PRE foi criado com sucesso)
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -c\ number\ -d\ "${tmp.cmd}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.cmd
SNAPACTIONS
      success "snapper.actions criado — snapshots pre/post automáticos em cada dnf"
    else
      info "snapper.actions já existe"
    fi

    if [[ $STEP_ERRORS -eq 0 ]]; then
      success "Snapper configurado com DNF5 Actions"
      mark_ok 13 "Snapper (Btrfs · DNF5 Actions)"
    else
      mark_fail 13 "Snapper" "erro na configuração"
    fi
  fi
  save_step 13
fi

# =============================================================================
# ETAPA 14 — FIREWALL
# =============================================================================
if should_run 14; then
  section 14 "Configurando Firewall"
  STEP_ERRORS=0

  if ! sudo systemctl is-active --quiet firewalld; then
    sudo systemctl enable --now firewalld 2>&1 | tee -a "$LOG_FILE" \
      || STEP_ERRORS=$((STEP_ERRORS+1))
  else
    info "firewalld já está ativo"
  fi

  DEFAULT_ZONE=$(sudo firewall-cmd --get-default-zone 2>/dev/null || echo "desconhecida")
  info "Zona padrão: ${DEFAULT_ZONE}"

  # Portas para desenvolvimento ASP.NET
  for port in 5000/tcp 5001/tcp 7000/tcp 7001/tcp 8080/tcp 8443/tcp; do
    sudo firewall-cmd --permanent --add-port="$port" 2>&1 | tee -a "$LOG_FILE" || true
  done

  # Serviços padrão
  for svc in ssh mdns; do
    sudo firewall-cmd --permanent --add-service="$svc" 2>&1 | tee -a "$LOG_FILE" || true
  done

  if sudo firewall-cmd --reload 2>&1 | tee -a "$LOG_FILE"; then
    success "Firewall configurado (portas ASP.NET abertas para dev local)"
  else
    warn "Falha ao recarregar firewall"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 14 "Firewall"
  else
    mark_fail 14 "Firewall" "erro ao configurar regras"
  fi
  save_step 14
fi

# =============================================================================
# ETAPA 15 — ZSH + OH MY ZSH
# =============================================================================
if should_run 15; then
  section 15 "Instalando Zsh + Oh My Zsh"
  STEP_ERRORS=0

  dnf_install "Zsh" zsh util-linux-user || STEP_ERRORS=$((STEP_ERRORS+1))

  # Definir Zsh como shell padrão
  if command -v zsh &>/dev/null && [[ "$SHELL" != "$(command -v zsh)" ]]; then
    sudo chsh -s "$(command -v zsh)" "$USER" 2>&1 | tee -a "$LOG_FILE" \
      && success "Zsh definido como shell padrão para $USER" \
      || { warn "Falha ao definir Zsh como padrão"; STEP_ERRORS=$((STEP_ERRORS+1)); }
  else
    info "Zsh já é o shell padrão"
  fi

  # Oh My Zsh
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    if RUNZSH=no CHSH=no \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        2>&1 | tee -a "$LOG_FILE"; then
      success "Oh My Zsh instalado"
    else
      warn "Falha ao instalar Oh My Zsh"
      STEP_ERRORS=$((STEP_ERRORS+1))
    fi
  else
    info "Oh My Zsh já está instalado"
  fi

  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  # Plugins externos
  declare -A ZSH_PLUGINS=(
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
    ["zsh-completions"]="https://github.com/zsh-users/zsh-completions"
  )

  for plugin_name in "${!ZSH_PLUGINS[@]}"; do
    plugin_url="${ZSH_PLUGINS[$plugin_name]}"
    if [[ ! -d "${ZSH_CUSTOM}/plugins/${plugin_name}" ]]; then
      git clone --depth 1 "$plugin_url" "${ZSH_CUSTOM}/plugins/${plugin_name}" \
        2>&1 | tee -a "$LOG_FILE" \
        || { warn "Falha ao clonar: ${plugin_name}"; STEP_ERRORS=$((STEP_ERRORS+1)); }
    else
      info "Plugin já existe: ${plugin_name}"
    fi
  done

  # Tema Powerlevel10k (requer Nerd Font — instalada na etapa 10)
  if [[ ! -d "${ZSH_CUSTOM}/themes/powerlevel10k" ]]; then
    info "Instalando tema Powerlevel10k..."
    git clone --depth 1 https://github.com/romkatv/powerlevel10k.git \
      "${ZSH_CUSTOM}/themes/powerlevel10k" \
      2>&1 | tee -a "$LOG_FILE" \
      && success "Powerlevel10k instalado" \
      || warn "Falha ao instalar Powerlevel10k"
  else
    info "Powerlevel10k já instalado"
  fi

  # Configurar .zshrc
  if [[ -f "$HOME/.zshrc" ]]; then
    # Tema
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc" \
      || warn "Não foi possível definir tema no .zshrc"

    # Plugins
    sed -i 's/^plugins=(git)/plugins=(git dotnet dnf zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' \
      "$HOME/.zshrc" \
      || warn "Não foi possível atualizar plugins no .zshrc"

    # PATH do .NET e variáveis de ambiente
    if ! grep -q "DOTNET_ROOT" "$HOME/.zshrc"; then
      cat >> "$HOME/.zshrc" << 'ZSHENV'

# .NET
export DOTNET_ROOT=/usr/lib/dotnet
export PATH="$PATH:$HOME/.dotnet/tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1

# bat como substituto do cat (se disponível)
command -v bat &>/dev/null && alias cat='bat --paging=never'

# fd como substituto do find (se disponível)
command -v fd &>/dev/null && alias find='fd'

# fzf — busca fuzzy
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
ZSHENV
      _log "Variáveis de ambiente adicionadas ao .zshrc"
    fi
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    success "Zsh + Oh My Zsh + Powerlevel10k configurados"
    warn "Execute 'p10k configure' após o primeiro login no Zsh para configurar o tema"
    mark_ok 15 "Zsh + Oh My Zsh + Powerlevel10k"
  else
    mark_fail 15 "Zsh + Oh My Zsh" "${STEP_ERRORS} item(ns) com falha"
  fi
  save_step 15
fi

# =============================================================================
# ETAPA 16 — PODMAN (Docker-compatible)
# =============================================================================
if should_run 16; then
  section 16 "Configurando Podman (Docker-compatible)"
  STEP_ERRORS=0

  dnf_install "Podman + ferramentas de container" \
    podman \
    podman-compose \
    podman-tui \
    buildah \
    skopeo \
    containernetworking-plugins || STEP_ERRORS=$((STEP_ERRORS+1))

  # Socket Podman em modo usuário (compatibilidade com Docker API / VS Code Docker ext)
  systemctl --user enable --now podman.socket 2>&1 | tee -a "$LOG_FILE" || true

  # Alias docker → podman nos shells
  for rc_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$rc_file" ]] && ! grep -q "alias docker=" "$rc_file"; then
      cat >> "$rc_file" << 'PODMANALIASES'

# Podman como substituto do Docker
alias docker='podman'
alias docker-compose='podman-compose'
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
PODMANALIASES
      _log "Aliases docker=podman adicionados a $rc_file"
    fi
  done

  # Registro padrão Docker Hub
  if [[ ! -f /etc/containers/registries.conf.d/docker.conf ]]; then
    sudo tee /etc/containers/registries.conf.d/docker.conf > /dev/null << 'REGCONF'
[[registry]]
prefix = "docker.io"
location = "docker.io"
REGCONF
    _log "Registro Docker Hub configurado"
  fi

  if command -v podman &>/dev/null; then
    PODMAN_VER=$(podman --version | awk '{print $3}' 2>/dev/null || echo "instalado")
    success "Podman ${PODMAN_VER} instalado — alias docker=podman ativo"
  else
    warn "Podman não encontrado após instalação"
    STEP_ERRORS=$((STEP_ERRORS+1))
  fi

  if [[ $STEP_ERRORS -eq 0 ]]; then
    mark_ok 16 "Podman (Docker-compatible)"
  else
    mark_fail 16 "Podman" "erro na instalação ou configuração"
  fi
  save_step 16
fi

# =============================================================================
# RESUMO FINAL
# =============================================================================

echo ""
echo -e "${BOLD}${CYAN}  ════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}    RESUMO DA INSTALAÇÃO${NC}"
echo -e "${BOLD}${CYAN}  ════════════════════════════════════════════════════════${NC}"
echo ""

TOTAL_OK=0
TOTAL_FAIL=0

while IFS='|' read -r step_num step_name status msg; do
  if [[ "$status" == "ok" ]]; then
    echo -e "  ${GREEN}✅${NC}  Etapa ${step_num}: ${step_name}"
    TOTAL_OK=$((TOTAL_OK+1))
  else
    echo -e "  ${RED}❌${NC}  Etapa ${step_num}: ${step_name}"
    [[ -n "$msg" ]] && echo -e "       ${YELLOW}↳ ${msg}${NC}"
    TOTAL_FAIL=$((TOTAL_FAIL+1))
  fi
done < "$STATUS_FILE"

echo ""
echo -e "${BOLD}${CYAN}  ════════════════════════════════════════════════════════${NC}"

if [[ $TOTAL_FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✅  Concluído com sucesso! (${TOTAL_OK}/${TOTAL_STEPS} etapas)${NC}"
else
  echo -e "  ${YELLOW}${BOLD}⚠   ${TOTAL_OK} OK · ${TOTAL_FAIL} com falha${NC}"
  echo -e "  ${YELLOW}    Verifique os itens ❌ e o log:${NC}"
  echo -e "  ${YELLOW}    cat ${LOG_FILE}${NC}"
fi

echo ""
echo -e "  ${BOLD}Próximos passos após reiniciar:${NC}"
echo -e "  • Abrir terminal Zsh e executar ${CYAN}p10k configure${NC} para configurar o tema"
echo -e "  • Conferir fontes em VS Code: ${CYAN}JetBrains Mono${NC} ou ${CYAN}JetBrainsMono Nerd Font Mono${NC}"
echo -e "  • Verificar snapshots: ${CYAN}snapper ls${NC}"
echo -e "  • Verificar Podman: ${CYAN}podman info${NC}"
echo ""
echo -e "  📄 Log completo: ${LOG_FILE}"
echo -e "${BOLD}${CYAN}  ════════════════════════════════════════════════════════${NC}"
echo ""

# Remove arquivo de progresso somente se tudo OK
if [[ $TOTAL_FAIL -eq 0 ]]; then
  rm -f "$STEP_FILE"
  _log "Concluído sem erros. Arquivo de progresso removido."
else
  warn "Arquivo de progresso mantido para retomada: ${STEP_FILE}"
  _log "Concluído com ${TOTAL_FAIL} falha(s). Arquivo de progresso mantido."
fi

echo -e "${YELLOW}  ⚠  Reinicie o sistema para aplicar todas as mudanças.${NC}"
echo ""
read -rp "  Deseja reiniciar agora? [s/N] " RESPOSTA
if [[ "${RESPOSTA,,}" == "s" ]]; then
  info "Reiniciando em 5 segundos... (Ctrl+C para cancelar)"
  sleep 5
  sudo reboot
else
  info "Reinicie manualmente: sudo reboot"
fi

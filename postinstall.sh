#!/usr/bin/env bash
# =============================================================================
# Fedora 43 - Pós-instalação para VAIO FE15
# Intel Core i5/i7 11ª/12ª Gen + Intel Iris Xe
#
# Funcionalidades:
#   - Retomada automática por etapa (salva progresso em /tmp/.postinstall_step)
#   - Log completo em /tmp/postinstall.log
#   - --skip-broken nos installs dnf para maior resiliência
#
# Etapas:
#    1. Atualização do sistema
#    2. RPM Fusion
#    3. Codecs e multimídia
#    4. Drivers Intel Iris Xe
#    5. Gerenciamento de energia (TLP)
#    6. Tuned (Perfil de Performance)
#    7. Hardware (Wi-Fi, Bluetooth, Suspend)
#    8. GNOME
#    9. Desenvolvimento (.NET + VS Code + extensões C#)
#   10. Flathub
#   11. Snapper (snapshots Btrfs automáticos)
#   12. Firewall (verificação + perfil dev)
#   13. Fontes Microsoft + renderização
#   14. Zsh + Oh My Zsh
#   15. Docker / Podman
# =============================================================================

set -uo pipefail

# --- Arquivos de controle ---
LOG_FILE="/tmp/postinstall.log"
STEP_FILE="/tmp/.postinstall_step"
TOTAL_STEPS=15

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
_log()    { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info()    { echo -e "${BLUE}[INFO]${NC} $*";    _log "INFO:    $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*";   _log "OK:      $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; _log "AVISO:   $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*";    _log "ERRO:    $*"; }

section() {
  local step="$1"; shift
  echo -e "\n${BOLD}${CYAN}==> [${step}/${TOTAL_STEPS}] $*${NC}"
  _log "=== ETAPA ${step}/${TOTAL_STEPS}: $* ==="
}

# Salva a etapa atual no arquivo de progresso
save_step() { echo "$1" > "$STEP_FILE"; }

# Retorna a última etapa concluída (0 se nenhuma)
last_step() {
  if [[ -f "$STEP_FILE" ]]; then
    cat "$STEP_FILE"
  else
    echo "0"
  fi
}

# Wrapper para dnf install com --skip-broken e log
dnf_install() {
  info "dnf install: $*"
  sudo dnf install -y --skip-broken "$@" 2>&1 | tee -a "$LOG_FILE"
}

# Verifica se uma etapa deve ser executada
should_run() {
  local step="$1"
  local last
  last=$(last_step)
  [[ "$step" -gt "$last" ]]
}

# --- Verificações iniciais ---
if [[ $EUID -eq 0 ]]; then
  error "Não execute como root. Use um usuário comum com sudo."
  exit 1
fi

if ! command -v dnf &>/dev/null; then
  error "Este script requer dnf (Fedora/RHEL)."
  exit 1
fi

# Inicializa o log
echo "========================================" >> "$LOG_FILE"
echo " Fedora 43 Pós-instalação — $(date)    " >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# --- Cabeçalho ---
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║   Fedora 43 — Pós-instalação VAIO FE15               ║"
echo "║   Iris Xe | .NET | GNOME | Snapper | Zsh | Docker    ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║   Log: %-45s ║\n" "$LOG_FILE"
printf "║   Progresso: %-41s║\n" "$STEP_FILE"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

LAST=$(last_step)
if [[ "$LAST" -gt 0 ]]; then
  warn "Progresso anterior detectado: etapas 1–${LAST} já concluídas."
  warn "Retomando a partir da etapa $((LAST + 1))..."
  echo ""
  read -rp "Pressione ENTER para continuar ou Ctrl+C para cancelar..."
else
  read -rp "Pressione ENTER para iniciar ou Ctrl+C para cancelar..."
fi

# =============================================================================
# ETAPA 1 — ATUALIZAÇÃO DO SISTEMA
# =============================================================================
if should_run 1; then
  section 1 "Atualizando o sistema"
  sudo dnf upgrade --refresh -y 2>&1 | tee -a "$LOG_FILE"
  success "Sistema atualizado"
  save_step 1
fi

# =============================================================================
# ETAPA 2 — RPM FUSION
# =============================================================================
if should_run 2; then
  section 2 "Habilitando RPM Fusion"
  FEDORA_VERSION=$(rpm -E %fedora)

  if ! rpm -q rpmfusion-free-release &>/dev/null; then
    sudo dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" \
      2>&1 | tee -a "$LOG_FILE"
    success "RPM Fusion instalado"
  else
    info "RPM Fusion já está instalado"
  fi
  save_step 2
fi

# =============================================================================
# ETAPA 3 — CODECS E MULTIMÍDIA
# =============================================================================
if should_run 3; then
  section 3 "Instalando codecs e multimídia"

  sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing 2>&1 | tee -a "$LOG_FILE" || \
    warn "swap ffmpeg falhou — pode já estar instalado ou requer distro-sync"

  dnf_install \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-free-extras \
    gstreamer1-plugins-good \
    gstreamer1-plugins-base \
    gstreamer1-plugin-openh264 \
    lame

  success "Codecs instalados"
  save_step 3
fi

# =============================================================================
# ETAPA 4 — DRIVERS INTEL IRIS XE
# =============================================================================
if should_run 4; then
  section 4 "Configurando drivers Intel Iris Xe"

  dnf_install \
    intel-media-driver \
    libva-intel-driver \
    libva-utils \
    mesa-dri-drivers \
    mesa-vulkan-drivers

  success "Drivers Intel Iris Xe instalados"

  if command -v vainfo &>/dev/null; then
    info "Verificando VA-API:"
    vainfo 2>&1 | grep -E "vainfo|VA-API|profile" | head -10 | tee -a "$LOG_FILE" || true
  fi

  save_step 4
fi

# =============================================================================
# ETAPA 5 — GERENCIAMENTO DE ENERGIA (TLP)
# =============================================================================
if should_run 5; then
  section 5 "Configurando gerenciamento de energia (TLP)"

  dnf_install tlp tlp-rdw
  sudo systemctl enable --now tlp 2>&1 | tee -a "$LOG_FILE"
  sudo systemctl mask power-profiles-daemon 2>/dev/null | tee -a "$LOG_FILE" || true

  success "TLP instalado e ativo"
  save_step 5
fi

# =============================================================================
# ETAPA 6 — TUNED (Otimização de Performance)
# =============================================================================
if should_run 6; then # Ou ajuste a numeração conforme sua sequência
  section 6 "Configurando Tuned (Perfil de Performance)"

  dnf_install tuned
  sudo systemctl enable --now tuned 2>&1 | tee -a "$LOG_FILE"

  # Para o seu VAIO (Laptop), o perfil 'throughput-performance' é excelente para compilação .NET
  # mas o 'accelerate-performance' ou 'balanced' também são opções.
  sudo tuned-adm profile throughput-performance 2>&1 | tee -a "$LOG_FILE"

  success "Tuned configurado para máxima performance de I/O e CPU"
  save_step 6
fi

# =============================================================================
# ETAPA 7 — HARDWARE (Wi-Fi, Bluetooth, Suspend)
# =============================================================================
if should_run 7; then
  section 7 "Configurando hardware (Wi-Fi, Bluetooth, Suspend)"
  
  dnf_install iwl7260-firmware iwl8000-firmware iwl3160-firmware alsa-utils bluez bluez-tools

  # Suspend ao fechar a tampa (Idempotente)
  LOGIND_CONF="/etc/systemd/logind.conf"
  if ! grep -q "^HandleLidSwitch=suspend" "$LOGIND_CONF"; then
    # Comenta a linha padrão e adiciona a nova para evitar duplicidade
    sudo sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=suspend/' "$LOGIND_CONF"
    # Caso a linha nem exista (raro), adiciona ao fim
    grep -q "^HandleLidSwitch=suspend" "$LOGIND_CONF" || echo "HandleLidSwitch=suspend" | sudo tee -a "$LOGIND_CONF" > /dev/null
  fi

  # PITFALL: NÃO use 'systemctl restart systemd-logind' aqui, pois ele derruba a sessão X11/Wayland 
  # e mata o script. O logind será atualizado no reboot final do script.
  info "Configuração de Suspend aplicada (será ativada após o reboot)."

  success "Hardware configurado"
  save_step 7
fi

# =============================================================================
# ETAPA 8 — GNOME
# =============================================================================
if should_run 8; then
  section 8 "Ajustando GNOME"

  dnf_install gnome-tweaks gnome-extensions-app dconf-editor

  gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
  gsettings set org.gnome.desktop.peripherals.keyboard numlock-state true
  gsettings set org.gnome.desktop.interface show-battery-percentage true

  _log "gsettings aplicados"
  success "GNOME configurado"
  save_step 8
fi

# =============================================================================
# ETAPA 9 — DESENVOLVIMENTO (.NET + VS Code + extensões C#)
# =============================================================================
if should_run 9; then
  section 9 "Instalando ambiente de desenvolvimento (.NET + VS Code)"

  sudo dnf groupinstall -y "Development Tools" 2>&1 | tee -a "$LOG_FILE"

  dnf_install \
    git curl wget vim htop \
    p7zip p7zip-plugins unrar \
    neofetch

  # .NET SDK
  info "Instalando .NET SDK 10..."
  dnf_install dotnet-sdk-10.0

  if command -v dotnet &>/dev/null; then
    success ".NET instalado: $(dotnet --version)"
  else
    warn ".NET pode não ter instalado corretamente — verifique manualmente."
  fi

  # VS Code
  if ! command -v code &>/dev/null; then
    info "Adicionando repositório VS Code..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>&1 | tee -a "$LOG_FILE"
    sudo sh -c 'cat > /etc/yum.repos.d/vscode.repo << EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF'
    dnf_install code
    success "VS Code instalado"
  else
    info "VS Code já está instalado"
  fi

  # Extensões C#/.NET
  if command -v code &>/dev/null; then
    info "Instalando extensões do VS Code para C#/.NET..."
    EXTENSIONS=(
      "ms-dotnettools.csharp"
      "ms-dotnettools.csdevkit"
      "ms-dotnettools.vscode-dotnet-runtime"
      "formulahendry.dotnet-test-explorer"
      "editorconfig.editorconfig"
    )
    for ext in "${EXTENSIONS[@]}"; do
      code --install-extension "$ext" 2>&1 | tee -a "$LOG_FILE" || \
        warn "Não foi possível instalar extensão: $ext"
    done
    success "Extensões C#/.NET instaladas"
  fi

  save_step 9
fi

# =============================================================================
# ETAPA 10 — FLATHUB
# =============================================================================
if should_run 10; then
  section 10 "Configurando Flathub"

  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
    2>&1 | tee -a "$LOG_FILE"

  success "Flathub configurado"
  save_step 10
fi

# =============================================================================
# ETAPA 11 — SNAPPER (snapshots Btrfs automáticos)
# =============================================================================
if should_run 11; then
  section 11 "Configurando Snapper (snapshots Btrfs)"

  # Verificar se o filesystem raiz é Btrfs
  ROOT_FS=$(findmnt -n -o FSTYPE /)
  if [[ "$ROOT_FS" != "btrfs" ]]; then
    warn "Filesystem raiz não é Btrfs (é: ${ROOT_FS}). Pulando Snapper."
    save_step 11
  else
    dnf_install snapper snap-pac snapper-gui

    # Criar configuração para root (se não existir)
    if ! snapper -c root list &>/dev/null 2>&1; then
      sudo snapper -c root create-config / 2>&1 | tee -a "$LOG_FILE"
      success "Configuração snapper para / criada"
    else
      info "Configuração snapper para / já existe"
    fi

    # Ajustar limites de snapshots (evitar acúmulo excessivo)
    sudo snapper -c root set-config \
      NUMBER_LIMIT=10 \
      NUMBER_LIMIT_IMPORTANT=5 \
      TIMELINE_CREATE=yes \
      TIMELINE_LIMIT_HOURLY=3 \
      TIMELINE_LIMIT_DAILY=7 \
      TIMELINE_LIMIT_WEEKLY=2 \
      TIMELINE_LIMIT_MONTHLY=1 \
      TIMELINE_LIMIT_YEARLY=0 \
      2>&1 | tee -a "$LOG_FILE"

    # Habilitar timers do snapper
    sudo systemctl enable --now snapper-timeline.timer 2>&1 | tee -a "$LOG_FILE"
    sudo systemctl enable --now snapper-cleanup.timer  2>&1 | tee -a "$LOG_FILE"

    success "Snapper configurado — snapshots automáticos ativos"
    info "snap-pac criará snapshots automáticos antes/depois de cada dnf"
    save_step 11
  fi
fi

# =============================================================================
# ETAPA 12 — FIREWALL (verificação + perfil dev)
# =============================================================================
if should_run 12; then
  section 12 "Verificando e configurando Firewall"

  # Garantir que firewalld está ativo
  if ! sudo systemctl is-active --quiet firewalld; then
    sudo systemctl enable --now firewalld 2>&1 | tee -a "$LOG_FILE"
    success "firewalld ativado"
  else
    info "firewalld já está ativo"
  fi

  # Zona padrão
  DEFAULT_ZONE=$(sudo firewall-cmd --get-default-zone)
  info "Zona padrão: ${DEFAULT_ZONE}"
  _log "Zona padrão firewall: ${DEFAULT_ZONE}"

  # Portas úteis para desenvolvimento local (.NET, HTTP, HTTPS, debugging)
  DEV_PORTS=(
    "5000/tcp"   # ASP.NET HTTP default
    "5001/tcp"   # ASP.NET HTTPS default
    "7000/tcp"   # ASP.NET alternativa
    "8080/tcp"   # HTTP alternativa comum
  )

  info "Abrindo portas para desenvolvimento local..."
  for port in "${DEV_PORTS[@]}"; do
    sudo firewall-cmd --permanent --add-port="$port" 2>&1 | tee -a "$LOG_FILE" || true
  done

  # Serviços úteis
  sudo firewall-cmd --permanent --add-service=ssh    2>&1 | tee -a "$LOG_FILE" || true
  sudo firewall-cmd --permanent --add-service=mdns   2>&1 | tee -a "$LOG_FILE" || true

  sudo firewall-cmd --reload 2>&1 | tee -a "$LOG_FILE"

  info "Regras ativas:"
  sudo firewall-cmd --list-all 2>&1 | tee -a "$LOG_FILE"

  success "Firewall configurado para desenvolvimento"
  save_step 12
fi

# =============================================================================
# ETAPA 13 — FONTES MICROSOFT + RENDERIZAÇÃO
# =============================================================================
if should_run 13; then
  section 13 "Instalando fontes Microsoft e melhorando renderização"

  # Fontes essenciais
  dnf_install \
    curl \
    cabextract \
    xorg-x11-font-utils \
    fontconfig

  # Microsoft Core Fonts via RPM Fusion (msttcorefonts)
  dnf_install mscore-fonts-all || \
    warn "mscore-fonts-all não disponível — tentando via Flathub ou método alternativo"

  # Fontes de desenvolvimento recomendadas
  dnf_install \
    fira-code-fonts \
    mozilla-fira-mono-fonts \
    google-roboto-fonts \
    google-noto-fonts-common

  # Renderização melhorada — hinting e antialiasing
  gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'
  gsettings set org.gnome.desktop.interface font-hinting 'slight'

  # Fonte do sistema (opcional — descomente para aplicar)
  # gsettings set org.gnome.desktop.interface font-name 'Roboto 11'
  # gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code 12'
  # gsettings set org.gnome.desktop.interface document-font-name 'Roboto 11'

  # Atualizar cache de fontes
  sudo fc-cache -fv 2>&1 | tee -a "$LOG_FILE"

  success "Fontes e renderização configuradas"
  save_step 13
fi

# =============================================================================
# ETAPA 14 — ZSH + OH MY ZSH
# =============================================================================
if should_run 14; then
  section 14 "Instalando Zsh + Oh My Zsh"

  dnf_install zsh util-linux-user

  # Definir Zsh como shell padrão do usuário atual
  if [[ "$SHELL" != "$(which zsh)" ]]; then
    sudo chsh -s "$(which zsh)" "$USER" 2>&1 | tee -a "$LOG_FILE"
    success "Zsh definido como shell padrão para $USER"
  else
    info "Zsh já é o shell padrão"
  fi

  # Instalar Oh My Zsh (modo não-interativo, sem trocar shell automaticamente)
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Instalando Oh My Zsh..."
    RUNZSH=no CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      2>&1 | tee -a "$LOG_FILE"
    success "Oh My Zsh instalado"
  else
    info "Oh My Zsh já está instalado"
  fi

  # Plugins úteis para desenvolvimento
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

  # zsh-autosuggestions
  if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
      "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" 2>&1 | tee -a "$LOG_FILE"
  fi

  # zsh-syntax-highlighting
  if [[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
      "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" 2>&1 | tee -a "$LOG_FILE"
  fi

  # Ativar plugins no .zshrc (se Oh My Zsh foi instalado)
  if [[ -f "$HOME/.zshrc" ]]; then
    # Habilitar plugins
    sed -i 's/^plugins=(git)/plugins=(git dotnet dnf zsh-autosuggestions zsh-syntax-highlighting)/' \
      "$HOME/.zshrc" 2>/dev/null || \
      warn "Não foi possível atualizar plugins no .zshrc — edite manualmente"

    # Adicionar PATH do .NET se necessário
    if ! grep -q "DOTNET_ROOT" "$HOME/.zshrc"; then
      cat >> "$HOME/.zshrc" << 'EOF'

# .NET
export DOTNET_ROOT=/usr/lib/dotnet
export PATH="$PATH:$HOME/.dotnet/tools"
EOF
    fi

    success "Plugins Zsh configurados: git dotnet dnf autosuggestions syntax-highlighting"
  fi

  success "Zsh + Oh My Zsh instalados"
  warn "Reinicie o terminal ou execute 'zsh' para usar o novo shell"
  save_step 14
fi

# =============================================================================
# ETAPA 15 — DOCKER / PODMAN
# =============================================================================
if should_run 15; then
  section 15 "Configurando Docker / Podman"

  # Podman já vem no Fedora — garantir que está instalado e configurar
  dnf_install \
    podman \
    podman-compose \
    buildah \
    skopeo

  # Habilitar socket do Podman (para compatibilidade com Docker API)
  systemctl --user enable --now podman.socket 2>&1 | tee -a "$LOG_FILE" || true

  # Criar alias docker → podman para compatibilidade
  if [[ -f "$HOME/.zshrc" ]]; then
    if ! grep -q "alias docker=podman" "$HOME/.zshrc"; then
      echo "" >> "$HOME/.zshrc"
      echo "# Podman como substituto do Docker" >> "$HOME/.zshrc"
      echo "alias docker=podman" >> "$HOME/.zshrc"
      echo "alias docker-compose=podman-compose" >> "$HOME/.zshrc"
    fi
  fi
  if [[ -f "$HOME/.bashrc" ]]; then
    if ! grep -q "alias docker=podman" "$HOME/.bashrc"; then
      echo "" >> "$HOME/.bashrc"
      echo "# Podman como substituto do Docker" >> "$HOME/.bashrc"
      echo "alias docker=podman" >> "$HOME/.bashrc"
      echo "alias docker-compose=podman-compose" >> "$HOME/.bashrc"
    fi
  fi

  # Docker Engine (opcional — descomente se preferir Docker em vez de Podman)
  # sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
  # dnf_install docker-ce docker-ce-cli containerd.io docker-compose-plugin
  # sudo systemctl enable --now docker
  # sudo usermod -aG docker "$USER"

  # Configurar registro de containers para Docker Hub
  if [[ ! -f /etc/containers/registries.conf.d/docker.conf ]]; then
    sudo tee /etc/containers/registries.conf.d/docker.conf > /dev/null << 'EOF'
[[registry]]
prefix = "docker.io"
location = "docker.io"
EOF
  fi

  info "Versão Podman: $(podman --version)"
  success "Podman configurado (alias docker=podman ativo)"
  warn "Faça logout/login para que o socket do Podman funcione corretamente"
  save_step 15
fi


echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════╗"
echo "║           ✅  Configuração concluída!                ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  ✔ Sistema atualizado                                ║"
echo "║  ✔ RPM Fusion habilitado                             ║"
echo "║  ✔ Codecs de mídia instalados                        ║"
echo "║  ✔ Driver Intel Iris Xe configurado                  ║"
echo "║  ✔ TLP (gerenciamento de bateria) ativo              ║"
echo "║  ✔ Tuned (Perfil de Performance)                     ║"
echo "║  ✔ Wi-Fi / Bluetooth / Suspend configurados          ║"
echo "║  ✔ GNOME ajustado                                    ║"
echo "║  ✔ .NET SDK 9 + VS Code + extensões C# instalados    ║"
echo "║  ✔ Flathub configurado                               ║"
echo "║  ✔ Snapper (snapshots Btrfs automáticos)             ║"
echo "║  ✔ Firewall configurado para desenvolvimento         ║"
echo "║  ✔ Fontes Microsoft + renderização melhorada         ║"
echo "║  ✔ Zsh + Oh My Zsh + plugins instalados              ║"
echo "║  ✔ Podman configurado (alias docker=podman)          ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  📄 Log completo: %-34s║\n" "$LOG_FILE"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  ⚠  Reinicie o sistema para aplicar todas as         ║"
echo "║     mudanças (especialmente drivers e Zsh).          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Remove o arquivo de progresso após conclusão bem-sucedida
rm -f "$STEP_FILE"
_log "Script concluído com sucesso. Arquivo de progresso removido."

read -rp "Deseja reiniciar agora? [s/N] " RESPOSTA
if [[ "${RESPOSTA,,}" == "s" ]]; then
  info "Reiniciando em 5 segundos..."
  sleep 5
  sudo reboot
else
  info "Reinicie manualmente quando quiser com: sudo reboot"
fi

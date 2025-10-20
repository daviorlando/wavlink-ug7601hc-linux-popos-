#!/usr/bin/env bash
#
# Correção Wavlink WL-UG7601HC (DisplayLink/SMI USB Display) — Pop!_OS kernel 6.16.x
# v3:
#  - Tolerante a 'DKMS tree already contains' (não aborta)
#  - Força build/install para o kernel atual
#  - Instala SOMENTE a libevdi (evita falha no PyEvdi)
#  - Não usa 'make install' no diretório raiz do evdi (evita alvo pyevdi)
#
set -euo pipefail

EVDI_TAG="${EVDI_TAG:-v1.14.11}"
EVDI_VER="${EVDI_TAG#v}"
WORKDIR="$(mktemp -d -t ug7601hc-fix.XXXXXX)"
LOGFILE="/var/log/fix-ug7601hc-evdi-${EVDI_TAG}.log"
KVER="$(uname -r)"

mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

banner() {
  echo
  echo "[INFO] ==============================================================="
  echo "[INFO] $1"
  echo "[INFO] ==============================================================="
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[ERRO] Execute como root: sudo $0 [opcional:.run]"
    exit 1
  fi
}

stop_services() {
  banner "Parando serviços DisplayLink/SMI (se existirem)"
  systemctl stop displaylink-driver.service 2>/dev/null || true
  systemctl stop displaylink.service 2>/dev/null || true
  systemctl stop smi.service 2>/dev/null || true
  systemctl stop smiusbdisplay.service 2>/dev/null || true
  systemctl stop smi-instantview.service 2>/dev/null || true
}

start_services() {
  banner "Iniciando serviços DisplayLink/SMI (se existirem)"
  systemctl daemon-reload || true
  systemctl restart displaylink-driver.service 2>/dev/null || true
  systemctl restart displaylink.service 2>/dev/null || true
  systemctl restart smi.service 2>/dev/null || true
  systemctl restart smiusbdisplay.service 2>/dev/null || true
  systemctl restart smi-instantview.service 2>/dev/null || true
}

blacklist_udl() {
  banner "Desativando 'udl' (framebuffer genérico) para evitar conflitos"
  mkdir -p /etc/modprobe.d
  cat >/etc/modprobe.d/blacklist-udl.conf <<'EOF'
# Bloqueia driver udl (framebuffer genérico) para evitar conflitos com evdi
blacklist udl
EOF
}

install_build_prereqs() {
  banner "Instalando dependências de compilação (dkms, headers, build-essential, git, libdrm-dev)"
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    dkms build-essential "linux-headers-$(uname -r)" git pkg-config libdrm-dev
}

purge_old_evdi() {
  banner "Removendo versões antigas do EVDI no DKMS (se houver)"
  if dkms status | grep -qi 'evdi/'; then
    while read -r line; do
      ver="$(echo "$line" | awk -F'[ /,]' '/evdi\//{print $2}' | head -n1)"
      if [[ -n "${ver:-}" && "${ver}" != "${EVDI_VER}" ]]; then
        echo "[INFO] Removendo evdi/${ver} do DKMS"
        dkms remove "evdi/${ver}" --all || true
      fi
    done < <(dkms status | grep -i 'evdi/' || true)
  else
    echo "[INFO] Nenhuma versão antiga do evdi encontrada no DKMS."
  fi
}

dkms_has_evdi_ver() {
  # Detecta presença de evdi/<versao> no DKMS mesmo que sem build
  if dkms status 2>/dev/null | grep -q "evdi/${EVDI_VER}"; then
    return 0
  fi
  # Fallback: presença do fonte no /usr/src
  if [[ -f "/usr/src/evdi-${EVDI_VER}/dkms.conf" ]]; then
    return 0
  fi
  return 1
}

build_install_evdi() {
  banner "Baixando e preparando EVDI ${EVDI_TAG}"
  cd "$WORKDIR"
  git clone https://github.com/DisplayLink/evdi.git
  cd evdi
  git checkout "${EVDI_TAG}"

  banner "Registrando (se necessário), compilando e instalando EVDI ${EVDI_VER} para o kernel ${KVER}"
  cd module

  if dkms_has_evdi_ver; then
    echo "[INFO] evdi/${EVDI_VER} já presente no DKMS. Pulando 'dkms add'."
  else
    echo "[INFO] Executando: dkms add . (primeira vez desta versão)"
    dkms add . || echo "[WARN] 'dkms add' retornou erro, mas seguiremos se a versão já constar no tree."
  fi

  # Constrói e instala explicitamente para o kernel atual
  if ! dkms build "evdi/${EVDI_VER}" -k "${KVER}"; then
    echo "[WARN] Build falhou. Tentando limpar build antigo deste kernel e refazer..."
    dkms remove "evdi/${EVDI_VER}" -k "${KVER}" --force || true
    dkms add . || true
    dkms build "evdi/${EVDI_VER}" -k "${KVER}"
  fi

  dkms install "evdi/${EVDI_VER}" -k "${KVER}" --force || true

  cd ..
  banner "Compilando e instalando SOMENTE a libevdi compatível (${EVDI_VER})"
  make -C library
  make -C library install
  ldconfig
}

modprobe_evdi() {
  banner "Carregando módulo 'evdi' e verificando versão"
  modprobe -r evdi 2>/dev/null || true
  modprobe evdi
  modinfo evdi | egrep 'filename:|version:|license:|srcversion:' || true
}

install_smi_run_if_provided() {
  local RUNFILE="${1:-}"
  if [[ -z "${RUNFILE}" ]]; then
    echo "[INFO] Instalador SMI (.run) não fornecido. Pulando etapa opcional."
    return 0
  fi
  if [[ ! -f "${RUNFILE}" ]]; then
    echo "[ERRO] Arquivo .run não encontrado: ${RUNFILE}"
    exit 1
  fi
  banner "Instalando pacote original (${RUNFILE}) — pode reinstalar EVDI antigo; vamos sobrepor em seguida"
  chmod +x "${RUNFILE}"
  "${RUNFILE}" || true

  # Garante que a versão nova permaneça
  build_install_evdi
  modprobe_evdi
}

diagnostics() {
  banner "Diagnóstico rápido"
  echo "[INFO] Kernel: ${KVER}"
  echo "[INFO] DKMS:"
  dkms status || true
  echo "[INFO] Udev rules relevantes:"
  ls -l /etc/udev/rules.d/*evdi*.rules 2>/dev/null || true
  ls -l /lib/udev/rules.d/*evdi*.rules 2>/dev/null || true
  echo "[INFO] Dispositivos USB potenciais (WAVLINK/DisplayLink/Silicon Motion):"
  lsusb | egrep -i 'wavlink|displaylink|silicon|17e9|090c|1d5c' || true
}

main() {
  require_root
  banner "Correção Wavlink WL-UG7601HC (DisplayLink) — Pop!_OS kernel ${KVER}"
  echo "[INFO] Log: ${LOGFILE}"
  stop_services
  blacklist_udl
  install_build_prereqs
  purge_old_evdi
  build_install_evdi
  modprobe_evdi
  install_smi_run_if_provided "${1:-}"
  start_services
  diagnostics
  echo
  echo "[SUCESSO] EVDI ${EVDI_TAG} instalado e serviços reiniciados."
  echo "[DICA] Se ainda não detectar a tela, reconecte o dock/adaptador USB e faça logout/login (ou reinicie o sistema gráfico)."
  echo "[DICA] Para suporte, anexe este log: ${LOGFILE}"
  echo
}

trap 'echo "[INFO] Limpando diretório temporário ${WORKDIR}"; rm -rf "$WORKDIR"' EXIT
main "$@"

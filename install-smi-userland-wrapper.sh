#!/usr/bin/env bash
#
# install-smi-userland-wrapper.sh
# Executa o instalador .run da SMI *ignorando* qualquer chamada a DKMS,
# para instalar apenas os componentes de userland (udev, serviços, bins).
#
# Uso:
#   sudo ./install-smi-userland-wrapper.sh /caminho/SMIUSBDisplay-driver.2.22.1.0.run
#
set -euo pipefail

RUNFILE="${1:-}"
if [[ -z "${RUNFILE}" || ! -f "${RUNFILE}" ]]; then
  echo "[ERRO] Informe o caminho para o arquivo .run do SMI (ex.: SMIUSBDisplay-driver.2.22.1.0.run)"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "[ERRO] Execute como root: sudo $0 /caminho/para/SMIUSBDisplay-driver*.run"
  exit 1
fi

WRAPBIN="$(mktemp -d -t smi-wrapbin.XXXXXX)"
trap 'echo "[INFO] Limpando ${WRAPBIN}"; rm -rf "${WRAPBIN}"' EXIT

# Cria wrapper para 'dkms' que apenas loga e retorna sucesso
cat > "${WRAPBIN}/dkms" <<'EOF'
#!/usr/bin/env bash
echo "[WRAP] DKMS suprimido: dkms $@" >&2
exit 0
EOF
chmod +x "${WRAPBIN}/dkms"

# Opcional: se quiser também suprimir 'modprobe' durante a instalação (não é obrigatório)
cat > "${WRAPBIN}/modprobe" <<'EOF'
#!/usr/bin/env bash
echo "[WRAP] modprobe suprimido durante instalador: modprobe $@" >&2
# não retornar erro — alguns instaladores ignoram retorno, outros não
exit 0
EOF
chmod +x "${WRAPBIN}/modprobe"

# Exporta variáveis que alguns instaladores respeitam
export SKIP_DKMS=1 SKIP_EVDI=1 SKIP_KMOD=1 NO_DKMS=1

echo "[INFO] Executando instalador com DKMS neutralizado ..."
PATH="${WRAPBIN}:${PATH}" bash "${RUNFILE}"

echo "[INFO] Recarregando regras e serviços ..."
udevadm control --reload-rules || true
udevadm trigger || true
systemctl daemon-reload || true

for svc in displaylink-driver displaylink smi smiusbdisplay smi-instantview; do
  systemctl enable "$svc" 2>/dev/null || true
  systemctl restart "$svc" 2>/dev/null || true
done

echo "[SUCESSO] Instalador executado com DKMS suprimido (userland instalado)."
echo "[DICA] Para manter compatibilidade com kernel 6.16.x, rode agora:"
echo "       sudo ./fix-ug7601hc-evdi-6.16.sh"

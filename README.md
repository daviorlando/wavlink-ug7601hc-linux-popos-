
# Wavlink WL-UG7601HC on Pop!_OS (kernel 6.16.x)

Scripts e guia para fazer o adaptador **Wavlink WL-UG7601HC** (chipset Synaptics/SMI + EVDI/DisplayLink) funcionar no **Pop!_OS 22.04** com **kernel 6.16.x**.

> ✅ Confirmado em uso real: o instalador da SMI foi executado com DKMS suprimido, o notebook reiniciou e a tela USB passou a funcionar.

---

## Por que estes scripts?

- O instalador oficial da SMI (`SMIUSBDisplay-driver*.run`) tenta instalar **EVDI 1.14.7** via DKMS, que **quebra** no kernel 6.16.x.
- Este repo mantém **EVDI 1.14.11** (que funciona no 6.16.x) e instala **apenas o userland** da SMI (udev/serviços/binários).
- Tudo automatizado, idempotente e com logs.

---

## Conteúdo

- `scripts/fix-ug7601hc-evdi-6.16.sh`: corrige/garante **EVDI v1.14.11** via DKMS e instala a **libevdi** correspondente. Também desabilita `udl` para evitar conflito.
- `scripts/install-smi-userland-wrapper.sh`: executa o `.run` da SMI **silenciando DKMS/modprobe**, instalando só userland.

> **Não** versionamos o instalador proprietário `SMIUSBDisplay-driver*.run`. Baixe do site do fabricante e indique o caminho ao rodar o wrapper.

---


---

## Onde baixar o driver oficial (fabricante)

- Página oficial de drivers da Wavlink: <https://www.wavlink.com/en_us/drivers.html>  
  Procure pelo modelo **WL-UG7601HC** (linha baseada em **SM768/Synaptics/SMI**) e baixe o instalador para **Linux** (arquivo `.run`).  
  > Observação: não publicamos o `.run` no repositório por provável licença proprietária; use o wrapper para instalar apenas o *userland* e mantenha o **EVDI 1.14.11** ativo via script de correção.

## Requisitos

- Pop!_OS 22.04 (ou derivado Ubuntu 22.04) com kernel 6.16.x
- `sudo`, `dkms`, `git`, `build-essential`, `linux-headers-$(uname -r)`, `pkg-config`, `libdrm-dev` (o script de fix instala se faltar)

---

## Passo a passo (sempre funciona)

1) **Instalar o userland SMI** sem tocar no DKMS/EVDI:

```bash
cd scripts
chmod +x install-smi-userland-wrapper.sh
sudo ./install-smi-userland-wrapper.sh ~/Downloads/SM768-Driver-20250808/SMIUSBDisplay-driver.2.22.1.0.run
```

2) **Fixar o EVDI 1.14.11** e alinhar a `libevdi`:

```bash
chmod +x fix-ug7601hc-evdi-6.16.sh
sudo ./fix-ug7601hc-evdi-6.16.sh
```

3) (Opcional) Desconecte e reconecte o adaptador USB; faça **logout/login** (especialmente em **Wayland**) ou reinicie a sessão gráfica.

---

## Verificações rápidas

```bash
# versão do módulo EVDI carregado
modinfo evdi | egrep 'filename:|version:'

# módulo em uso
lsmod | grep evdi || echo "evdi ainda não carregado"

# biblioteca userland
ldconfig -p | grep libevdi

# serviços (alguns nomes podem não existir dependendo da versão)
systemctl status smi smiusbdisplay smi-instantview displaylink displaylink-driver --no-pager --full
```

**Xorg:**

```bash
echo $XDG_SESSION_TYPE   # deve ser 'x11'
xrandr --listproviders   # espera algo como 'DLP (evdi)'
```

**Wayland:** após instalar, geralmente precisa **logout/login** para o compositor reconhecer.

---

## Troubleshooting (FAQ)

- **O instalador .run tenta “downgrade” para EVDI 1.14.7**  
  Use sempre o wrapper `install-smi-userland-wrapper.sh` e depois rode `fix-ug7601hc-evdi-6.16.sh`.

- **Monitor não acende**  
  1) Reconecte o adaptador USB  
  2) Logout/login (especialmente em Wayland)  
  3) Teste sessão **Xorg** na tela de login  
  4) Cole diagnósticos:
     ```bash
     uname -r
     dkms status | grep -i evdi
     modinfo evdi | egrep 'filename:|version:'
     ldconfig -p | grep libevdi
     systemctl status smi smiusbdisplay smi-instantview displaylink displaylink-driver --no-pager --full
     journalctl -u displaylink-driver -u displaylink -u smi -u smiusbdisplay -u smi-instantview --since "1 hour ago" --no-pager | tail -n 200
     ```

- **Limpar versões antigas do DKMS e manter só 1.14.11**  
  ```bash
  sudo dkms remove evdi/1.7.0 --all || true
  sudo rm -rf /usr/src/evdi-1.7.0 /var/lib/dkms/evdi/1.7.0
  sudo rm -rf /usr/src/evdi-1.14.7 /var/lib/dkms/evdi/1.14.7
  sudo dkms status | grep -i evdi || echo "Somente 1.14.11 ativa"
  ```

---

## Segurança e licenças

- Estes **scripts** não contêm segredos. Evite subir **logs** ou o **.run proprietário**.
- **EVDI** é GPL; estes scripts shell estão licenciados sob **MIT** (veja `LICENSE`).
- Marcas “DisplayLink”, “Synaptics/SMI” e “Wavlink” são usadas de forma descritiva (uso nominativo).

---


## Créditos

- Scripts e documentação: comunidade + contribuições de Davi Orlando.
- EVDI: https://github.com/DisplayLink/evdi

Se este repo ajudou, deixe uma estrela ⭐ e compartilhe!

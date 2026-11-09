#!/usr/bin/env bash
# ==============================================================================
# Script de Instalação Rápida: Zabbix Proxy 7.0 LTS + Selenium Standalone Chrome
# Plataformas Suportadas: Ubuntu e Debian
# Ambiente: Docker & Docker Compose
# ==============================================================================

set -euo pipefail

# Cores para saída no terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Mensagens utilitárias
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

# Funções de validação
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

validate_ip_or_fqdn() {
    local target="$1"
    local ipv4_regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    local fqdn_regex='^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$|^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$'

    if [[ "$target" =~ $ipv4_regex || "$target" =~ $fqdn_regex ]]; then
        return 0
    else
        return 1
    fi
}

# 1. Verificação de permissões de root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_error "Este script precisa ser executado como root ou com privilégios de sudo."
    echo "Exemplo: sudo bash $0"
    exit 1
fi

echo -e "${CYAN}${BOLD}"
echo "=================================================================="
echo "    INSTALAÇÃO RÁPIDA: ZABBIX PROXY 7.0 + SELENIUM EM DOCKER      "
echo "=================================================================="
echo -e "${NC}"

# 2. Verificação de Sistema Operacional
if [ ! -f /etc/os-release ]; then
    log_error "Não foi possível identificar o sistema operacional (/etc/os-release ausente)."
    exit 1
fi

. /etc/os-release

OS_ID="${ID:-}"
OS_VERSION_CODENAME="${VERSION_CODENAME:-}"

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    log_warn "Sistema operacional detectado: $OS_ID ($NAME)."
    log_warn "Este script foi projetado para Ubuntu e Debian. Deseja prosseguir mesmo assim?"
    read -rp "Continuar? (s/N): " FORCE_CONTINUE
    if [[ ! "$FORCE_CONTINUE" =~ ^[sS]$ ]]; then
        log_error "Instalação cancelada."
        exit 1
    fi
else
    log_success "Sistema operacional detectado: $NAME ($VERSION)"
fi

# 3. Verificação e Instalação de Docker / Docker Compose
install_docker() {
    log_info "Instalando Docker CE e Docker Compose plugin via repositório oficial..."

    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} \
      ${OS_VERSION_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    log_success "Docker instalado e ativado com sucesso!"
}

if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    log_info "Docker ou Docker Compose plugin não foram localizados no sistema."
    install_docker
else
    log_success "Docker e Docker Compose já estão instalados: $(docker --version)"
fi

# 4. Perguntas interativas de configuração

# 4.1 Pasta de instalação
DEFAULT_INSTALL_DIR="/opt/zabbix-proxy"
read -rp "Diretório de instalação [padrão: ${DEFAULT_INSTALL_DIR}]: " INPUT_INSTALL_DIR
INSTALL_DIR="${INPUT_INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
log_info "Diretório selecionado: $INSTALL_DIR"

# 4.2 Nome do Proxy no Zabbix
while true; do
    read -rp "Nome do Proxy (Hostname cadastrado no Zabbix Server): " INPUT_HOSTNAME
    ZBX_HOSTNAME="$(echo "$INPUT_HOSTNAME" | xargs)"
    if [ -n "$ZBX_HOSTNAME" ]; then
        break
    else
        log_error "O nome do Proxy é obrigatório e não pode ser vazio."
    fi
done

# 4.3 Endereço do Zabbix Server
while true; do
    read -rp "Endereço (IP ou FQDN) do Zabbix Server: " INPUT_SERVER_HOST
    ZBX_SERVER_HOST="$(echo "$INPUT_SERVER_HOST" | xargs)"
    if [ -z "$ZBX_SERVER_HOST" ]; then
        log_error "O endereço do Zabbix Server é obrigatório."
        continue
    fi

    if ! validate_ip_or_fqdn "$ZBX_SERVER_HOST"; then
        log_error "Formato inválido: '$ZBX_SERVER_HOST'. Digite um IP válido (ex: 192.168.1.100) ou FQDN (ex: zabbix.empresa.com)."
        continue
    fi

    log_info "Verificando se $ZBX_SERVER_HOST responde a ping..."
    if ping -c 1 -W 2 "$ZBX_SERVER_HOST" &>/dev/null; then
        log_success "Host $ZBX_SERVER_HOST alcançável com sucesso."
        break
    else
        log_warn "Não foi possível pingar $ZBX_SERVER_HOST (pode estar bloqueado por firewall ou temporariamente inacessível)."
        read -rp "Deseja manter este endereço mesmo assim? (S/n): " CONFIRM_HOST
        CONFIRM_HOST="${CONFIRM_HOST:-S}"
        if [[ "$CONFIRM_HOST" =~ ^[sS]$ ]]; then
            break
        fi
    fi
done

# 4.4 Porta do Zabbix Server
DEFAULT_SERVER_PORT="10051"
while true; do
    read -rp "Porta do Zabbix Server [padrão: ${DEFAULT_SERVER_PORT}]: " INPUT_SERVER_PORT
    ZBX_SERVER_PORT="${INPUT_SERVER_PORT:-$DEFAULT_SERVER_PORT}"
    if validate_port "$ZBX_SERVER_PORT"; then
        break
    else
        log_error "Porta inválida: '$ZBX_SERVER_PORT'. A porta deve ser um número inteiro entre 1 e 65535."
    fi
done

# 4.5 Modo de Operação do Proxy
echo ""
echo -e "${BOLD}Modo de Operação do Proxy:${NC}"
echo "  1) Passivo (Padrão - O Zabbix Server conecta no Proxy para coletar os dados)"
echo "  0) Ativo (O Proxy conecta e envia os dados para o Zabbix Server)"
read -rp "Escolha o modo (1 ou 0) [padrão: 1]: " INPUT_PROXYMODE
ZBX_PROXYMODE="${INPUT_PROXYMODE:-1}"
if [[ "$ZBX_PROXYMODE" != "0" && "$ZBX_PROXYMODE" != "1" ]]; then
    log_warn "Opção inválida, definindo modo Passivo (1) por padrão."
    ZBX_PROXYMODE="1"
fi

# 4.6 Portas Locais (Proxy e Selenium)
DEFAULT_PROXY_PORT="10051"
while true; do
    read -rp "Porta de escuta local do Zabbix Proxy no host [padrão: ${DEFAULT_PROXY_PORT}]: " INPUT_PROXY_PORT
    PROXY_PORT="${INPUT_PROXY_PORT:-$DEFAULT_PROXY_PORT}"
    if validate_port "$PROXY_PORT"; then
        break
    else
        log_error "Porta inválida: '$PROXY_PORT'. A porta deve ser um número inteiro entre 1 e 65535."
    fi
done

DEFAULT_SELENIUM_PORT="4444"
while true; do
    read -rp "Porta de acesso local do Selenium Standalone no host [padrão: ${DEFAULT_SELENIUM_PORT}]: " INPUT_SELENIUM_PORT
    SELENIUM_PORT="${INPUT_SELENIUM_PORT:-$DEFAULT_SELENIUM_PORT}"
    if validate_port "$SELENIUM_PORT"; then
        if [ "$SELENIUM_PORT" == "$PROXY_PORT" ]; then
            log_error "A porta do Selenium ($SELENIUM_PORT) não pode ser igual à porta do Proxy ($PROXY_PORT)."
            continue
        fi
        break
    else
        log_error "Porta inválida: '$SELENIUM_PORT'. A porta deve ser um número inteiro entre 1 e 65535."
    fi
done

# Quantidade de Pollers para Browser / Selenium
DEFAULT_BROWSER_POLLERS="2"
while true; do
    read -rp "Número de processos Browser Pollers no Proxy [padrão: ${DEFAULT_BROWSER_POLLERS}]: " INPUT_BROWSER_POLLERS
    ZBX_STARTBROWSERPOLLERS="${INPUT_BROWSER_POLLERS:-$DEFAULT_BROWSER_POLLERS}"
    if [[ "$ZBX_STARTBROWSERPOLLERS" =~ ^[0-9]+$ ]] && [ "$ZBX_STARTBROWSERPOLLERS" -ge 1 ] && [ "$ZBX_STARTBROWSERPOLLERS" -le 1000 ]; then
        break
    else
        log_error "O número de pollers deve ser um número inteiro entre 1 e 1000."
    fi
done

# 4.7 Criptografia TLS
echo ""
echo -e "${BOLD}Configuração de Criptografia TLS:${NC}"
echo "  1) Sem Criptografia (Padrão)"
echo "  2) TLS com PSK (Pre-Shared Key)"
echo "  3) TLS com Certificados Digitais X.509"
read -rp "Selecione a opção de criptografia (1, 2 ou 3) [padrão: 1]: " INPUT_TLS_OPT
TLS_OPT="${INPUT_TLS_OPT:-1}"

# Variáveis TLS
ZBX_TLSCONNECT="unencrypted"
ZBX_TLSACCEPT="unencrypted"
ZBX_TLSPSKIDENTITY=""
ZBX_TLSPSKFILE=""
ZBX_TLSCAFILE=""
ZBX_TLSCERTFILE=""
ZBX_TLSKEYFILE=""
ZBX_TLSSERVERCERTISSUER=""
ZBX_TLSSERVERCERTSUBJECT=""

CERTS_DIR="${INSTALL_DIR}/certs"
mkdir -p "$CERTS_DIR"

if [ "$TLS_OPT" == "2" ]; then
    echo -e "\n${BOLD}[Configuração TLS PSK]${NC}"
    DEFAULT_PSK_IDENTITY="PSK-${ZBX_HOSTNAME}"
    read -rp "Identidade PSK (TLS_PSK_IDENTITY) [padrão: ${DEFAULT_PSK_IDENTITY}]: " INPUT_PSK_IDENTITY
    ZBX_TLSPSKIDENTITY="${INPUT_PSK_IDENTITY:-$DEFAULT_PSK_IDENTITY}"

    echo "Deseja gerar automaticamente uma chave PSK hexadecimal de 32 bytes (64 caracteres)?"
    read -rp "(S/n): " AUTO_GEN_PSK
    AUTO_GEN_PSK="${AUTO_GEN_PSK:-S}"

    PSK_FILE_PATH="${CERTS_DIR}/zabbix_proxy.psk"
    if [[ "$AUTO_GEN_PSK" =~ ^[sS]$ ]]; then
        HEX_KEY=$(openssl rand -hex 32)
        echo "$HEX_KEY" > "$PSK_FILE_PATH"
        log_success "Chave PSK gerada com sucesso!"
        echo -e "${YELLOW}Chave PSK: ${HEX_KEY}${NC}"
        echo -e "${YELLOW}Identidade: ${ZBX_TLSPSKIDENTITY}${NC}"
        echo "Guarde esses valores para cadastrar o Proxy na interface web do Zabbix."
    else
        while true; do
            read -rp "Insira a chave PSK (hexadecimal): " MANUAL_PSK
            if [ -n "$MANUAL_PSK" ]; then
                echo "$MANUAL_PSK" > "$PSK_FILE_PATH"
                break
            else
                log_error "A chave PSK não pode ser vazia."
            fi
        done
    fi

    chmod 600 "$PSK_FILE_PATH"
    # UID 1997 é o usuário padrão 'zabbix' dentro do container Alpine
    chown -R 1997:1997 "$CERTS_DIR" 2>/dev/null || chmod -R 755 "$CERTS_DIR"

    ZBX_TLSCONNECT="psk"
    ZBX_TLSACCEPT="psk"
    ZBX_TLSPSKFILE="zabbix_proxy.psk"

elif [ "$TLS_OPT" == "3" ]; then
    echo -e "\n${BOLD}[Configuração TLS Certificados X.509]${NC}"
    echo "Informe os caminhos completos dos arquivos no sistema:"

    while true; do
        read -rp "Caminho do arquivo de CA (ex: /root/zabbix_ca.crt): " SRC_CA
        if [ -f "$SRC_CA" ]; then
            cp "$SRC_CA" "${CERTS_DIR}/zabbix_ca.crt"
            break
        else
            log_error "Arquivo não encontrado: $SRC_CA"
        fi
    done

    while true; do
        read -rp "Caminho do Certificado do Proxy (ex: /root/zabbix_proxy.crt): " SRC_CERT
        if [ -f "$SRC_CERT" ]; then
            cp "$SRC_CERT" "${CERTS_DIR}/zabbix_proxy.crt"
            break
        else
            log_error "Arquivo não encontrado: $SRC_CERT"
        fi
    done

    while true; do
        read -rp "Caminho da Chave Privada do Proxy (ex: /root/zabbix_proxy.key): " SRC_KEY
        if [ -f "$SRC_KEY" ]; then
            cp "$SRC_KEY" "${CERTS_DIR}/zabbix_proxy.key"
            break
        else
            log_error "Arquivo não encontrado: $SRC_KEY"
        fi
    done

    read -rp "TLS Server Cert Issuer (opcional, Enter para pular): " ZBX_TLSSERVERCERTISSUER
    read -rp "TLS Server Cert Subject (opcional, Enter para pular): " ZBX_TLSSERVERCERTSUBJECT

    chmod 600 "${CERTS_DIR}/zabbix_proxy.key"
    chmod 644 "${CERTS_DIR}/zabbix_ca.crt" "${CERTS_DIR}/zabbix_proxy.crt"
    chown -R 1997:1997 "$CERTS_DIR" 2>/dev/null || chmod -R 755 "$CERTS_DIR"

    ZBX_TLSCONNECT="cert"
    ZBX_TLSACCEPT="cert"
    ZBX_TLSCAFILE="zabbix_ca.crt"
    ZBX_TLSCERTFILE="zabbix_proxy.crt"
    ZBX_TLSKEYFILE="zabbix_proxy.key"

else
    log_info "Comunicação configurada sem criptografia TLS."
fi

# 5. Criação da estrutura de diretórios
log_info "Criando diretórios de trabalho em ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
mkdir -p "${CERTS_DIR}"

# 6. Geração do arquivo .env
log_info "Gerando arquivo de configuração .env..."
cat <<EOF > "${INSTALL_DIR}/.env"
# Configurações geradas automaticamente pelo instalador do Zabbix Proxy
INSTALL_DIR=${INSTALL_DIR}
ZBX_HOSTNAME=${ZBX_HOSTNAME}
ZBX_SERVER_HOST=${ZBX_SERVER_HOST}
ZBX_SERVER_PORT=${ZBX_SERVER_PORT}
ZBX_PROXYMODE=${ZBX_PROXYMODE}
PROXY_PORT=${PROXY_PORT}
SELENIUM_PORT=${SELENIUM_PORT}
ZBX_STARTBROWSERPOLLERS=${ZBX_STARTBROWSERPOLLERS}

# Configurações TLS
ZBX_TLSCONNECT=${ZBX_TLSCONNECT}
ZBX_TLSACCEPT=${ZBX_TLSACCEPT}
ZBX_TLSPSKIDENTITY=${ZBX_TLSPSKIDENTITY}
ZBX_TLSPSKFILE=${ZBX_TLSPSKFILE}
ZBX_TLSCAFILE=${ZBX_TLSCAFILE}
ZBX_TLSCERTFILE=${ZBX_TLSCERTFILE}
ZBX_TLSKEYFILE=${ZBX_TLSKEYFILE}
ZBX_TLSSERVERCERTISSUER=${ZBX_TLSSERVERCERTISSUER}
ZBX_TLSSERVERCERTSUBJECT=${ZBX_TLSSERVERCERTSUBJECT}
EOF

chmod 600 "${INSTALL_DIR}/.env"

# 7. Geração do docker-compose.yml
log_info "Gerando arquivo docker-compose.yml..."
cat <<'EOF' > "${INSTALL_DIR}/docker-compose.yml"
services:
  selenium-chrome:
    image: selenium/standalone-chrome:latest
    container_name: selenium-chrome
    restart: unless-stopped
    shm_size: 2gb
    ports:
      - "${SELENIUM_PORT}:4444"
    networks:
      - zabbix-net
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:4444/status || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  zabbix-proxy:
    image: zabbix/zabbix-proxy-sqlite3:alpine-7.0-latest
    container_name: zabbix-proxy
    restart: unless-stopped
    ports:
      - "${PROXY_PORT}:10051"
    volumes:
      - zabbix-proxy-data:/var/lib/zabbix
      - ./certs:/var/lib/zabbix/enc:ro
    environment:
      - ZBX_HOSTNAME=${ZBX_HOSTNAME}
      - ZBX_SERVER_HOST=${ZBX_SERVER_HOST}
      - ZBX_SERVER_PORT=${ZBX_SERVER_PORT}
      - ZBX_PROXYMODE=${ZBX_PROXYMODE}
      - ZBX_WEBDRIVERURL=http://selenium-chrome:4444
      - ZBX_STARTBROWSERPOLLERS=${ZBX_STARTBROWSERPOLLERS}
      - ZBX_TLSCONNECT=${ZBX_TLSCONNECT}
      - ZBX_TLSACCEPT=${ZBX_TLSACCEPT}
      - ZBX_TLSPSKIDENTITY=${ZBX_TLSPSKIDENTITY}
      - ZBX_TLSPSKFILE=${ZBX_TLSPSKFILE}
      - ZBX_TLSCAFILE=${ZBX_TLSCAFILE}
      - ZBX_TLSCERTFILE=${ZBX_TLSCERTFILE}
      - ZBX_TLSKEYFILE=${ZBX_TLSKEYFILE}
      - ZBX_TLSSERVERCERTISSUER=${ZBX_TLSSERVERCERTISSUER}
      - ZBX_TLSSERVERCERTSUBJECT=${ZBX_TLSSERVERCERTSUBJECT}
    depends_on:
      selenium-chrome:
        condition: service_healthy
    networks:
      - zabbix-net

volumes:
  zabbix-proxy-data:
    driver: local

networks:
  zabbix-net:
    driver: bridge
EOF

# 8. Inicialização dos Containers com Docker Compose
log_info "Iniciando containers do Zabbix Proxy e Selenium..."
cd "${INSTALL_DIR}"
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

log_info "Aguardando inicialização dos serviços..."
sleep 5

# 9. Verificação de status
echo ""
echo -e "${CYAN}${BOLD}Status dos Containers:${NC}"
docker compose ps

echo ""
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo -e "${GREEN}${BOLD}       INSTALAÇÃO CONCLUÍDA COM SUCESSO!                          ${NC}"
echo -e "${GREEN}${BOLD}==================================================================${NC}"
echo ""
echo -e "Diretório do projeto:   ${BOLD}${INSTALL_DIR}${NC}"
echo -e "Nome do Proxy:          ${BOLD}${ZBX_HOSTNAME}${NC}"
echo -e "Zabbix Server:          ${BOLD}${ZBX_SERVER_HOST}:${ZBX_SERVER_PORT}${NC}"
echo -e "Modo do Proxy:          ${BOLD}$([ "$ZBX_PROXYMODE" == "0" ] && echo "Ativo" || echo "Passivo")${NC}"
echo -e "Porta Proxy (Host):     ${BOLD}${PROXY_PORT}${NC}"
echo -e "Porta Selenium (Host):  ${BOLD}${SELENIUM_PORT}${NC}"
echo -e "Tipo de Criptografia:   ${BOLD}${ZBX_TLSCONNECT}${NC}"
if [ "$ZBX_TLSCONNECT" == "psk" ]; then
    echo -e "PSK Identity:           ${BOLD}${ZBX_TLSPSKIDENTITY}${NC}"
    echo -e "Arquivo PSK:            ${BOLD}${INSTALL_DIR}/certs/zabbix_proxy.psk${NC}"
fi

echo ""
echo -e "${BOLD}Comandos úteis para manutenção:${NC}"
echo "  Ver logs do Proxy:       cd ${INSTALL_DIR} && docker compose logs -f zabbix-proxy"
echo "  Ver logs do Selenium:    cd ${INSTALL_DIR} && docker compose logs -f selenium-chrome"
echo "  Parar serviços:          cd ${INSTALL_DIR} && docker compose down"
echo "  Reiniciar serviços:      cd ${INSTALL_DIR} && docker compose restart"
echo "  Status do Selenium:      curl http://localhost:${SELENIUM_PORT}/status"
echo ""

# Instalador Rápido: Zabbix Proxy 7.0 LTS + Selenium Standalone em Docker

Script de instalação automatizada e interativa para ambientes **Ubuntu e Debian**. Implanta o **Zabbix Proxy 7.0 LTS (SQLite3)** integrado ao **Selenium Standalone Chrome** para monitoramento web moderno e itens do tipo *Browser* via WebDriver.

---

## 🚀 Requisitos Mínimos

- **Sistema Operacional**: Ubuntu 20.04+, 22.04+, 24.04+ ou Debian 11 (Bullseye), 12 (Bookworm).
- **Acesso**: Privilégios de `root` ou `sudo`.
- **Portas de Rede**:
  - Porta de saída para o Zabbix Server (padrão `10051/TCP`).
  - Porta local de entrada para o Zabbix Proxy se configurado em modo Passivo.
  - Porta local do Selenium (padrão `4444/TCP`).

---

## 📥 Como Executar

### Opção 1: Execução direta no servidor
```bash
# Clone ou baixe o script na máquina de destino
curl -fsSL https://raw.githubusercontent.com/.../install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
```

### Opção 2: Se já estiver no servidor
```bash
sudo bash install.sh
```

---

## ⚙️ Parâmetros Solicitados no Assistente

| Parâmetro | Descrição | Valor Padrão | Validação |
| :--- | :--- | :--- | :--- |
| **Diretório de instalação** | Onde o `.env`, `docker-compose.yml` e certificados ficarão armazenados | `/opt/zabbix-proxy` | - |
| **Nome do Proxy** | Hostname cadastrado na interface web do Zabbix Server | *(Sem padrão - Obrigatório)* | Não pode ser vazio |
| **Endereço do Zabbix Server** | IP ou FQDN do Zabbix Server central | *(Obrigatório)* | Validação regex de IPv4/FQDN e ping de conectividade |
| **Porta do Zabbix Server** | Porta TCP do Zabbix Server | `10051` | Número inteiro entre 1 e 65535 |
| **Modo do Proxy** | `1` = Passivo (aguarda conexão) ou `0` = Ativo (conecta no servidor) | `1` (Passivo) | Apenas 0 ou 1 |
| **Porta Local do Proxy** | Porta exposta no host para escuta do Proxy | `10051` | Número inteiro entre 1 e 65535 |
| **Porta Local do Selenium** | Porta exposta no host para o Selenium Standalone | `4444` | Número inteiro entre 1 e 65535 (não pode ser igual à do proxy) |
| **Browser Pollers** | Número de processos dedicados a itens do tipo Browser | `2` | Número inteiro positivo (1 a 1000) |
| **Criptografia TLS** | `1` = Sem criptografia, `2` = TLS PSK, `3` = TLS Certificados X.509 | `1` (Sem Criptografia) | - |

---

## 🔐 Opções de Criptografia TLS

1. **Sem Criptografia (Padrão)**:
   - Recomendado para testes ou túneis VPN internos (ex: WireGuard/IPsec já criptografados).
2. **TLS com PSK (Pre-Shared Key)**:
   - O instalador oferece a opção de gerar automaticamente uma chave hexadecimal criptograficamente segura de 32 bytes (`openssl rand -hex 32`) ou inserir uma chave existente.
   - Os arquivos de chave são gravados com permissões seguras `600` e associados ao usuário do container.
3. **TLS com Certificados X.509**:
   - Solicita o caminho do arquivo CA, do Certificado e da Chave Privada.
   - Copia os certificados para a pasta `certs/` do projeto e configura os parâmetros `ZBX_TLSCAFILE`, `ZBX_TLSCERTFILE` e `ZBX_TLSKEYFILE`.

---

## 📂 Estrutura de Arquivos Gerada

```
/opt/zabbix-proxy/
├── .env                    # Variáveis de ambiente protegidas (chmod 600)
├── docker-compose.yml      # Definição dos containers proxy e selenium
├── certs/                  # Armazenamento de chaves e certificados TLS
│   ├── zabbix_proxy.psk    # (se selecionado PSK)
│   ├── zabbix_ca.crt       # (se selecionado X.509)
│   ├── zabbix_proxy.crt    # (se selecionado X.509)
│   └── zabbix_proxy.key    # (se selecionado X.509)
└── zbx_env/                # Volumes de persistência do SQLite
```

---

## 🛠️ Comandos de Manutenção

Navegue até o diretório onde o proxy foi instalado (ex: `/opt/zabbix-proxy`):

```bash
cd /opt/zabbix-proxy

# Visualizar status dos containers
docker compose ps

# Acompanhar logs do Zabbix Proxy em tempo real
docker compose logs -f zabbix-proxy

# Acompanhar logs do Selenium em tempo real
docker compose logs -f selenium-chrome

# Reiniciar os serviços
docker compose restart

# Parar os serviços
docker compose down

# Iniciar os serviços
docker compose up -d

# Testar saúde do Selenium Chrome
curl http://localhost:4444/status
```

---

## 🌐 Configuração na Interface Web do Zabbix Server

1. Acesse o Zabbix Frontend: **Administration (ou Gerenciamento) -> Proxies**.
2. Clique em **Create proxy**:
   - **Proxy name**: Deve ser idêntico ao `ZBX_HOSTNAME` informado no script.
   - **Proxy mode**: Ativo (Active) ou Passivo (Passive), conforme configurado.
   - **Encryption**:
     - Se escolheu **Sem Criptografia**: marque `No encryption`.
     - Se escolheu **PSK**: marque `PSK`, insira a mesma **PSK identity** e a **PSK (chave hex)** exibida ao término do script.
     - Se escolheu **Certificate**: selecione `Certificate` e preencha os dados do Issuer/Subject se aplicável.
3. Salve e aguarde 1 a 2 minutos para o primeiro envio de dados do proxy para o servidor.

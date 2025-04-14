# Script de Backup PostgreSQL com Upload para S3

Este script permite realizar backups diários automatizados de um banco de dados PostgreSQL, com compactação, gerenciamento de retenção local e upload para Amazon S3.

## Características

- ✅ Backup completo de banco de dados PostgreSQL usando `pg_dump`
- ✅ Compactação em formato `.tar.gz`
- ✅ Registros detalhados em arquivo de log
- ✅ Retenção local configurável (mantém apenas os N backups mais recentes)
- ✅ Upload automático para Amazon S3
- ✅ Retenção configurável no S3 (baseada em dias)
- ✅ Notificações de erro via webhook (POST JSON)
- ✅ Compatível com cron para execução automatizada

## Requisitos

- Sistema Ubuntu (ou outra distribuição Linux baseada em Debian)
- PostgreSQL client instalado
- s3cmd configurado para acesso ao Amazon S3
- curl para notificações

## Instalação das Dependências

### 1. Atualizar repositórios

```bash
sudo apt update
```

### 2. Instalar PostgreSQL client

Se você já tem o servidor PostgreSQL instalado, o cliente provavelmente já está disponível. Caso contrário:

```bash
sudo apt install postgresql-client
```

### 3. Instalar s3cmd

```bash
sudo apt install s3cmd
```

### 4. Instalar curl (geralmente já vem instalado)

```bash
sudo apt install curl
```

## Configuração do s3cmd

Antes de usar o script, você precisa configurar o s3cmd com suas credenciais AWS:

```bash
s3cmd --configure
```

O comando acima solicitará:
- Access Key e Secret Key da AWS
- Região do S3
- Configurações de endpoint (use o padrão para AWS S3)
- Outras configurações opcionais

Suas configurações serão salvas em `~/.s3cfg`.

## Instalação do Script

### 1. Baixar o script

Salve o script `postgres_backup.sh` em um local adequado, por exemplo:

```bash
sudo mkdir -p /usr/local/scripts
sudo cp postgres_backup.sh /usr/local/scripts/
```

### 2. Tornar o script executável

```bash
sudo chmod +x /usr/local/scripts/postgres_backup.sh
```

### 3. Editar as configurações

Abra o script e ajuste as configurações no início:

```bash
sudo nano /usr/local/scripts/postgres_backup.sh
```

#### Configurações importantes:

```bash
# Diretório onde os backups serão armazenados
BACKUP_DIR="/var/backups/postgres"
# Nome do banco de dados
DB_NAME="seu_banco_de_dados"
# Usuário do PostgreSQL
DB_USER="seu_usuario"
# Senha do PostgreSQL (considere usar variáveis de ambiente ou .pgpass para maior segurança)
DB_PASSWORD="sua_senha"
# Host do PostgreSQL
DB_HOST="localhost"
# Porta do PostgreSQL
DB_PORT="5432"
# URL para enviar notificações de erro
NOTIFICATION_URL="https://sua-url-de-notificacao.com/api/notify"
# Quantidade de backups a manter
KEEP_BACKUPS=5
# Arquivo de log
LOG_FILE="/var/log/postgres_backup.log"
# Configurações do S3
S3_BUCKET="s3://seu-bucket-s3/backups/postgres"
# Número de dias para reter backups no S3 (0 = manter indefinidamente)
S3_RETENTION_DAYS=30
```

### 4. Criar diretórios necessários

```bash
sudo mkdir -p /var/backups/postgres
sudo touch /var/log/postgres_backup.log
sudo chown $(whoami) /var/log/postgres_backup.log
```

## Configuração do cron para execução automática

Para configurar o script para ser executado automaticamente todos os dias:

### 1. Editar o crontab

```bash
sudo crontab -e
```

### 2. Adicionar a linha para execução diária (exemplo: às 2 da manhã)

```
0 2 * * * /usr/local/scripts/postgres_backup.sh
```

## Métodos alternativos para lidar com a senha do PostgreSQL

### Método 1: Usar arquivo .pgpass

Em vez de armazenar a senha no script, você pode usar um arquivo `.pgpass` no diretório home do usuário que executará o script:

1. Criar o arquivo `.pgpass` (substitua os valores por seus dados reais):

```bash
echo "hostname:port:database:username:password" > ~/.pgpass
chmod 600 ~/.pgpass
```

2. Remover a linha `export PGPASSWORD="$DB_PASSWORD"` do script
3. Remover a linha `unset PGPASSWORD` do script

### Método 2: Usar variável de ambiente

Você pode definir a variável PGPASSWORD no crontab:

```
0 2 * * * PGPASSWORD="sua_senha" /usr/local/scripts/postgres_backup.sh
```

E então remover as linhas de exportação/unset no script.

## Testando o script

Execute o script manualmente para verificar se tudo está funcionando corretamente:

```bash
sudo /usr/local/scripts/postgres_backup.sh
```

Verifique o arquivo de log para confirmar que o backup foi criado com sucesso:

```bash
tail -n 20 /var/log/postgres_backup.log
```

## Resolução de Problemas

### Problemas de permissão

Se o script estiver falhando devido a problemas de permissão:

```bash
sudo chown -R $(whoami):$(whoami) /var/backups/postgres
```

### Problemas com s3cmd

Verifique se o s3cmd está configurado corretamente:

```bash
s3cmd ls
```

Se receber um erro, reconfigure o s3cmd:

```bash
s3cmd --configure
```

### Falhas no PostgreSQL

Verifique se as credenciais do PostgreSQL estão corretas e se o usuário tem permissão para realizar dumps:

```bash
pg_dump -h localhost -U seu_usuario -d seu_banco_de_dados -f /tmp/test_dump.sql
```

## Segurança

- Não armazene senhas diretamente no script em ambientes de produção
- Assegure-se de que o arquivo `postgres_backup.sh` tenha permissões restritas (ex: 700)
- Considere o uso de IAM roles para o S3 em vez de chaves de acesso codificadas

## Personalização

O script pode ser personalizado para:

- Adicionar compressão com níveis diferentes
- Excluir determinadas tabelas do backup
- Implementar rotinas de backup incremental
- Adicionar confirmação por e-mail quando o backup for bem-sucedido

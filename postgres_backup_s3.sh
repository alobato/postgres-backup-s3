#!/bin/bash

# -------------- Configurações --------------
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

# -------------- Funções --------------

# Função para registrar logs
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Função para enviar notificação de erro
notify_error() {
    local message="$1"
    
    curl -s -X POST "$NOTIFICATION_URL" \
        -H "Content-Type: application/json" \
        -d "{\"error\": true, \"message\": \"$message\", \"database\": \"$DB_NAME\", \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"}" > /dev/null
    
    log "Notificação de erro enviada: $message"
}

# Função para fazer upload para o S3
upload_to_s3() {
    local file="$1"
    local full_path="$BACKUP_DIR/$file"
    
    log "Iniciando upload para S3: $file -> $S3_BUCKET"
    
    # Verificar se s3cmd está instalado
    if ! command -v s3cmd &> /dev/null; then
        log "ERRO: s3cmd não está instalado. Pulando upload para S3."
        notify_error "Falha no upload para S3: s3cmd não está instalado"
        return 1
    fi
    
    # Fazer upload para o S3
    s3cmd put "$full_path" "$S3_BUCKET/" --quiet
    
    if [ $? -eq 0 ]; then
        log "Upload para S3 concluído com sucesso: $file"
        return 0
    else
        log "ERRO: Falha no upload para S3: $file"
        notify_error "Falha no upload para S3: $file"
        return 1
    fi
}

# -------------- Início do Script --------------

# Verifica se o diretório de backup existe, se não, cria
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    log "Diretório de backup criado: $BACKUP_DIR"
fi

# Nome do arquivo de backup com timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="${DB_NAME}_${TIMESTAMP}.sql"
COMPRESSED_BACKUP="${BACKUP_FILENAME}.tar.gz"

# Log de início do backup
log "Iniciando backup do banco $DB_NAME"

# Executa o pg_dump
export PGPASSWORD="$DB_PASSWORD"
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -F p -f "$BACKUP_DIR/$BACKUP_FILENAME" "$DB_NAME"

# Verifica se o backup foi realizado com sucesso
if [ $? -eq 0 ]; then
    log "Backup do banco $DB_NAME concluído com sucesso"
    
    # Compacta o arquivo SQL
    tar -czf "$BACKUP_DIR/$COMPRESSED_BACKUP" -C "$BACKUP_DIR" "$BACKUP_FILENAME"
    
    if [ $? -eq 0 ]; then
        log "Arquivo de backup compactado com sucesso: $COMPRESSED_BACKUP"
        
        # Remove o arquivo SQL original
        rm "$BACKUP_DIR/$BACKUP_FILENAME"
        log "Arquivo SQL original removido"
        
        # Upload para o S3
        upload_to_s3 "$COMPRESSED_BACKUP"
        
        # Remove backups antigos mantendo apenas os KEEP_BACKUPS mais recentes
        cd "$BACKUP_DIR" || exit 1
        ls -t *.tar.gz | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm
        
        REMAINING_BACKUPS=$(ls -1 *.tar.gz | wc -l)
        log "Limpeza local concluída. Total de backups mantidos: $REMAINING_BACKUPS"
        
        # Limpar backups antigos no S3 se configurado
        if [ $S3_RETENTION_DAYS -gt 0 ]; then
            log "Iniciando limpeza de backups antigos no S3 (mais antigos que $S3_RETENTION_DAYS dias)"
            s3cmd ls "$S3_BUCKET/" | grep -i ".tar.gz$" | awk '{print $4}' | while read -r s3_file; do
                # Extrai a data do nome do arquivo (assume formato padrão com timestamp)
                file_name=$(basename "$s3_file")
                file_date=$(echo "$file_name" | grep -o "[0-9]\{8\}_[0-9]\{6\}" | cut -d_ -f1)
                
                if [ -n "$file_date" ]; then
                    # Converte data do arquivo para timestamp unix
                    file_year=${file_date:0:4}
                    file_month=${file_date:4:2}
                    file_day=${file_date:6:2}
                    file_timestamp=$(date -d "$file_year-$file_month-$file_day" +%s 2>/dev/null)
                    
                    # Calcula timestamp de corte (hoje menos dias de retenção)
                    cutoff_timestamp=$(date -d "-$S3_RETENTION_DAYS days" +%s)
                    
                    # Se o arquivo for mais antigo que o período de retenção, exclui
                    if [ -n "$file_timestamp" ] && [ "$file_timestamp" -lt "$cutoff_timestamp" ]; then
                        log "Removendo backup antigo do S3: $file_name"
                        s3cmd rm "$s3_file" --quiet
                    fi
                fi
            done
            log "Limpeza de backups antigos no S3 concluída"
        fi
    else
        ERROR_MSG="Falha ao compactar o arquivo de backup $BACKUP_FILENAME"
        log "$ERROR_MSG"
        notify_error "$ERROR_MSG"
        
        # Tenta remover o arquivo de backup incompleto
        rm "$BACKUP_DIR/$BACKUP_FILENAME"
    fi
else
    ERROR_MSG="Falha ao criar backup do banco $DB_NAME"
    log "$ERROR_MSG"
    notify_error "$ERROR_MSG"
fi

# Limpa variável de senha
unset PGPASSWORD

log "Processo de backup finalizado"
exit 0

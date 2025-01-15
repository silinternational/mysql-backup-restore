#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Generate UUID v4
generate_uuid() {
    if [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        date +%s%N | sha256sum | head -c 32
    fi
}

# Parse Sentry DSN
parse_sentry_dsn() {
    local dsn=$1
    # Extract components using basic string manipulation
    local project_id=$(echo "$dsn" | sed 's/.*\///')
    local key=$(echo "$dsn" | sed 's|https://||' | sed 's/@.*//')
    local host=$(echo "$dsn" | sed 's|https://[^@]*@||' | sed 's|/.*||')
    echo "$project_id|$key|$host"
}

# Send error to Sentry via REST API
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"
    
    # Check if SENTRY_DSN is set
    if [ -z "${SENTRY_DSN:-}" ]; then
        log "ERROR: SENTRY_DSN not set"
        return 1
    fi

    # Parse DSN
    local dsn_parts=($(parse_sentry_dsn "$SENTRY_DSN" | tr '|' ' '))
    local project_id="${dsn_parts[0]}"
    local key="${dsn_parts[1]}"
    local host="${dsn_parts[2]}"

    # Generate event ID and timestamp
    local event_id=$(generate_uuid)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # Create JSON payload
    local payload=$(cat <<EOF
{
    "event_id": "${event_id}",
    "timestamp": "${timestamp}",
    "level": "error",
    "message": "${error_message}",
    "logger": "mysql-backup",
    "platform": "bash",
    "environment": "production",
    "tags": {
        "database": "${db_name}",
        "status_code": "${status_code}",
        "host": "$(hostname)"
    },
    "extra": {
        "script_path": "$0",
        "timestamp": "${timestamp}"
    }
}
EOF
)

    # Send to Sentry
    local response
    response=$(curl -s -X POST \
        "https://${host}/api/${project_id}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${key}, sentry_client=bash-script/1.0" \
        -d "${payload}" 2>&1)

    if [ $? -ne 0 ]; then
        log "ERROR: Failed to send event to Sentry: ${response}"
        return 1
    fi

    log "Error event sent to Sentry: ${error_message}"
}

# Send success to Sentry
send_success_to_sentry() {
    if [ -z "${SENTRY_DSN:-}" ]; then
        log "ERROR: SENTRY_DSN not set"
        return 1
    fi

    # Parse DSN
    local dsn_parts=($(parse_sentry_dsn "$SENTRY_DSN" | tr '|' ' '))
    local project_id="${dsn_parts[0]}"
    local key="${dsn_parts[1]}"
    local host="${dsn_parts[2]}"

    # Generate event ID and timestamp
    local event_id=$(generate_uuid)
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # Create success payload
    local success_payload=$(cat <<EOF
{
    "event_id": "${event_id}",
    "timestamp": "${timestamp}",
    "level": "info",
    "message": "Backup completed successfully",
    "logger": "mysql-backup",
    "platform": "bash",
    "environment": "production",
    "tags": {
        "status": "success",
        "databases": "${DB_NAMES}",
        "host": "$(hostname)"
    }
}
EOF
)

    # Send to Sentry
    local response
    response=$(curl -s -X POST \
        "https://${host}/api/${project_id}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${key}, sentry_client=bash-script/1.0" \
        -d "${success_payload}" 2>&1)

    if [ $? -ne 0 ]; then
        log "ERROR: Failed to send success event to Sentry: ${response}"
        return 1
    fi

    log "Success event sent to Sentry"
}

STATUS=0

log "mysql-backup-restore: backup: Started"

for dbName in ${DB_NAMES}; do
    log "mysql-backup-restore: Backing up ${dbName}"

    start=$(date +%s)
    mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        log "*** START DEBUGGING FOR NON-ZERO STATUS ***"

        # Display update
        uptime
        log ""

        # display free drive space (in megabytes)
        df -m
        log ""

        # display free memory in megabytes
        free -m
        log ""

        # display swap information
        swapon
        log ""

        log "*** END DEBUGGING FOR NON-ZERO STATUS ***"

        error_message="MySQL backup failed for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "mysql-backup-restore: FATAL: Backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else 
        log "mysql-backup-restore: Backup of ${dbName} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${dbName}.sql) bytes)."
    fi

    start=$(date +%s)
    gzip -f /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="Compression failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "mysql-backup-restore: FATAL: Compressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS 
    else
        log "mysql-backup-restore: Compressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    start=$(date +%s)
    s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="S3 copy failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "mysql-backup-restore: FATAL: Copy backup to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "mysql-backup-restore: Copy backup to ${S3_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    if [ "${B2_BUCKET}" != "" ]; then
        start=$(date +%s)
        s3cmd \
        --access_key=${B2_APPLICATION_KEY_ID} \
        --secret_key=${B2_APPLICATION_KEY} \
        --host=${B2_HOST} \
        --host-bucket='%(bucket)s.'"${B2_HOST}" \
        put /tmp/${dbName}.sql.gz s3://${B2_BUCKET}/${dbName}.sql.gz
        STATUS=$?
        end=$(date +%s)
        if [ $STATUS -ne 0 ]; then
            error_message="Backblaze B2 copy failed for database ${dbName} backup"
            error_to_sentry "$error_message" "$dbName" "$STATUS"
            log "mysql-backup-restore: FATAL: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
            exit $STATUS
        else
            log "mysql-backup-restore: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
        fi
    fi
done

# Send success event to Sentry if all operations completed successfully
if [ $STATUS -eq 0 ]; then
    send_success_to_sentry
fi

log "mysql-backup-restore: backup: Completed"
exit $STATUS

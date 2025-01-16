#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}"
}

# Optional Sentry reporting
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"

    # Only attempt Sentry reporting if SENTRY_DSN is configured
    if [ -n "${SENTRY_DSN:-}" ]; then
        if command -v sentry-cli >/dev/null 2>&1; then
            # Use sentry-cli if available
            sentry-cli send-event \
                --level error \
                --message "$error_message" \
                --tag database="$db_name" \
                --tag status="$status_code" \
                --tag host="$(hostname)" \
                --extra script_path="$0" || true  # Don't fail if Sentry reporting fails
        else
            # Log that Sentry reporting was attempted but cli not found
            log "WARN" "Sentry reporting configured but sentry-cli not found"
        fi
    fi
}

# Optional Sentry reporting for successful backups
success_to_sentry() {
    local success_message="$1"
    local db_name="$2"
    local status_code="$3"

    # Only attempt Sentry reporting if SENTRY_DSN is configured
    if [ -n "${SENTRY_DSN:-}" ]; then
        if command -v sentry-cli >/dev/null 2>&1; then
            # Use sentry-cli if available
            sentry-cli send-event \
                --level info \
                --message "$success_message" \
                --tag database="$db_name" \
                --tag status="$status_code" \
                --tag host="$(hostname)" \
                --extra script_path="$0" || true
        else
            # Log that Sentry reporting was attempted but cli not found
            log "WARN" "Sentry reporting configured but sentry-cli not found"
        fi
    fi
}

STATUS=0

log "INFO" "mysql-backup-restore: backup: Started"

for dbName in ${DB_NAMES}; do
    log "INFO" "mysql-backup-restore: Backing up ${dbName}"

    start=$(date +%s)
    mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        log "ERROR" "*** START DEBUGGING FOR NON-ZERO STATUS ***"

        # Display update
        uptime
        log "INFO" ""

        # display free drive space (in megabytes)
        df -m
        log "INFO" ""

        # display free memory in megabytes
        free -m
        log "INFO" ""

        # display swap information
        swapon
        log "INFO" ""

        log "ERROR" "*** END DEBUGGING FOR NON-ZERO STATUS ***"

        error_message="MySQL backup failed for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else 
        success_to_sentry "MySQL backup completed successfully for database ${dbName}" "$dbName" "$STATUS"
        log "INFO" "mysql-backup-restore: Backup of ${dbName} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${dbName}.sql) bytes)."
    fi

    # Compression
    start=$(date +%s)
    gzip -f /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="Compression failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Compressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS 
    else
        success_to_sentry "Compression completed successfully for database ${dbName}" "$dbName" "$STATUS"
        log "INFO" "mysql-backup-restore: Compressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # S3 Upload
    start=$(date +%s)
    s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="S3 copy failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Copy backup to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        success_to_sentry "S3 upload completed successfully for database ${dbName}" "$dbName" "$STATUS"
        log "INFO" "mysql-backup-restore: Copy backup to ${S3_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Backblaze B2 Upload
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
            log "ERROR" "mysql-backup-restore: FATAL: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
            exit $STATUS
        else
            success_to_sentry "Backblaze B2 upload completed successfully for database ${dbName}" "$dbName" "$STATUS"
            log "INFO" "mysql-backup-restore: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
        fi
    fi
done

exit $STATUS

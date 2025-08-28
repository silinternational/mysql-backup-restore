#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}"
}

# Determine whether to use server cert verification
function get_server_cert() {
    MYSQL="mysql"
    if [ -n "$SSL_CA_BASE64" ]; then
        echo "$SSL_CA_BASE64" | base64 -d > /tmp/ca.pem
        MYSQL="mysql --ssl-ca=/tmp/ca.pem"
    fi
}

# Function to remove sensitive values from sentry Event
filter_sensitive_values() {
    local msg="$1"
    for var in AWS_ACCESS_KEY AWS_SECRET_KEY B2_APPLICATION_KEY B2_APPLICATION_KEY_ID MYSQL_PASSWORD; do
        val="${!var}"
        if [ -n "$val" ]; then
            msg="${msg//$val/[FILTERED]}"
        fi
    done
    echo "$msg"
}

# Sentry reporting with validation and backwards compatibility
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"

    error_message=$(filter_sensitive_values "$error_message")

    # Check if SENTRY_DSN is configured - ensures restore continues
    if [ -z "${SENTRY_DSN:-}" ]; then
        log "DEBUG" "Sentry logging skipped - SENTRY_DSN not configured"
        return 0
    fi

    # Validate SENTRY_DSN format
    if ! [[ "${SENTRY_DSN}" =~ ^https://[^@]+@[^/]+/[0-9]+$ ]]; then
        log "WARN" "Invalid SENTRY_DSN format - Sentry logging will be skipped"
        return 0
    fi

    # Attempt to send event to Sentry
    if sentry-cli send-event \
        --message "${error_message}" \
        --level error \
        --tag "database:${db_name}" \
        --tag "status:${status_code}"; then
        log "DEBUG" "Successfully sent error to Sentry - Message: ${error_message}, Database: ${db_name}, Status: ${status_code}"
    else
        log "WARN" "Failed to send error to Sentry, but continuing restore process"
    fi

    return 0
}

STATUS=0

log "INFO" "mysql-backup-restore: restore: Started"

get_server_cert

for dbName in ${DB_NAMES}; do
    log "INFO" "mysql-backup-restore: Restoring ${dbName}"

    # Download backup file
    start=$(date +%s)
    s3cmd get -f ${S3_BUCKET}/${dbName}.sql.gz /tmp/${dbName}.sql.gz
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        error_message="Failed to download backup file for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Copy backup of ${dbName} from ${S3_BUCKET} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Copy backup of ${dbName} from ${S3_BUCKET} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Download checksum file
    start=$(date +%s)
    s3cmd get -f ${S3_BUCKET}/${dbName}.sql.sha256.gz /tmp/${dbName}.sql.sha256.gz
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        error_message="Failed to download checksum file for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Copy checksum of ${dbName} from ${S3_BUCKET} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Copy checksum of ${dbName} from ${S3_BUCKET} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Decompress backup file
    start=$(date +%s)
    gunzip -f /tmp/${dbName}.sql.gz
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        error_message="Failed to decompress backup file for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Decompressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Decompressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Decompress checksum file
    start=$(date +%s)
    gunzip -f /tmp/${dbName}.sql.sha256.gz
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        error_message="Failed to decompress checksum file for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Decompressing checksum of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Decompressing checksum of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Verify checksum
    log "INFO" "mysql-backup-restore: Verifying checksum for ${dbName}"
    cd /tmp || {
        error_message="Failed to change directory to /tmp"
        error_to_sentry "$error_message" "$dbName" "1"
        log "ERROR" "mysql-backup-restore: FATAL: ${error_message}"
        exit 1
    }

    if ! sha256sum -c "${dbName}.sql.sha256"; then
        error_message="Checksum validation failed for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "1"
        log "ERROR" "mysql-backup-restore: FATAL: ${error_message}"
        exit 1
    fi
    log "INFO" "mysql-backup-restore: Checksum verification successful for ${dbName}"

    # Restore database
    start=$(date +%s)
    $MYSQL -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName} < /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        error_message="Failed to restore database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Restore of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Restore of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Clean up temporary files
    rm -f "/tmp/${dbName}.sql" "/tmp/${dbName}.sql.sha256"
    log "DEBUG" "Removed temporary files for ${dbName}"
done

log "INFO" "mysql-backup-restore: restore: Completed"
exit $STATUS

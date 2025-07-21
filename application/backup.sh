#!/usr/bin/env bash

# Initialize logging with timestamp
log() {
    local level="${1:-INFO}"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${level}: ${message}"
}

# Function to detect the appropriate database dump command
function get_database_dump_command() {
    MARIADB=$(which mariadb-dump 2>/dev/null)
    MYSQL=$(which mysqldump 2>/dev/null)
    MARIADB_STAT=$(stat $MARIADB 2>/dev/null | grep file)
    MYSQL_STAT=$(stat $MYSQL 2>/dev/null | grep file)

    # If both exist, prefer mysqldump for MySQL RDS
    if [ -n "$MYSQL_STAT" ] && [ -n "$MARIADB_STAT" ]; then
        DATABASE_DUMP_COMMAND="mysqldump";
        log "INFO" "Both mariadb-dump and mysqldump exist, using ${DATABASE_DUMP_COMMAND} for MySQL RDS"
    elif [ -z "$MYSQL_STAT" ] && [ -n "$MARIADB_STAT" ]; then
        DATABASE_DUMP_COMMAND="mariadb-dump";
        log "INFO" "mariadb-dump exists, using ${DATABASE_DUMP_COMMAND} for MariaDB"
    elif [ -n "$MYSQL_STAT" ] && [ -z "$MARIADB_STAT" ]; then
        DATABASE_DUMP_COMMAND="mysqldump";
        log "INFO" "mysqldump exists, using ${DATABASE_DUMP_COMMAND} for MySQL"
    else
        error_message="Neither mariadb-dump nor mysqldump exist. Backup cannot proceed"
        error_to_sentry "$error_message" "system" 1
        log "ERROR" "Neither mariadb-dump nor mysqldump exist, Backup cannot proceed"
        exit 1
    fi
}

# Determine whether to use server cert verification
function get_server_cert() {
    CA_FLAGS=""
    if [ -n "$SSL_CA_BASE64" ]; then
        echo "$SSL_CA_BASE64" | base64 -d > /tmp/ca.pem
        CA_FLAGS="--ssl-verify-server-cert --ssl-ca=/tmp/ca.pem"
    fi
}

# Sentry reporting with validation and backwards compatibility
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"

    # Check if SENTRY_DSN is configured - ensures backup continues
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
        log "WARN" "Failed to send error to Sentry, but continuing backup process"
    fi

    return 0
}

STATUS=0

log "INFO" "mysql-backup-restore: backup: Started"

# Determine which database dump command to use
DATABASE_DUMP_COMMAND="";
get_database_dump_command;
get_server_cert;
for dbName in ${DB_NAMES}; do
    log "INFO" "mysql-backup-restore: Backing up ${dbName}"

    start=$(date +%s)
    ${DATABASE_DUMP_COMMAND} ${CA_FLAGS} -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql
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
        log "INFO" "mysql-backup-restore: Backup of ${dbName} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${dbName}.sql) bytes)."
    fi

    # Generate checksum for the backup file
    log "INFO" "mysql-backup-restore: Generating checksum for backup file"
    cd /tmp || {
        error_message="Failed to change directory to /tmp"
        error_to_sentry "$error_message" "$dbName" "1"
        log "ERROR" "mysql-backup-restore: FATAL: ${error_message}"
        exit 1
    }

    sha256sum "${dbName}.sql" > "${dbName}.sql.sha256" || {
        error_message="Failed to generate checksum for backup of ${dbName}"
        error_to_sentry "$error_message" "$dbName" "1"
        log "ERROR" "mysql-backup-restore: FATAL: ${error_message}"
        exit 1
    }
    log "DEBUG" "Checksum file contents: $(cat "${dbName}.sql.sha256")"

    # Validate checksum
    log "INFO" "mysql-backup-restore: Validating backup checksum"
    sha256sum -c "${dbName}.sql.sha256" || {
        error_message="Checksum validation failed for backup of ${dbName}"
        error_to_sentry "$error_message" "$dbName" "1"
        log "ERROR" "mysql-backup-restore: FATAL: ${error_message}"
        exit 1
    }
    log "INFO" "mysql-backup-restore: Checksum validation successful"

    # Compress backup file
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
        log "INFO" "mysql-backup-restore: Compressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Compress checksum file separately
    gzip -f "${dbName}.sql.sha256"
    if [ $? -ne 0 ]; then
        log "WARN" "mysql-backup-restore: Failed to compress checksum file, but continuing backup process"
    fi

    # Upload both compressed files to S3
    start=$(date +%s)

    # Upload backup file
    s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}
    STATUS=$?
    if [ $STATUS -ne 0 ]; then
        error_message="S3 copy failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Copy backup to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS)."
        exit $STATUS
    fi

    # Upload checksum file
    s3cmd put /tmp/${dbName}.sql.sha256.gz ${S3_BUCKET}
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="S3 copy failed for database ${dbName} checksum"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        log "ERROR" "mysql-backup-restore: FATAL: Copy checksum to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS)."
        exit $STATUS
    else
        log "INFO" "mysql-backup-restore: Copy backup and checksum to ${S3_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    # Backblaze B2 Upload (Optional)
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
            log "INFO" "mysql-backup-restore: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
        fi
    fi

    # Clean up temporary files
    rm -f "/tmp/${dbName}.sql.gz" "/tmp/${dbName}.sql.sha256.gz"
done

log "INFO" "mysql-backup-restore: backup: Completed"

exit $STATUS;

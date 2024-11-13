#!/usr/bin/env sh
# Error Tracking
if [ ! -z "${ SENTRY_DSN }"]; then
    eval "$(curl -sL https://sentry.io/get-curl.sh)"
    SENTRY_TRACE_ID=$(uuidgen)
fi

# Send error to Sentry
error_to_sentry() {
    local error_message="$1"
    local db_name="$2"
    local status_code="$3"

    if [ ! -z "${ SENTRY_DSN }" ]; then
        curl -X POST "${ SENTRY_DSN }" \
            -H "Content-Type: application/json" \
            -d "{
                \"message\": \"${error_message}\",
                \"level\": \"error\",
                \"extra\": {
                    \"database\": \"${db_name}\",
                    \"status_code\": \"${status_code}\",
                    \"hostname\": \"${HOSTNAME}\",
                    \"trace_id\": \"${SENTRY_TRACE_ID}\"
                    }
}"; fi 

STATUS=0

echo "mysql-backup-restore: backup: Started"

for dbName in ${DB_NAMES}; do
    echo "mysql-backup-restore: Backing up ${dbName}"

    start=$(date +%s)
    mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        echo "*** START DEBUGGING FOR NON-ZERO STATUS ***"

        # Display update
        uptime
        echo

        # display free drive space (in megabytes)
        df -m
        echo

        # display free memory in megabytes
        free -m
        echo

        # display swap information
        swapon
        echo

        echo "*** END DEBUGGING FOR NON-ZERO STATUS ***"

        error_message="MySQL backup failed for database ${dbName}"
        error_to_sentry "$error_message" "$dbName" "$STATUS"

        echo "mysql-backup-restore: FATAL: Backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    fi

    start=$(date +%s)
    gzip -f /tmp/${dbName}.sql
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="Compression failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"
        
        echo "mysql-backup-restore: FATAL: Compressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    fi

    start=$(date +%s)
    s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}
    STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        error_message="S3 copy failed for database ${dbName} backup"
        error_to_sentry "$error_message" "$dbName" "$STATUS"

        echo "mysql-backup-restore: FATAL: Copy backup to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
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

            echo "mysql-backup-restore: FATAL: Copy backup to Backblaze B2 bucket ${B2_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
            exit $STATUS
        fi
    fi

done

echo "mysql-backup-restore: backup: Completed"
exit $STATUS

#!/usr/bin/env sh

STATUS=0

echo "mysql-backup-restore: backup: Started"

for dbName in ${DB_NAMES}; do
    echo "mysql-backup-restore: Backing up ${dbName}"

    start=$(date +%s)
    mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql || STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Backup of ${dbName} completed in $(expr ${end} - ${start}) seconds, ($(stat -c %s /tmp/${dbName}.sql) bytes)."
    fi

    start=$(date +%s)
    gzip -f /tmp/${dbName}.sql || STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Compressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Compressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    start=$(date +%s)
    s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET} || STATUS=$?
    end=$(date +%s)
    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Copy backup to ${S3_BUCKET} of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Copy backup to ${S3_BUCKET} of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi
done

echo "mysql-backup-restore: backup: Completed"
exit $STATUS

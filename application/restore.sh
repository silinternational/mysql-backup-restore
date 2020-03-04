#!/usr/bin/env sh

STATUS=0

echo "mysql-backup-restore: restore: Started"

for dbName in ${DB_NAMES}; do
    echo "mysql-backup-restore: Restoring ${dbName}"

    start=$(date +%s)
    s3cmd get -f ${S3_BUCKET}/${dbName}.sql.gz /tmp/${dbName}.sql.gz || STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Copy backup of ${dbName} from ${S3_BUCKET} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Copy backup of ${dbName} from ${S3_BUCKET} completed in $(expr ${end} - ${start}) seconds."
    fi

    start=$(date +%s)
    gunzip -f /tmp/${dbName}.sql.gz || STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Decompressing backup of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Decompressing backup of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi

    start=$(date +%s)
    $(mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName} < /tmp/${dbName}.sql) || STATUS=$?
    end=$(date +%s)

    if [ $STATUS -ne 0 ]; then
        echo "mysql-backup-restore: FATAL: Restore of ${dbName} returned non-zero status ($STATUS) in $(expr ${end} - ${start}) seconds."
        exit $STATUS
    else
        echo "mysql-backup-restore: Restore of ${dbName} completed in $(expr ${end} - ${start}) seconds."
    fi
done

echo "mysql-backup-restore: restore: Completed"
exit $STATUS

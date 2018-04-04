#!/usr/bin/env sh

for dbName in ${DB_NAMES}; do
    logger -p user.info "backing up ${dbName}..."

    start=$(date +%s)
    runny $(mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${MYSQL_DUMP_ARGS} ${dbName} > /tmp/${dbName}.sql)
    end=$(date +%s)
    logger -p user.info "${dbName} backed up ($(stat -c %s /tmp/${dbName}.sql) bytes) in $(expr ${end} - ${start}) seconds."

    runny gzip -f /tmp/${dbName}.sql
    runny s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}

    logger -p user.info "${dbName} backup stored in ${S3_BUCKET}."
done

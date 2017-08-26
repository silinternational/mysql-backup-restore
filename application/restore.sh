#!/usr/bin/env sh

for dbName in ${DB_NAMES}; do
    logger -p user.info "restoring ${dbName}..."

    runny s3cmd get -f ${S3_BUCKET}/${dbName}.sql.gz /tmp/${dbName}.sql.gz
    runny gunzip -f /tmp/${dbName}.sql.gz

    start=$(date +%s)
    runny $(mysql -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName} < /tmp/${dbName}.sql)
    end=$(date +%s)

    logger -p user.info "${dbName} restored in $(expr ${end} - ${start}) seconds."
done

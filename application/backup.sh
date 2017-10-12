#!/usr/bin/env sh

if [[ "x$DB_ENGINE" == "x" ]]; then
  DB_ENGINE="MYSQL"
fi

if [[ "$DB_ENGINE" == "MYSQL" ]]; then
  DUMP_CMD='mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName}'
elif [[ "$DB_ENGINE" == "PGSQL" ]]; then
  DUMP_CMD='pg_dump -U ${DB_USER} -h ${DB_HOST} ${DB_NAME}'
fi

for dbName in ${DB_NAMES}; do
    logger -p user.info "backing up ${dbName}..."

    start=$(date +%s)
    runny $(${DUMP_CMD} > /tmp/${dbName}.sql)
    end=$(date +%s)
    logger -p user.info "${dbName} backed up ($(stat -c %s /tmp/${dbName}.sql) bytes) in $(expr ${end} - ${start}) seconds."

    runny gzip -f /tmp/${dbName}.sql
    runny s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}

    logger -p user.info "${dbName} backup stored in ${S3_BUCKET}."
done

#!/usr/bin/env sh

for dbName in ${DB_NAMES}; do
    if [ ${MODE} = "backup" ]; then
        logger -p user.info "backing up ${dbName}..."

        start=$(date +%s)
        runny $(mysqldump -h ${MYSQL_HOST} -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName} > /tmp/${dbName}.sql)
        end=$(date +%s)
        logger -p user.info "${dbName} backed up ($(stat -c %s /tmp/${dbName}.sql) bytes) in $(expr ${end} - ${start}) seconds."

        runny gzip -f /tmp/${dbName}.sql
        runny s3cmd put /tmp/${dbName}.sql.gz ${S3_BUCKET}
    elif [ ${MODE} = "restore" ]; then
        logger -p user.info "restoring ${dbName}..."

        runny s3cmd get -f ${S3_BUCKET}/${dbName}.sql.gz /tmp/${dbName}.sql.gz
        runny gunzip -f /tmp/${dbName}.sql.gz

        start=$(date +%s)
        runny $(mysql -u ${MYSQL_USER} -p"${MYSQL_PASSWORD}" ${dbName} < /tmp/${dbName}.sql)
        end=$(date +%s)
        logger -p user.info "${dbName} restored in $(expr ${end} - ${start}) seconds."
    else
        echo "unknown MODE(${MODE}), exiting."
        exit 1
    fi
done

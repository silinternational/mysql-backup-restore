#!/usr/bin/env sh

STATUS=0

case "${MODE}" in
    backup|restore)
        /data/${MODE}.sh || STATUS=$?
        ;;
    *)
        echo mysql-backup-restore: FATAL: Unknown MODE: ${MODE}
        exit 1
esac

if [ $STATUS -ne 0 ]; then
    echo mysql-backup-restore: Non-zero exit: $STATUS
fi

exit $STATUS

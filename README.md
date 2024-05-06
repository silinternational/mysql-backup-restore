# mysql-backup-restore
Service to backup and/or restore mysql databases to/from S3 and optionally to B2

## How to use it
1. Create an S3 bucket to hold your backups
2. Turn versioning on for that bucket
2. (Optional) Create a B2 bucket to hold your backups
3. Supply all appropriate environment variables
4. Run a backup and check your bucket(s) for that backup

### Environment variables
`MODE` Valid values: `backup`, `restore`. Restores are implemented **only** from S3.

`DB_NAMES` list of the database names

`MYSQL_USER` user that accesses the database

`MYSQL_PASSWORD` password for the `MYSQL_USER`

`MYSQL_DUMP_ARGS` (optional) additional arguments to the mysqldump command, e.g., `--max_allowed_packet=50M`

`S3_BUCKET` e.g., _s3://database-backups_ **NOTE: no trailing slash**

>**It's recommended that your S3 bucket have versioning turned on.** Each backup creates a file of the form _dbname_.sql.gz. If versioning is not turned on, the previous backup file will be replaced with the new one, resulting in a single level of backups.

`AWS_ACCESS_KEY` used for S3 interactions

`AWS_SECRET_KEY` used for S3 interactions

`B2_BUCKET` (optional) Name of the Backblaze B2 bucket, e.g., _database-backups_. When `B2_BUCKET` is defined, the backup file is copied to the B2 bucket in addition to the S3 bucket.

>**It's recommended that your B2 bucket have versioning and encryption turned on.** Each backup creates a file of the form _dbname_.sql.gz. If versioning is not turned on, the previous backup file will be replaced with the new one, resulting in a single level of backups. Encryption may offer an additional level of protection from attackers. It also has the side effect of preventing downloads of the file via the Backblaze GUI (you'll have to use the `b2` command or the Backblaze API).

`B2_APPLICATION_KEY_ID` (optional; required if `B2_BUCKET` is defined) Backblaze application key ID

`B2_APPLICATION_KEY` (optional; required if `B2_BUCKET` is defined) Backblaze application key secret

## Docker Hub
This image is built automatically on Docker Hub as [silintl/mysql-backup-restore](https://hub.docker.com/r/silintl/mysql-backup-restore/).

## Playing with it locally
You'll need [Docker Engine](https://docs.docker.com/engine/) with the Docker Compose plugin and [Make](https://www.gnu.org/software/make/).

1. cd .../mysql-backup-restore
3. Upload test/world.sql.gz to the S3 bucket.
4. `make db`  # creates the MySQL DB server
5. `make restore`  # restores the DB dump file
6. `docker ps -a`  # get the Container ID of the exited restore container
7. `docker logs <containerID>`  # review the restoration log messages
8. `make backup`  # create a new DB dump file
9. `docker ps -a`  # get the Container ID of the exited backup container
10. `docker logs <containerID>`  # review the backup log messages
11. `make restore`  # restore the DB dump file from the new backup
12. `docker ps -a`  # get the Container ID of the exited restore container
13. `docker logs <containerID>`  # review the restoration log messages
14. `make clean`  # remove containers and network
15. `docker volume ls`  # find the volume ID of the MySQL data container
16. `docker volume rm <volumeID>`  # remove the data volume
17. `docker images`  # list existing images
18. `docker image rm <imageID ...>`  # remove images no longer needed

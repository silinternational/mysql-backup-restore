# mysql-backup-restore
Service to backup and/or restore mysql databases to/from S3

## How to use it
1. Create an S3 bucket to hold your backups
2. Turn versioning on for that bucket
3. Supply all appropriate environment variables
4. Run a backup and check your bucket for that backup

### Environment variables
`MODE` Valid values: `backup`, `restore`

`DB_NAMES` list of the database names

`MYSQL_USER` user that accesses the database

`MYSQL_PASSWORD` password for the `MYSQL_USER`

`MYSQL_DUMP_ARGS` (optional) additional arguments to the mysqldump command, e.g., `--max_allowed_packet=50M`

`AWS_ACCESS_KEY` used for S3 interactions

`AWS_SECRET_KEY` used for S3 interactions

`S3_BUCKET` e.g., _s3://database-backups_ **NOTE: no trailing slash**

>**It's recommended that your S3 bucket have versioning turned on.**

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

# mysql-backup-restore
Service to backup and/or restore mysql databases using S3

## How to use it
1. Create an S3 bucket to hold your backups
2. Turn versioning on for that bucket
3. Supply all appropriate environment variables
4. Run a backup and check your bucket for that backup

### Environment variables
`LOGENTRIES_KEY`

`MODE=[backup|restore]`

`CRON_SCHEDULE="0 2 * * *"` _defaults to every day at 2:00 AM_ [syntax reference](https://en.wikipedia.org/wiki/Cron)

`DB_NAMES=[name1 name2 name3 ...]`

`MYSQL_USER=`

`MYSQL_PASSWORD=`

`AWS_ACCESS_KEY=` used for S3 interactions

`AWS_SECRET_KEY=` used for S3 interactions

`S3_BUCKET=` _e.g., s3://database-backups_ **NOTE: no trailing slash**

>**It's recommended that your S3 bucket have versioning turned on.**

## Docker Hub
This image is built automatically on Docker Hub as [silintl/mysql-backup-restore](https://hub.docker.com/r/silintl/mysql-backup-restore/)

## Playing with it locally
You'll need [Docker](https://www.docker.com/get-docker) and [Make](https://www.gnu.org/software/make/)

1. `cp local.env.dist local.env` and supply variables
2. Ensure you have a `gz` dump in your S3 bucket to be used for testing.  A test database is provided as part of this project in the `test` folder.
2. `make`

A UI into the local database will then be running at [http://localhost:8001](http://localhost:8001)
 

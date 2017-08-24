# mysql-backup-restore
Service to backup and/or restore mysql databases using S3

## How to use it
Create an S3 bucket to hold your backups
Turn versioning on for that bucket
Run a backup and check your bucket for that backup


**It's recommended that your S3 bucket have versioning turned on.**

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

## Playing with it locally
you'll need Docker and Make


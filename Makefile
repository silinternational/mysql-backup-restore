test: restore backup

restore: bucket
	docker compose run --rm app bash -c "s3cmd put /root/world* \$$S3_BUCKET"
	docker compose run --rm --env MODE=restore app

backup: bucket
	docker compose run --rm --env MODE=backup app

bucket:
	-docker compose run --rm app bash -c "s3cmd mb -f \$$S3_BUCKET"

clean:
	docker compose kill
	docker compose rm -f

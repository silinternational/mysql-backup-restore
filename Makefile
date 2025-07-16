test: restore backup

restore:
	docker compose run --rm app bash -c "s3cmd put /root/world* s3://world"
	docker compose run --rm --env MODE=restore app

backup:
	docker compose run --rm --env MODE=backup app

clean:
	docker compose kill
	docker compose rm -f

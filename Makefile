.PHONY: test run image

test:  ## run the tests
	.venv/bin/pytest -q

run:  ## serve the site on localhost:5000, reloads on save
	.venv/bin/flask --app app.main run --debug

image:  ## build the container image locally (Colima must be running)
	docker build --build-arg APP_VERSION=dev -t pipeline-demo:dev .

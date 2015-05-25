IMAGE_TAG=docker.jimubox.com/daikon

all: clean docker

main.js: main.coffee
	coffee -c main.coffee

node_modules: package.json
	npm install

docker: main.js node_modules Dockerfile
	docker build -t $(IMAGE_TAG) .

clean:
	-docker rmi $(IMAGE_TAG)
	rm main.js

.PHONY: docker clean

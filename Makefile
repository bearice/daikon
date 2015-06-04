IMAGE_TAG=docker.jimubox.com/daikon

all: docker
push: docker
	docker push $(IMAGE_TAG)

run: push
	maestro restart -r

%.js: %.coffee
	coffee -c main.coffee

node_modules: package.json
	npm install

docker: main.js dockerstats.js node_modules Dockerfile
	docker build -t $(IMAGE_TAG) .

clean:
	-docker rmi $(IMAGE_TAG)
	rm main.js

#run: all
#	docker run --hostname $(shell hostname) --name daikon --rm -v /var/run/docker.sock:/var/run/docker.sock -e ETCD_DNS_NAME=_etcd._tcp.zhaowei.jimubox.com docker.jimubox.com/daikon

.PHONY: docker push run clean

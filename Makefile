NPM=npm
NODE=node
COFFEE=node_modules/coffee-script/bin/coffee
PEGJS=node_modules/pegjs/bin/pegjs
MOCHA=node_modules/mocha/bin/mocha

TARGETS=$(patsubst src/%.coffee,lib/%.js,$(shell find src -name \*.coffee))

all: node_modules $(TARGETS)

lib/%.js: src/%.coffee
	@mkdir -p $(shell dirname $@)
	$(COFFEE) -c -m -o $(shell dirname $@) "$<"

node_modules: package.json
	$(NPM) install

clean:
	find lib -name \*.map -delete
	rm -rf $(TARGETS)

run: all
	node lib/main

watch:
	nodemon -w src

test: all
	$(MOCHA) --compilers coffee:coffee-script/register

docker: all
	docker build -t docker.jimubox.com/daikon .

push: docker
	docker push docker.jimubox.com/daikon

.PHONY: all clean run watch

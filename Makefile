
export DOCKER_BUILDKIT=1
GIT_TAG = $(shell git describe --exact-match --tags HEAD 2>/dev/null)
ifeq ($(strip $(GIT_TAG)),)
GIT_REF = $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
else
GIT_REF = $(GIT_TAG)
endif

PANDOC_VERSION ?= 2.10.1

all: build test README

build: asciidoctor-minimal.build build-haskell.build asciidoctor.build

%.build:
	docker buildx bake $(*) --load --set '*.cache-to=""' --print
	docker buildx bake $(*) --load --set '*.cache-to=""'

docker-cache: asciidoctor-minimal.docker-cache build-haskell.docker-cache asciidoctor.docker-cache

%.docker-cache:
	docker buildx bake $(*) --print
	docker buildx bake $(*)

test: asciidoctor.test

%.test:
	bats $(CURDIR)/tests/$(*).bats

deploy: asciidoctor.deploy

%.deploy:
	docker buildx bake $(*) --push --print
	docker buildx bake $(*) --push

clean:
	rm -rf "$(CURDIR)/cache"

cache:
	mkdir -p "$(CURDIR)/cache"

cache/pandoc-$(PANDOC_VERSION)-linux.tar.gz: cache
	curl -sSL -o "$(CURDIR)/cache/pandoc-$(PANDOC_VERSION)-linux.tar.gz" \
		https://github.com/jgm/pandoc/releases/download/$(PANDOC_VERSION)/pandoc-$(PANDOC_VERSION)-linux-amd64.tar.gz

cache/pandoc-$(PANDOC_VERSION)/bin/pandoc: cache/pandoc-$(PANDOC_VERSION)-linux.tar.gz
	tar xzf "$(CURDIR)/cache/pandoc-$(PANDOC_VERSION)-linux.tar.gz" -C "$(CURDIR)/cache"

# GitHub renders asciidoctor but DockerHub requires markdown.
# This recipe creates README.md and README.adoc from README-original.adoc and env_vars.yml.
README: asciidoctor.build cache/pandoc-$(PANDOC_VERSION)/bin/pandoc
	cat tests/env_vars.yml | sed -e 's/^[A-Z]/:&/' | sed '/^#/d' > "$(CURDIR)/cache/env_vars.adoc"
	cat "$(CURDIR)/cache/env_vars.adoc" README-original.adoc > README.adoc
	docker run --rm -t -v $(CURDIR):/documents --entrypoint bash asciidoctor \
		-c "asciidoctor -b docbook -a leveloffset=+1 -o - README.adoc | /documents/cache/pandoc-$(PANDOC_VERSION)/bin/pandoc  --atx-headers --wrap=preserve -t gfm -f docbook - > README.md"

deploy-README: README
	git add README.adoc README.md && git commit -s -m "Updating README files using 'make README command'" \
		&& git push origin $(shell git rev-parse --abbrev-ref HEAD) || echo 'No changes to README files'

.PHONY: all build test deploy clean README deploy-README docker-cache

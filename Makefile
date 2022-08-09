# Makefile for releasing podinfo
#
# The release version is controlled from pkg/version

TAG?=latest
NAME:=podinfo
DOCKER_REPOSITORY:=stefanprodan
DOCKER_IMAGE_NAME:=$(DOCKER_REPOSITORY)/$(NAME)
GHCR_IMAGE_REPO:=$(shell yq .image.repository charts/podinfo/values.yaml)
GIT_COMMIT:=$(shell git describe --dirty --always)
GIT_SOURCE:=$(shell git config --get remote.origin.url)
OCI_REVISION:=$(shell git branch --show-current)/$(shell git rev-parse HEAD)
VERSION:=$(shell grep 'VERSION' pkg/version/version.go | awk '{ print $$4 }' | tr -d '"')
EXTRA_RUN_ARGS?=

run:
	go run -ldflags "-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=$(GIT_COMMIT)" cmd/podinfo/* \
	--level=debug --grpc-port=9999 --backend-url=https://httpbin.org/status/401 --backend-url=https://httpbin.org/status/500 \
	--ui-logo=https://raw.githubusercontent.com/stefanprodan/podinfo/gh-pages/cuddle_clap.gif $(EXTRA_RUN_ARGS)

.PHONY: test
test:
	go test ./... -coverprofile cover.out

build:
	GIT_COMMIT=$$(git rev-list -1 HEAD) && CGO_ENABLED=0 go build  -ldflags "-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=$(GIT_COMMIT)" -a -o ./bin/podinfo ./cmd/podinfo/*
	GIT_COMMIT=$$(git rev-list -1 HEAD) && CGO_ENABLED=0 go build  -ldflags "-s -w -X github.com/stefanprodan/podinfo/pkg/version.REVISION=$(GIT_COMMIT)" -a -o ./bin/podcli ./cmd/podcli/*

tidy:
	rm -f go.sum; go mod tidy -compat=1.17

fmt:
	gofmt -l -s -w ./
	goimports -l -w ./

build-charts:
	helm lint charts/*
	helm package charts/*

build-container:
	docker build -t $(DOCKER_IMAGE_NAME):$(VERSION) .

build-xx:
	docker buildx build \
	--platform=linux/amd64 \
	-t $(DOCKER_IMAGE_NAME):$(VERSION) \
	--load \
	-f Dockerfile.xx .

build-base:
	docker build -f Dockerfile.base -t $(DOCKER_REPOSITORY)/podinfo-base:latest .

push-base: build-base
	docker push $(DOCKER_REPOSITORY)/podinfo-base:latest

test-container:
	@docker rm -f podinfo || true
	@docker run -dp 9898:9898 --name=podinfo $(DOCKER_IMAGE_NAME):$(VERSION)
	@docker ps
	@TOKEN=$$(curl -sd 'test' localhost:9898/token | jq -r .token) && \
	curl -sH "Authorization: Bearer $${TOKEN}" localhost:9898/token/validate | grep test

push-container:
	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) $(DOCKER_IMAGE_NAME):latest
	docker push $(DOCKER_IMAGE_NAME):$(VERSION)
	docker push $(DOCKER_IMAGE_NAME):latest
	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) quay.io/$(DOCKER_IMAGE_NAME):$(VERSION)
	docker tag $(DOCKER_IMAGE_NAME):$(VERSION) quay.io/$(DOCKER_IMAGE_NAME):latest
	docker push quay.io/$(DOCKER_IMAGE_NAME):$(VERSION)
	docker push quay.io/$(DOCKER_IMAGE_NAME):latest

version-set:
	@next="$(TAG)" && \
	current="$(VERSION)" && \
	/usr/bin/sed -i '' "s/$$current/$$next/g" pkg/version/version.go && \
	/usr/bin/sed -i '' "s/tag: $$current/tag: $$next/g" charts/podinfo/values.yaml && \
	/usr/bin/sed -i '' "s/tag: $$current/tag: $$next/g" charts/podinfo/values-prod.yaml && \
	/usr/bin/sed -i '' "s/appVersion: $$current/appVersion: $$next/g" charts/podinfo/Chart.yaml && \
	/usr/bin/sed -i '' "s/version: $$current/version: $$next/g" charts/podinfo/Chart.yaml && \
	/usr/bin/sed -i '' "s/podinfo:$$current/podinfo:$$next/g" kustomize/deployment.yaml && \
	/usr/bin/sed -i '' "s/podinfo:$$current/podinfo:$$next/g" deploy/webapp/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s/podinfo:$$current/podinfo:$$next/g" deploy/webapp/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s/podinfo:$$current/podinfo:$$next/g" deploy/bases/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s/podinfo:$$current/podinfo:$$next/g" deploy/bases/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s/$$current/$$next/g" cue/main.cue && \
	echo "Version $$next set in code, deployment, chart and kustomize"

image-set:
	@next="$(REPO)" && \
	current="$(GHCR_IMAGE_REPO)" && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" charts/podinfo/values.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" charts/podinfo/values-prod.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" cue/podinfo/config.cue && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" deploy/webapp/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" deploy/webapp/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" deploy/bases/frontend/deployment.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" deploy/bases/backend/deployment.yaml && \
	/usr/bin/sed -i '' "s|$$current|$$next|g" kustomize/deployment.yaml && \
	echo "Image repo $$next set in deployment, chart and kustomize"

release-app:
	git tag $(VERSION)
	git push origin $(VERSION)

# release-oci:
# 	git tag release/$(VERSION)
# 	git push origin release/$(VERSION)

# Careful
push-tag: version-set release-app
	# echo "Now go check on the build, and when it's finished run: make release-oci"

push-config:
	flux push artifact $(GHCR_IMAGE_REPO)/deploy:$(VERSION) \
	  --path="./deploy" \
	  --source="$(GIT_SOURCE)" \
	  --revision="$(OCI_REVISION)"

push-chart: build-charts
	# helm lint charts/*
	# helm package charts/*
	helm push podinfo-$(VERSION).tgz oci://$(GHCR_IMAGE_REPO)/helm

swagger:
	go install github.com/swaggo/swag/cmd/swag@latest
	go get github.com/swaggo/swag/gen@latest
	go get github.com/swaggo/swag/cmd/swag@latest
	cd pkg/api && $$(go env GOPATH)/bin/swag init -g server.go

.PHONY: cue-mod
cue-mod:
	@cd cue && cue get go k8s.io/api/...

.PHONY: cue-gen
cue-gen:
	@cd cue && cue fmt ./... && cue vet --all-errors --concrete ./...
	@cd cue && cue gen
SHELL:=/bin/sh
export GOSUMDB=off
export GO111MODULE=on

$(value $(shell [ ! -d "$(CURDIR)/bin" ] && mkdir -p "$(CURDIR)/bin"))
export GOBIN=$(CURDIR)/bin
GOLANGCI_BIN?=$(GOBIN)/golangci-lint
GOLANGCI_REPO?=https://github.com/golangci/golangci-lint
GOLANGCI_LATEST_VERSION?= $(shell git ls-remote --tags --refs --sort='v:refname' $(GOLANGCI_REPO)|tail -1|egrep -o "v[0-9]+.*")
GO?=$(shell which go)

ifneq ($(wildcard $(GOLANGCI_BIN)),)
	GOLANGCI_CUR_VERSION:=v$(shell $(GOLANGCI_BIN) --version|sed -E 's/.* version (.*) built from .* on .*/\1/g')
else
	GOLANGCI_CUR_VERSION:=
endif

# install linter tool
.PHONY: .install-linter
.install-linter:
ifeq ($(filter $(GOLANGCI_CUR_VERSION), $(GOLANGCI_LATEST_VERSION)),)
	$(info Installing GOLANGCI-LINT $(GOLANGCI_LATEST_VERSION)...)
	@curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s $(GOLANGCI_LATEST_VERSION)
	@chmod +x $(GOLANGCI_BIN)
else
	@echo 1 >/dev/null
endif


# run full lint like in pipeline
.PHONY: lint
lint: | go-deps .install-linter
	@echo Full lint... && \
	$(GOLANGCI_BIN) cache clean && \
	$(GOLANGCI_BIN) run --config=$(CURDIR)/.golangci.yaml -v $(CURDIR)/... && \
	echo -=OK=-

# install project dependencies
.PHONY: go-deps
go-deps:
	@echo Check go modules dependencies... && \
	$(GO) mod tidy && go mod vendor && go mod verify && \
	echo -=OK=-


#connectrpc.com/connect
#go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest

.PHONY: .grpc-plugins
.grpc-plugins:
	@echo - ensure GRPC plugins are installed
ifeq ($(wildcard $(GOBIN)/protoc-gen-grpc-gateway),)
	@echo install \"protoc-gen-grpc-gateway\" && \
	$(GO) install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway
endif
ifeq ($(wildcard $(GOBIN)/protoc-gen-openapiv2),)
	@echo install \"protoc-gen-openapiv2\" && \
	$(GO) install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2
endif
ifeq ($(wildcard $(GOBIN)/protoc-gen-go),)
	@echo install \"protoc-gen-go\" && \
	$(GO) install google.golang.org/protobuf/cmd/protoc-gen-go
endif
ifeq ($(wildcard $(GOBIN)/protoc-gen-go-grpc),)
	@echo install \"protoc-gen-go-grpc\" && \
	$(GO) install google.golang.org/grpc/cmd/protoc-gen-go-grpc
endif
ifeq ($(wildcard $(GOBIN)/protoc-gen-connect-go),)
	@echo install \"protoc-gen-connect-go\" && \
	$(GO) install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest
endif

proto_dirs := sgroups common
.PHONY: generate-api
generate-api: | .grpc-plugins
	@(\
	apis=$(CURDIR)/api && \
	dest=$(CURDIR)/pkg/api && \
	PATH=$(PATH):$(GOBIN):/usr/include:/usr/local/include && \
	rm -rf $$dest 2>/dev/null && \
	mkdir -p $$dest && \
	echo generating API in \"$$dest\" ... && \
	for p in $(proto_dirs); do \
		for v in $$apis/$$p/*.proto; do \
			echo  "  - " \"$$p/$$(basename $$v)\" ;\
			protoc \
				-I $(CURDIR)/vendor/github.com/grpc-ecosystem/grpc-gateway/v2/ \
				-I $(CURDIR)/3d-party \
				--go_opt=paths=source_relative \
				--go-grpc_opt=paths=source_relative \
				--go_out $$dest \
				--go-grpc_out $$dest \
				--proto_path=$$apis \
				--grpc-gateway_out $$dest \
				--grpc-gateway_opt paths=source_relative \
				--grpc-gateway_opt logtostderr=true \
				--grpc-gateway_opt standalone=false \
				--openapiv2_out $$dest \
				--openapiv2_opt logtostderr=true \
				--connect-go_out=$$dest \
				--connect-go_opt=paths=source_relative \
				"$$v" ||\
			exit 1;\
		done; \
	done; \
	echo -=OK=- ;\
	)


.PHONY: test
test:
	@echo Running tests... && \
	$(GO) clean -testcache && go test -v ./...



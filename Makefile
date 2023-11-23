VERSION=$(shell cat VERSION)
KUST_VERSION_FILE="./csdp/base_components/bootstrap/kustomization.yaml"
RUNTIME_YAML_FILE="./csdp/hybrid/basic/runtime.yaml"
YQ_BINARY := /usr/local/bin/yq

BUMP_CHECK_MSG="Error: git working tree is not clean, make sure that you ran 'make bump' locally and commit the changes!"

.PHONY: bump
bump: $(YQ_BINARY)
	@echo "bumping version ${VERSION}"

	@echo "--> updating file: ${KUST_VERSION_FILE}"
	@yq -i '.configMapGenerator.0.literals.0 = "version=${VERSION}"' ${KUST_VERSION_FILE}
	@yq -i '.configMapGenerator.0.literals.1 = "bootstrapRevision=${VERSION}"' ${KUST_VERSION_FILE}

	@echo "--> updating file: ${RUNTIME_YAML_FILE}"
	@yq -i '.spec.version = "${VERSION}"' ${RUNTIME_YAML_FILE}
	@echo "done!"

.PHONY: check-bump
check-bump: bump
	@echo "checking bump..."
	@git status --short && git diff --quiet || (echo "\n${BUMP_CHECK_MSG}" && exit 1)


$(YQ_BINARY):
	@echo "Checking if yq is installed..."
	@if command -v yq > /dev/null ; then \
		echo "yq is already installed"; \
	else \
		@echo "Downloading yq..." \
		@curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_$(shell go env GOOS)_$(shell go env GOARCH) -o $(YQ_BINARY) &&\
		chmod +x $(YQ_BINARY); \
		@yq --version; \
	fi

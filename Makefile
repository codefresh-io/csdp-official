VERSION=$(shell cat VERSION)
KUST_VERSION_FILE="./csdp/base_components/bootstrap/kustomization.yaml"
RUNTIME_YAML_FILE="./csdp/hybrid/basic/runtime.yaml"

BUMP_CHECK_MSG="Error: git working tree is not clean, make sure that you ran 'make bump' locally and commit the changes!"

.PHONY: bump
bump: /usr/local/bin/yq
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


/usr/local/bin/yq:
	@echo "Downloading yq..."
	@curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_$(shell go env GOOS)_$(shell go env GOARCH) -o /usr/local/bin/yq &&\
		chmod +x /usr/local/bin/yq
	@yq --version

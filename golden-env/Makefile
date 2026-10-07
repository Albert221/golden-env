# Defaults to the newest line of `versions`; override both for another release:
#   make image FLUTTER_VERSION=3.47.5 FLUTTER_COMMIT=<sha>
FLUTTER_VERSION ?= $(shell awk '!/^\#/ && NF { v = $$1 } END { print v }' versions)
FLUTTER_COMMIT ?= $(shell awk -v v=$(FLUTTER_VERSION) '$$1 == v { print $$2 }' versions)
IMAGE ?= ghcr.io/albert221/golden-env:$(FLUTTER_VERSION)
OCI_DIR ?= ../.build/golden-env-$(FLUTTER_VERSION).oci

BUILD = docker buildx build --platform linux/amd64 --provenance=false \
	--build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	--build-arg FLUTTER_COMMIT=$(FLUTTER_COMMIT)

.PHONY: image oci

# Into the local Docker engine, for `docker run`.
image:
	@test -n "$(FLUTTER_COMMIT)" || { echo "no commit for $(FLUTTER_VERSION) in versions"; exit 1; }
	$(BUILD) -t $(IMAGE) --load .

# As an OCI layout directory, for `golden-run load`. Reuses the build cache.
oci:
	@test -n "$(FLUTTER_COMMIT)" || { echo "no commit for $(FLUTTER_VERSION) in versions"; exit 1; }
	rm -rf $(OCI_DIR)
	$(BUILD) --output type=oci,tar=false,name=$(IMAGE),dest=$(OCI_DIR) .
	@echo $(OCI_DIR)

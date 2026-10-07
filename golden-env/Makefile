FLUTTER_VERSION ?= 3.47.6
FLUTTER_COMMIT ?= 5fc346839b5d0eef006ed8404392afb4dfae428d
IMAGE ?= golden-env:$(FLUTTER_VERSION)
OCI_DIR ?= ../.build/golden-env-$(FLUTTER_VERSION).oci

.PHONY: image oci

# Into the local Docker engine, for `docker run` comparisons.
image:
	docker buildx build --platform linux/amd64 --provenance=false \
	  --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  --build-arg FLUTTER_COMMIT=$(FLUTTER_COMMIT) \
	  -t $(IMAGE) --load .

# As an OCI layout directory, for `golden-run load`. Reuses the build cache.
oci:
	rm -rf $(OCI_DIR)
	docker buildx build --platform linux/amd64 --provenance=false \
	  --build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
	  --build-arg FLUTTER_COMMIT=$(FLUTTER_COMMIT) \
	  --output type=oci,tar=false,name=$(IMAGE),dest=$(OCI_DIR) .
	@echo $(OCI_DIR)

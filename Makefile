CONFIG ?= debug
BIN := $(shell swift build -c $(CONFIG) --show-bin-path)/golden-run

.PHONY: build release clean

# Virtualization.framework refuses to start a VM from a binary without the
# virtualization entitlement, so every build is followed by an ad-hoc sign.
build:
	swift build -c $(CONFIG)
	codesign --force --sign - --timestamp=none --entitlements=golden-run.entitlements $(BIN)
	@echo $(BIN)

release:
	$(MAKE) build CONFIG=release

clean:
	swift package clean

.PHONY: ensure-tools format format-check lint release publish-release

TOOLS ?= swift-format swiftlint

ensure-tools:
	@for tool in $(TOOLS); do \
		command -v $$tool >/dev/null 2>&1 || { echo "$$tool not installed"; exit 1; }; \
	done

format: TOOLS=swift-format
format: ensure-tools
	swift-format format -ir Sources

format-check: TOOLS=swift-format
format-check: ensure-tools
	swift-format lint -r Sources

lint: TOOLS=swiftlint
lint: ensure-tools
	swiftlint lint --strict --cache-path .build/swiftlint-cache

release:
	RELEASE_NOTARIZE="$(RELEASE_NOTARIZE)" \
	RELEASE_NOTARIZE_DMG="$(RELEASE_NOTARIZE_DMG)" \
	RELEASE_NOTARIZE_ZIP="$(RELEASE_NOTARIZE_ZIP)" \
	./scripts/release-build.sh

publish-release: RELEASE_NOTARIZE=1
publish-release: RELEASE_NOTARIZE_DMG=1
publish-release: RELEASE_NOTARIZE_ZIP=1
publish-release: release
	RELEASE_BUILD_ARTIFACTS=0 ./scripts/publish-github-release.sh

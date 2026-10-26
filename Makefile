# Aozora Ebooks — common tasks
.PHONY: app run cli test dist icon clean

app: ## Build the macOS app (needs xcodegen)
	cd App && xcodegen generate --quiet && xcodebuild -project AozoraEbooks.xcodeproj -scheme AozoraEbooks -configuration Release -derivedDataPath ../.build/xcode build | grep -E "error:|BUILD"
	@echo "→ .build/xcode/Build/Products/Release/Aozora Ebooks.app"

run: app
	open ".build/xcode/Build/Products/Release/Aozora Ebooks.app"

cli: ## Build the `aozora` command-line converter
	swift build -c release
	@echo "→ .build/release/aozora"

test: ## Unit and golden tests
	swift test

VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' App/project.yml)
DIST := .build/dist

dist: test ## Release zips (universal app + CLI) in .build/dist
	rm -rf $(DIST) && mkdir -p $(DIST)/cli
	cd App && xcodegen generate --quiet && xcodebuild -project AozoraEbooks.xcodeproj -scheme AozoraEbooks -configuration Release \
		-derivedDataPath ../.build/xcode ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | grep -E "error:|BUILD"
	ditto -c -k --keepParent ".build/xcode/Build/Products/Release/Aozora Ebooks.app" "$(DIST)/Aozora-Ebooks-$(VERSION).zip"
	swift build -c release --arch arm64 --arch x86_64
	BIN=$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path) && cp -R "$$BIN/aozora" "$$BIN/AozoraEbooks_AozoraKit.bundle" $(DIST)/cli/
	cd $(DIST) && ditto -c -k --norsrc cli "aozora-cli-$(VERSION).zip" && rm -r cli && shasum -a 256 *.zip | tee SHA256SUMS
	@echo "→ $(DIST)"

icon: ## Redraw the app icon
	swift scripts/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

clean:
	rm -rf .build App/AozoraEbooks.xcodeproj

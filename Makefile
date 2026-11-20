APP := MiniBrowser.app
VERSION := $(shell Scripts/version.sh 2>/dev/null)
DMG := MiniBrowser-$(VERSION).dmg

.PHONY: check lint build test perf run package clean

## check: 静态检查 + 单元测试 + 构建（CI 使用同一入口）
check: lint test build

lint:
	plutil -lint Resources/Info.plist
	bash -n Scripts/build-app.sh
	bash -n Scripts/version.sh
	bash -n Scripts/release-notes.sh
	bash -n Scripts/test.sh
	Scripts/release-notes.sh 1.0.1 | grep -q '签名'

build:
	swift build

test:
	Scripts/test.sh

## perf: 独立运行标签切换性能测试，严格执行本地 16ms 预算
perf:
	env CI=false GITHUB_ACTIONS=false Scripts/test.sh --filter TabSwitchPerformanceTests

## run: 打包 DEV X 签名的 release app，做 5 秒启动冒烟后只关闭该进程
run:
	MINIBROWSER_BUNDLE_ID=com.zhao.minibrowser.dev Scripts/build-app.sh
	@set -eu; \
	suite="MiniBrowser.Local.$$"; data="$(CURDIR)/.local/run-data"; pid=""; \
	cleanup() { \
		if [ -n "$$pid" ]; then kill "$$pid" 2>/dev/null || true; wait "$$pid" 2>/dev/null || true; fi; \
		defaults delete "$$suite" >/dev/null 2>&1 || true; \
		rm -f "$$HOME/Library/Preferences/$$suite.plist"; \
		rm -rf "$$data"; \
	}; \
	trap cleanup EXIT INT TERM; \
	MINIBROWSER_DEFAULTS_SUITE="$$suite" MINIBROWSER_DATA_DIRECTORY="$$data" \
	MINIBROWSER_NONPERSISTENT=1 \
		"$(APP)/Contents/MacOS/MiniBrowser" & pid=$$!; \
	sleep 5; \
	kill -0 $$pid; \
	echo "MiniBrowser launch smoke test passed (5s)"

## package: 复用发布流程的 .app 构建和 DMG 命令
package:
	Scripts/version.sh >/dev/null
	Scripts/build-app.sh
	rm -rf dmg
	mkdir dmg
	cp -R "$(APP)" dmg/
	ln -s /Applications dmg/Applications
	hdiutil create -volname MiniBrowser -srcfolder dmg -ov -format UDZO "$(DMG)"

clean:
	swift package clean
	rm -rf "$(APP)" dmg MiniBrowser-*.dmg release-notes.md

.DEFAULT_GOAL := help

.PHONY: help setup \
	run-macos run-linux run-windows \
	test test-e2e analyze format format-check \
	build-macos build-linux build-windows \
	check check-docs clean

help:
	@echo "可用命令："
	@echo "  make setup          - 检查 Flutter 并安装依赖"
	@echo "  make run-macos      - 在 macOS 上运行应用"
	@echo "  make run-linux      - 在 Linux 上运行应用"
	@echo "  make run-windows    - 在 Windows 上运行应用"
	@echo "  make test           - 运行单元/组件测试"
	@echo "  make test-e2e       - 运行聊天滚动 e2e 测试（macOS）"
	@echo "  make analyze        - 运行静态分析"
	@echo "  make format         - 格式化 Dart 代码"
	@echo "  make format-check   - 检查格式（不修改文件）"
	@echo "  make build-macos    - 构建 macOS debug 包"
	@echo "  make build-linux    - 构建 Linux debug 包"
	@echo "  make build-windows  - 构建 Windows debug 包"
	@echo "  make check          - 提交前验证（test + analyze + build-macos）"
	@echo "  make check-docs     - 仅文档改动时的检查（git diff --check）"
	@echo "  make clean          - 清理构建产物"

setup:
	flutter --version
	flutter pub get

run-macos:
	flutter run -d macos

run-linux:
	flutter run -d linux

run-windows:
	flutter run -d windows

test:
	flutter test

test-e2e:
	flutter test integration_test/chat_scroll_position_e2e_test.dart -d macos

analyze:
	flutter analyze

format:
	dart format .

format-check:
	dart format --set-exit-if-changed .

build-macos:
	flutter build macos --debug

build-linux:
	flutter build linux --debug

build-windows:
	flutter build windows --debug

check: test analyze build-macos

check-docs:
	git diff --check

clean:
	flutter clean

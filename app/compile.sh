#!/bin/bash
set -e

# Пути к папкам проекта
PROJECT_DIR="/Users/daniilchugunnikov/Desktop/work/gemini_limits_widget_v2"
APP_DIR="$PROJECT_DIR/app"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/GeminiLimits.app"

echo "=== Сборка GeminiLimits.app ==="

# Очистка старых билдов
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Компиляция Swift кода
echo "Компиляция Swift кода..."
swiftc -O -o "$APP_BUNDLE/Contents/MacOS/GeminiLimits" "$APP_DIR/main.swift"

# Копирование Info.plist
echo "Копирование Info.plist..."
cp "$APP_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Права доступа
chmod +x "$APP_BUNDLE/Contents/MacOS/GeminiLimits"

echo "=== Сборка завершена успешно ==="
echo "Приложение создано по пути: $APP_BUNDLE"

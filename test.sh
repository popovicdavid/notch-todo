#!/bin/zsh
# Kjører testene for lesing og skriving av todo-fila (Sources/Model/TodoFile.swift).
set -e
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 Sources/Model/TodoFile.swift Tests/main.swift -o build/tests
./build/tests

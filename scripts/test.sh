#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_build="$PWD/.build/standalone-tests"
mkdir -p "$test_build"
clang -std=c11 -Wall -Wextra -Werror -O2 -I Sources/AudioDSP/include \
    -c Sources/AudioDSP/AudioDSP.c -o "$test_build/AudioDSP.o"
printf 'module AudioDSP { header "%s/Sources/AudioDSP/include/AudioDSP.h" export * }\n' "$PWD" > "$test_build/module.modulemap"
swiftc -warnings-as-errors -I "$test_build" \
    Sources/EvenTone/Preferences.swift Sources/EvenTone/OutputSelection.swift \
    Sources/EvenTone/CalibrationSession.swift Sources/EvenTone/ReferenceSignal.swift \
    Sources/EvenTone/LoginItemController.swift Tests/EvenToneTests/*.swift \
    "$test_build/AudioDSP.o" -framework CoreAudio -framework ServiceManagement -o "$test_build/EvenToneTests"
"$test_build/EvenToneTests"

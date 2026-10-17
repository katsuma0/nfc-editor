#!/bin/bash
# Type-checks the NDEF and NFC layers and runs the logic tests with a plain Swift toolchain.
# Works on Linux or macOS without Xcode: it compiles a small CoreNFC stub so the NFC layer
# can be type-checked outside an iOS SDK. The SwiftUI layer is only syntax-parsed.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=.build/logic-tests
mkdir -p "$BUILD"
swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -module-name CoreNFC \
  -emit-module-path "$BUILD/CoreNFC.swiftmodule" -o "$BUILD/libCoreNFC.so" Tests/CoreNFCStub/CoreNFC.swift 2>/dev/null \
  || swiftc -swift-version 5 -parse-as-library -emit-module -emit-library -module-name CoreNFC \
  -emit-module-path "$BUILD/CoreNFC.swiftmodule" -o "$BUILD/libCoreNFC.dylib" Tests/CoreNFCStub/CoreNFC.swift
echo "type-checking NDEF and NFC"
swiftc -swift-version 5 -typecheck -I "$BUILD" NFCEditor/NDEF/*.swift NFCEditor/NFC/*.swift
echo "syntax-parsing every file"
find NFCEditor -name '*.swift' -print0 | xargs -0 -n1 swiftc -parse
echo "building logic tests"
swiftc -swift-version 5 -I "$BUILD" -L "$BUILD" -lCoreNFC -o "$BUILD/logic-tests" \
  NFCEditor/NDEF/*.swift NFCEditor/NFC/*.swift Tests/LogicTests/*.swift
LD_LIBRARY_PATH="$BUILD:${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="$BUILD:${DYLD_LIBRARY_PATH:-}" "$BUILD/logic-tests"

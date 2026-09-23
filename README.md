# KINW (KINW Is Not WINE) 📦🍷

> **KINW Is Not WINE** — A lightweight, modular "Bottles"-like runner and sandbox environment for iOS that brings Android APKs (2D indie games and visual novels) to iPhone & iPad without jailbreak and without JIT.

[![Build KINW IPA](https://github.com/your-username/KINW/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/your-username/KINW/actions/workflows/build-ipa.yml)
[![iOS 16+](https://img.shields.io/badge/iOS-16.0%2B-blue.svg)](https://apple.com)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![No JIT Required](https://img.shields.io/badge/JIT-Not%20Required-success.svg)](#)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ Features

* **📦 Sandboxed "Bottles" Architecture:** Every imported APK lives in its own isolated prefix (`Documents/Bottles/<id>/`). Save games, config files, and assets are completely separated.
* **🔍 Auto-Detection Engine:** Drops an `.apk` $\to$ KINW automatically parses `AndroidManifest.xml` via native C++ `AXMLDecoder`, extracts the game icon and title, and detects the engine signature.
* **🎮 Optimized for 2D Indie Games & Visual Novels:**
  * **HTML5 / Web Novels / Tyranobuilder:** Fullscreen hardware-accelerated WebKit/Metal runner with custom `kinw-app://` VFS and `localStorage` save syncing.
  * **RPG Maker MV / MZ:** Direct asset mounting and touch input support.
  * **Ren'Py Visual Novels:** Python/SDL2 archive and script integration pipeline.
  * **Godot Engine:** Direct `.pck` archive mounting.
  * **GameMaker Studio:** Native byte-data (`game.droid`) runner bridge.
* **🚀 Zero JIT / No Jailbreak:** Completely compliant with standard iOS sandboxing. Works via **AltStore**, **SideStore**, **TrollStore**, and **Scarlet**.
* **☁️ Cloud CI/CD:** Fully automated builds via GitHub Actions on Apple Silicon macOS runners. No Mac required on your local machine!

---

## 🏗️ Architecture

```
                  [ APK File (Drop / "Open with KINW") ]
                                    │
                                    ▼
+-----------------------------------------------------------------------+
|                       KINW iOS (SwiftUI 5)                            |
|   • Glassmorphic Game Shelf (Cover cards, Engine tags, Search)        |
|   • Bottle Manager (Settings, Orientation locks, Save Exporter)       |
+-----------------------------------------------------------------------+
                                    │
                                    ▼
+-----------------------------------------------------------------------+
|                    KINW CORE ENGINE (C++ / Swift)                     |
|   1. ZipExtractor (C/zlib): Fast memory decompression                 |
|   2. AXMLDecoder (C++): Binary AndroidManifest.xml parser             |
|   3. EngineDetector (Swift): Signature pattern matcher                |
|   4. BottleManager (Swift): Sandbox directory isolation               |
+-----------------------------------------------------------------------+
                                    │
                                    ▼
+-----------------------------------------------------------------------+
|                   MODULAR RUNNERS (Engine Runners)                    |
|   ┌──────────────────┐  ┌──────────────────┐  ┌────────────────────┐  |
|   │ WebNovelRunner   │  │ RenPyRunner      │  │ Godot / GameMaker  │  |
|   │ (WebKit / Metal) │  │ (.rpa / .rpyc)   │  │ (.pck / game.droid)│  |
|   └──────────────────┘  └──────────────────┘  └────────────────────┘  |
+-----------------------------------------------------------------------+
```

---

## 🎯 Supported Game Engines

| Engine | APK File Signatures | Status |
| :--- | :--- | :--- |
| **HTML5 / Web Novels** | `assets/www/index.html`, `assets/index.html` | ✅ **Active (Metal)** |
| **Tyranobuilder** | `assets/www/data/scenario/` | ✅ **Active** |
| **RPG Maker MV / MZ** | `assets/www/data/System.json` | ✅ **Active** |
| **Ren'Py Visual Novels** | `assets/x-game/`, `*.rpa`, `*.rpyc` | 🚧 **In Development** |
| **Godot Engine** | `assets/project.pck`, `*.pck` | 🚧 **In Development** |
| **GameMaker Studio** | `assets/game.droid`, `assets/data.win` | 🚧 **In Development** |
| **LÖVE2D** | `assets/game.love` | 📋 **Planned** |
| **Unity 2D (C++)** | `lib/arm64-v8a/libunity.so` | 📋 **Planned (FalsoJNI)** |

---

## 📲 How to Install & Play

### 1. Download `.ipa` from GitHub Actions
1. Fork or push this repository to GitHub.
2. Go to the **Actions** tab $\to$ click the latest **Build KINW IPA** run.
3. Under **Artifacts**, download `KINW-iOS-Build.zip` and extract `KINW.ipa`.

### 2. Sideload to iPhone / iPad
* **TrollStore (iOS 14.0 – 17.0):** Open `KINW.ipa` in TrollStore for permanent signing.
* **SideStore / AltStore:** Sideload wirelessly using your free Apple ID.
* **Scarlet:** Direct install.

### 3. Import & Launch
1. Open KINW on your iPhone.
2. Tap **"Import APK"** or choose **"Open in KINW"** from the iOS Files app or Safari.
3. KINW unpacks the game into its own bottle and configures the runner.
4. Tap **Play**!

---

## 🛠️ Local Development & Testing

The core C++ components (`AXMLDecoder` and `ZipExtractor`) can be compiled and tested on any Linux/macOS machine:

```bash
# Compile and run unit tests for AXMLDecoder:
g++ -std=c++17 -Wall -Wextra Tests/test_axml.cpp Sources/Core/AXMLDecoder.cpp -o test_axml
./test_axml [path/to/AndroidManifest.xml]
```

To generate the Xcode project locally (on macOS):
```bash
brew install xcodegen
xcodegen generate
open KINW.xcodeproj
```

---

## 📜 License
MIT License. Created with ❤️ for mobile gaming preservation and indie visual novels.

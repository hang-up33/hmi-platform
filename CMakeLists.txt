cmake_minimum_required(VERSION 3.21)
project(hmi_platform LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

include(CTest)

# Qt6::Test / Qt6::QuickTest は BUILD_TESTING=ON のときだけ要求する。
# Yocto 等 Qt Test / QuickTest が同梱されていないクロス環境で
# BUILD_TESTING=OFF にしたとき configure が落ちないようにするため。
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test QuickTest)
endif()

# --- Task 16: Phase 3-A E2E フレームワーク Spix を FetchContent で取り込む ---
#
# Spix は XML-RPC で外部からテストコマンドを受け付ける Qt 用 E2E ライブラリ。
# Editor / Simulator は `--e2e` CLI フラグ付き起動時のみ Spix エンドポイントを
# listen させる構成のため、通常起動への影響はリンク済みシンボルの追加だけ。
#
# **Windows MinGW では既定 OFF**：Spix の依存 AnyRPC は MinGW 検出時に
# `include/anyrpc/internal/mingw.mutex.h` / `mingw.condition_variable.h` を強制
# include し、`namespace std` に `recursive_mutex` / `timed_mutex` /
# `condition_variable` を再定義する。これは pthread 非対応の古い MinGW 向けの
# シムだが、modern MinGW（mingw1310_64 / POSIX threads モデル）の libstdc++
# は既に同じ型を提供するため、`error: redefinition of 'class std::...'` で
# 落ちる。AnyRPC upstream は 2022 年以降未メンテで修正されない見込みのため、
# Windows MinGW では E2E を opt-out 可能にする。
#
# Spix は AnyRPC (XML-RPC) ライブラリを `find_package(AnyRPC REQUIRED)` で要求
# する。AnyRPC は Homebrew / apt の公式パッケージが存在しないため、こちらも
# FetchContent で取り込み、Spix が期待する `AnyRPC::anyrpc` ターゲットを
# ALIAS で供給する。
#
# 既知の罠：
# - AnyRPC は `cmake_minimum_required(VERSION 2.8)` のため CMake 3.27+ で
#   `CMAKE_POLICY_VERSION_MINIMUM 3.5` を設定しないと configure が落ちる。
# - AnyRPC はトップレベルで `include_directories(${CMAKE_SOURCE_DIR}/include)`
#   を呼ぶ。FetchContent 経由だと `CMAKE_SOURCE_DIR` がトップ（hmi-platform）に
#   解決され誤動作するため、anyrpc ターゲットに `target_include_directories`
#   で正しい include path を明示しなおす。
# - Spix の FindAnyRPC.cmake は外部インストール済みヘッダ / ライブラリを
#   `find_path` / `find_library` で探す。CACHE 変数を埋めて
#   `find_package_handle_standard_args` を通し、ALIAS で imported target を供給する。
if(MINGW)
    # Windows MinGW では AnyRPC の libstdc++ 衝突により Spix をビルドできない。
    # ユーザーが明示的に -DHMI_ENABLE_E2E=ON を指定しない限り E2E は無効化する。
    option(HMI_ENABLE_E2E "Build with Spix (E2E test framework)" OFF)
else()
    option(HMI_ENABLE_E2E "Build with Spix (E2E test framework)" ON)
endif()

if(HMI_ENABLE_E2E)
    include(FetchContent)

    # AnyRPC（および古い CMake project の sub-build）が 2.x policy を要求するため、
    # CMake 3.27+ で導入された CMAKE_POLICY_VERSION_MINIMUM でポリシー下限を下げる。
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

    # AnyRPC：STATIC + log4cplus / examples 無効でビルド。
    set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(BUILD_WITH_LOG4CPLUS OFF CACHE BOOL "" FORCE)
    set(ANYRPC_LIB_BUILD_SHARED OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(
        anyrpc
        GIT_REPOSITORY https://github.com/sgieseking/anyrpc.git
        GIT_TAG b1949b3d40849229055ae75cf5334b9d08579502 # master @ 2022-08-29
    )
    FetchContent_MakeAvailable(anyrpc)
    # AnyRPC のグローバル `include_directories(${CMAKE_SOURCE_DIR}/include)` を補正し、
    # anyrpc ターゲット自体に正しい include path を public で持たせる。
    target_include_directories(anyrpc PUBLIC
        $<BUILD_INTERFACE:${anyrpc_SOURCE_DIR}/include>
    )
    # Spix の find_package(AnyRPC REQUIRED) を欺くため、CACHE 変数とエイリアスを供給。
    if(NOT TARGET AnyRPC::anyrpc)
        add_library(AnyRPC::anyrpc ALIAS anyrpc)
    endif()
    set(AnyRPC_INCLUDE_DIRS "${anyrpc_SOURCE_DIR}/include" CACHE PATH "" FORCE)
    set(AnyRPC_LIBRARIES anyrpc CACHE STRING "" FORCE)
    # Spix は `install(EXPORT SpixCoreTargets ...)` で SpixCore をエクスポートするが、
    # その link interface に AnyRPC::anyrpc → anyrpc を含むため、anyrpc も同じ
    # export set に登録しないと configure 時に「target not in any export set」で
    # 失敗する。`cmake --install` を実行しない限り副作用はない。
    install(TARGETS anyrpc EXPORT SpixCoreTargets)

    # Spix：QtQuick 向けライブラリのみ有効化。
    set(SPIX_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SPIX_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(SPIX_BUILD_QTQUICK ON CACHE BOOL "" FORCE)
    set(SPIX_BUILD_QTWIDGETS OFF CACHE BOOL "" FORCE)
    set(SPIX_QT_MAJOR "6" CACHE STRING "" FORCE)
    FetchContent_Declare(
        spix
        GIT_REPOSITORY https://github.com/faaxm/spix.git
        GIT_TAG v0.14
    )
    FetchContent_MakeAvailable(spix)
endif()

add_subdirectory(Shared/Schema)
add_subdirectory(Shared/Widgets)
add_subdirectory(Editor)
add_subdirectory(Simulator)

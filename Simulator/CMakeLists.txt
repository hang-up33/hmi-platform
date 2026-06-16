# Task 22: Simulator の QML module を STATIC library 化し、
# hmi_simulator（PC ビルド）と hmi_runtime（PC sanity + Yocto SDK クロスビルド）の
# 両方から共有できるようにする。
#
# Qt の qt_add_qml_module を実行ファイルに直結すると別の実行ファイルから
# 共有できないため、STATIC library として切り出し、利用側は qmlplugin を
# target_link_libraries で取り込む。パターンは Shared/Widgets に倣う
# （CLAUDE.md「共有 QML モジュールは STATIC でビルドし、利用側アプリで
# plugin ターゲットをリンクする」原則）。

qt_add_qml_module(hmi_simulator_qml STATIC
    URI HmiSimulator
    VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiSimulator
    QML_FILES
        qml/Main.qml
        qml/SimulatorCanvas.qml
)

# Simulator の C++ ソース（main.cpp / ProjectLoader）は Simulator/ にのみ置く。
# hmi_simulator と hmi_runtime の 2 ターゲットが同じソースを使うため、
# 共通の CMake function で executable を生成する。関数は CMake 上は
# グローバルスコープなので、add_subdirectory(Simulator) 後に
# Runtime/ から呼び出せる。CMAKE_CURRENT_FUNCTION_LIST_DIR は関数が
# 定義された場所（このディレクトリ = Simulator/）を指すため、Runtime/
# から呼んでも Simulator/src/ のソースを正しく参照できる。
function(hmi_add_simulator_like_executable target)
    qt_add_executable(${target}
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/main.cpp"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/ProjectLoader.cpp"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/ProjectLoader.h"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/ModbusController.cpp"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/ModbusController.h"
        "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/ScreenshotGrabber.h"
    )

    target_link_libraries(${target}
        PRIVATE
            Qt6::Quick
            Qt6::SerialBus
            hmi_schema
            hmi_widgetsplugin
            hmi_simulator_qmlplugin
    )

    # Task 16: E2E テスト用 Spix エンドポイント。`--e2e` 起動時のみ
    # 実際にネットワークを開くため、リンクしても通常起動には影響しない。
    # Windows MinGW では AnyRPC の libstdc++ 衝突により無効化される
    # （HMI_ENABLE_E2E のデフォルトがルート CMakeLists.txt で OFF になる）。
    if(HMI_ENABLE_E2E)
        target_compile_definitions(${target} PRIVATE HMI_HAS_SPIX)
        target_link_libraries(${target} PRIVATE Spix::QtQuick)
    endif()

    set_target_properties(${target} PROPERTIES
        MACOSX_BUNDLE TRUE
        WIN32_EXECUTABLE TRUE
    )

    # Windows: Atlas ブランドアイコンを exe に埋め込む（Editor と同じ仕組み）。
    # hmi_simulator / hmi_runtime（PC ビルド時）の両方に効く。Yocto クロスでは
    # WIN32 が偽なので何もしない。.rc はターゲットごとに別名で生成して衝突を避ける。
    if(WIN32)
        set(HMI_APP_ICON_PATH "${CMAKE_SOURCE_DIR}/branding/atlas.ico")
        configure_file(
            "${CMAKE_SOURCE_DIR}/branding/app_icon.rc.in"
            "${CMAKE_CURRENT_BINARY_DIR}/${target}_icon.rc"
            @ONLY
        )
        target_sources(${target} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/${target}_icon.rc")
    endif()
endfunction()

hmi_add_simulator_like_executable(hmi_simulator)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

qt_add_executable(hmi_editor
    src/main.cpp
    src/ProjectIo.cpp
    src/ProjectIo.h
    src/ScreenshotGrabber.h
)

qt_add_qml_module(hmi_editor
    URI HmiEditor
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Canvas.qml
        qml/EditableWidget.qml
        qml/InspectorSection.qml
        qml/SamplePalette.qml
        qml/EditorToolbar.qml
        qml/EditorDialogs.qml
)

target_link_libraries(hmi_editor
    PRIVATE
        Qt6::Quick
        hmi_schema
        hmi_widgetsplugin
)

# Task 16: E2E テスト用 Spix エンドポイント。`--e2e` 起動時のみ
# 実際にネットワークを開くため、リンクしても通常起動には影響しない。
# Windows MinGW では AnyRPC の libstdc++ 衝突により無効化される
# （HMI_ENABLE_E2E のデフォルトがルート CMakeLists.txt で OFF になる）。
if(HMI_ENABLE_E2E)
    target_compile_definitions(hmi_editor PRIVATE HMI_HAS_SPIX)
    target_link_libraries(hmi_editor PRIVATE Spix::QtQuick)
endif()

set_target_properties(hmi_editor PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# Windows: Atlas ブランドアイコンを exe に埋め込む。
# branding/app_icon.rc.in の @HMI_APP_ICON_PATH@ を atlas.ico の絶対パスで埋めた
# .rc を生成し、ターゲットソースに加える（windres が埋め込み）。
if(WIN32)
    set(HMI_APP_ICON_PATH "${CMAKE_SOURCE_DIR}/branding/atlas.ico")
    configure_file(
        "${CMAKE_SOURCE_DIR}/branding/app_icon.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/hmi_editor_icon.rc"
        @ONLY
    )
    target_sources(hmi_editor PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/hmi_editor_icon.rc")
endif()

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

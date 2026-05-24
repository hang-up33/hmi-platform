qt_add_executable(hmi_editor
    src/main.cpp
)

qt_add_qml_module(hmi_editor
    URI HmiEditor
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Canvas.qml
)

target_link_libraries(hmi_editor
    PRIVATE
        Qt6::Quick
        hmi_schema
)

set_target_properties(hmi_editor PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

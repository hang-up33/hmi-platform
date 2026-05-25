qt_add_executable(hmi_simulator
    src/main.cpp
    src/ProjectLoader.cpp
    src/ProjectLoader.h
)

qt_add_qml_module(hmi_simulator
    URI HmiSimulator
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/SimulatorCanvas.qml
)

target_link_libraries(hmi_simulator
    PRIVATE
        Qt6::Quick
        hmi_schema
        hmi_widgetsplugin
)

set_target_properties(hmi_simulator PROPERTIES
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

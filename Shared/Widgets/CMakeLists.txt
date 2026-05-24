qt_add_qml_module(hmi_widgets STATIC
    URI HmiWidgets
    VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets
    QML_FILES
        qml/HmiButton.qml
)

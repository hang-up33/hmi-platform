# Task 39: VariableStore は `pragma Singleton` の QML singleton。CMake 側でも
# QT_QML_SINGLETON_TYPE を立てないと qmldir に singleton 登録されず、利用側で
# `VariableStore.foo()` がメソッド解決できない（型参照になる）。
set_source_files_properties(qml/VariableStore.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(hmi_widgets STATIC
    URI HmiWidgets
    VERSION 1.0
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets
    QML_FILES
        qml/HmiButton.qml
        qml/HmiLabel.qml
        qml/HmiNumericField.qml
        qml/HmiTrend.qml
        qml/HmiMeter.qml
        qml/HmiSimpleButton.qml
        qml/VariableStore.qml
        # Task RF-E: Button/Label/SimpleButton の delegate ロジックを集約したホスト QML
        # （表示専用 + binding 読取のみの種別が対象。NumericField/Trend/Meter は対象外）
        qml/ButtonHost.qml
        qml/LabelHost.qml
        qml/SimpleButtonHost.qml
)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

qt_add_library(hmi_schema STATIC
    src/WidgetData.cpp
    src/ScreenData.cpp
    src/ProjectData.cpp
    src/VariableData.cpp
    src/ActionData.cpp
    src/BindingData.cpp
    src/SourceData.cpp
    src/ConnectionData.cpp
)

target_include_directories(hmi_schema PUBLIC include)

target_link_libraries(hmi_schema
    PUBLIC
        Qt6::Core
)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

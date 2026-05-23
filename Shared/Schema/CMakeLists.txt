qt_add_library(hmi_schema STATIC
    src/schema_placeholder.cpp
)

target_include_directories(hmi_schema PUBLIC include)

target_link_libraries(hmi_schema
    PUBLIC
        Qt6::Core
)

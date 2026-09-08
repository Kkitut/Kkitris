cmake_minimum_required(VERSION 3.31)
project(Kkitris)
set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

FetchContent_Declare(
    glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG d9d6f0f1f967807ffade6598ea9a631ebaf37a56
)

FetchContent_MakeAvailable(glfw)

find_package(Vulkan REQUIRED)
find_program(GLSLC glslc REQUIRED)

set(SHADER_DIR ${CMAKE_SOURCE_DIR}/src/shader)
set(SHADER_OUT_DIR ${CMAKE_BINARY_DIR}/shader)

file(GLOB SHADERS CONFIGURE_DEPENDS
    ${SHADER_DIR}/*.vert
    ${SHADER_DIR}/*.frag
)

set(SPIRV_FILES)

foreach(SHADER ${SHADERS})
    get_filename_component(NAME ${SHADER} NAME)

    set(OUTPUT ${SHADER_OUT_DIR}/${NAME}.spv)

    add_custom_command(
        OUTPUT ${OUTPUT}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${SHADER_OUT_DIR}
        COMMAND ${GLSLC} ${SHADER} -o ${OUTPUT}
        DEPENDS ${SHADER}
        COMMENT "Compiling ${NAME}"
        VERBATIM
    )

    list(APPEND SPIRV_FILES
        ${OUTPUT}
    )
endforeach()

add_custom_target(shaders
    ALL
    DEPENDS ${SPIRV_FILES}
)

add_executable(Kkitris)

file(GLOB SOURCES CONFIGURE_DEPENDS
    src/*.c
)

target_sources(Kkitris
    PRIVATE ${SOURCES}
)

target_link_libraries(Kkitris
    PRIVATE
    glfw
    Vulkan::Vulkan
)

add_dependencies(Kkitris shaders)
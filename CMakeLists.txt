cmake_minimum_required(VERSION 4.0)

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

add_executable(Kkitris)

file(GLOB SOURCES CONFIGURE_DEPENDS
    src/*.c
)

target_sources(Kkitris
    PRIVATE ${SOURCES}
)

target_link_libraries(Kkitris PRIVATE glfw)
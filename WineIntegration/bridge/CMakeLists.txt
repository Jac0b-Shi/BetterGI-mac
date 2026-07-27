cmake_minimum_required(VERSION 3.24)

project(BetterGIWineInputBridge VERSION 1.0.0 LANGUAGES C)

if(NOT WIN32)
    message(FATAL_ERROR "BetterGIWineInputBridge must be cross-compiled for Windows")
endif()

add_executable(BetterGIWineInputBridge
    src/main.c
)

target_include_directories(BetterGIWineInputBridge PRIVATE include)
target_compile_features(BetterGIWineInputBridge PRIVATE c_std_11)
target_compile_definitions(BetterGIWineInputBridge PRIVATE
    WIN32_LEAN_AND_MEAN
    UNICODE
    _UNICODE
)
target_compile_options(BetterGIWineInputBridge PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)
target_link_libraries(BetterGIWineInputBridge PRIVATE ws2_32 user32)

if(MINGW)
    target_link_options(BetterGIWineInputBridge PRIVATE
        -static
        -static-libgcc
    )
endif()

# iOS Simulator Toolchain for CMake
#
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=cmake/ios-simulator.toolchain.cmake ..

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING "Minimum iOS version")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Target architecture")

# Find iOS Simulator SDK
execute_process(
    COMMAND xcrun --sdk iphonesimulator --show-sdk-path
    OUTPUT_VARIABLE CMAKE_OSX_SYSROOT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Find compilers
execute_process(
    COMMAND xcrun --sdk iphonesimulator --find clang
    OUTPUT_VARIABLE CMAKE_C_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND xcrun --sdk iphonesimulator --find clang++
    OUTPUT_VARIABLE CMAKE_CXX_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# iOS Simulator-specific flags
set(CMAKE_C_FLAGS_INIT "-arch arm64 -isysroot ${CMAKE_OSX_SYSROOT} -mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(CMAKE_CXX_FLAGS_INIT "-arch arm64 -isysroot ${CMAKE_OSX_SYSROOT} -mios-simulator-version-min=${CMAKE_OSX_DEPLOYMENT_TARGET}")

# Don't search host paths
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# Skip try_compile for cross-compilation
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

message(STATUS "iOS Simulator SDK: ${CMAKE_OSX_SYSROOT}")
message(STATUS "iOS Simulator C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "iOS Simulator CXX Compiler: ${CMAKE_CXX_COMPILER}")

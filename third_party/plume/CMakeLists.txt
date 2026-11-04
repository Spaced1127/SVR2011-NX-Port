cmake_minimum_required(VERSION 3.20)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)

if(APPLE AND NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    # 10.15 because of our use of supportsFamily()
    set(CMAKE_OSX_DEPLOYMENT_TARGET "10.15" CACHE STRING "Minimum macOS deployment target")
endif()

project(plume)

if(APPLE)
    enable_language(OBJC OBJCXX)
endif()

string(COMPARE EQUAL ${CMAKE_SYSTEM_NAME} "Linux" IS_LINUX)

# Project options
include(CMakeDependentOption)
cmake_dependent_option(PLUME_SDL_VULKAN_ENABLED "Enable SDL Vulkan integration" OFF IS_LINUX OFF)
cmake_dependent_option(PLUME_D3D12_AGILITY_SDK_ENABLED "Enable D3D12 Agility SDK" OFF WIN32 OFF)
cmake_dependent_option(PLUME_APPLE_RETINA_ENABLED "Enable Apple Retina display support" ON APPLE ON)
option(PLUME_BUILD_EXAMPLES "Build example applications" OFF)

# Windows-specific definitions
if(WIN32)
    add_compile_definitions(NOMINMAX)
endif()

# Enable SDL Vulkan support
if(PLUME_SDL_VULKAN_ENABLED)
    if (NOT TARGET SDL2::SDL2)
        find_package(SDL2 REQUIRED)
    else()
        set(SDL2_INCLUDE_DIRS "$<TARGET_PROPERTY:SDL2::SDL2,INTERFACE_INCLUDE_DIRECTORIES>")
    endif()

    message(STATUS "Plume - Building with SDL2_INCLUDE_DIRS: ${SDL2_INCLUDE_DIRS}")
endif()

# Enable D3D12 Agility SDK support
if(PLUME_D3D12_AGILITY_SDK_ENABLED)
    find_package(directx-headers CONFIG REQUIRED)
    find_package(directx12-agility CONFIG REQUIRED)
endif()

# Print status messages
message(STATUS "Plume - Building with backends: Vulkan=1 Metal=${APPLE} D3D12=${WIN32}")
message(STATUS "Plume - SDL Vulkan integration: ${PLUME_SDL_VULKAN_ENABLED}")
message(STATUS "Plume - D3D12 Agility SDK: ${PLUME_D3D12_AGILITY_SDK_ENABLED}")
message(STATUS "Plume - Building examples: ${PLUME_BUILD_EXAMPLES}")

# Basic source files that are always included
set(PLUME_SOURCES
    plume_vulkan.cpp
    plume_vulkan.h
)

# Platform-specific files
if(APPLE)
    list(APPEND PLUME_SOURCES
        plume_metal.cpp
        plume_metal.h
        plume_apple.mm
        plume_apple.h
    )
elseif(WIN32)
    list(APPEND PLUME_SOURCES
        plume_d3d12.cpp
        plume_d3d12.h
        plume_d3d11.cpp
        plume_d3d11.h
        ${CMAKE_CURRENT_SOURCE_DIR}/contrib/D3D12MemoryAllocator/src/D3D12MemAlloc.cpp
    )
endif()

# Create target
add_library(plume STATIC ${PLUME_SOURCES})

# Include directories
target_include_directories(plume PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/contrib/volk
    ${CMAKE_CURRENT_SOURCE_DIR}/contrib/Vulkan-Headers/include
    ${CMAKE_CURRENT_SOURCE_DIR}/contrib/VulkanMemoryAllocator/include
)

if(WIN32)
    target_include_directories(plume PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/contrib/D3D12MemoryAllocator/include
    )
endif()

if(PLUME_PLATFORM_SWITCH)
    target_compile_definitions(plume PUBLIC VK_USE_PLATFORM_VI_NN)
    # Horizon has no pthread_rwlock: VMA's default std::shared_mutex throws
    # std::system_error(ENOSYS) in vmaCreateAllocator. Use VMA's mutex-based
    # lock. PUBLIC so every consumer that includes vk_mem_alloc.h agrees on
    # the VmaMutex layout.
    target_compile_definitions(plume PUBLIC VMA_USE_STL_SHARED_MUTEX=0)
    if(DEFINED PLUME_SWITCH_DEVKITPRO AND NOT "${PLUME_SWITCH_DEVKITPRO}" STREQUAL "")
        target_include_directories(plume PUBLIC "${PLUME_SWITCH_DEVKITPRO}/libnx/include")
    elseif(DEFINED DEVKITPRO AND NOT "${DEVKITPRO}" STREQUAL "")
        target_include_directories(plume PUBLIC "${DEVKITPRO}/libnx/include")
    endif()
endif()

# deko3d back end (banjo-nx/sa2-nx, MIT). Only on the Switch: devkitPro's
# deko3d and uam's source tree (third_party/uam) are linked here.
option(PLUME_DEKO3D "deko3d back end (Switch)" OFF)
set(PLUME_SWITCH_UAM_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../uam" CACHE PATH "uam source tree")
if(PLUME_DEKO3D)
    if(NOT PLUME_PLATFORM_SWITCH)
        message(FATAL_ERROR "PLUME_DEKO3D is only available for the Switch")
    endif()
    if(NOT EXISTS "${PLUME_SWITCH_UAM_DIR}/CMakeLists.txt")
        message(FATAL_ERROR "PLUME_DEKO3D needs PLUME_SWITCH_UAM_DIR (uam's source): ${PLUME_SWITCH_UAM_DIR}")
    endif()
    if(DEFINED PLUME_SWITCH_DEVKITPRO AND NOT "${PLUME_SWITCH_DEVKITPRO}" STREQUAL "")
        set(_plume_dkp "${PLUME_SWITCH_DEVKITPRO}")
    else()
        set(_plume_dkp "${DEVKITPRO}")
    endif()
    if(NOT TARGET uamlib)
        set(NX_ROOT "${_plume_dkp}/libnx")
        add_subdirectory("${PLUME_SWITCH_UAM_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/uam")
    endif()
    target_sources(plume PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}/plume_deko3d.cpp"
        "${CMAKE_CURRENT_SOURCE_DIR}/plume_deko3d_commands.cpp")
    target_compile_definitions(plume PUBLIC PLUME_DEKO3D=1)
    target_include_directories(plume PRIVATE "${PLUME_SWITCH_UAM_DIR}")
    # uam's Mesa (19) and the static NVK's Mesa define functions with the same
    # names: uam's strong symbols are made local, its API (uam::*) stays global.
    set(PLUME_DEKO3D_BIN "${_plume_dkp}/devkitA64/bin")
    set(PLUME_DEKO3D_HOST_EXE "")
    if(CMAKE_HOST_WIN32)
        set(PLUME_DEKO3D_HOST_EXE ".exe")
    endif()
    set(plume_uam_local "${CMAKE_CURRENT_BINARY_DIR}/uam_local.o")
    add_custom_command(
        OUTPUT "${plume_uam_local}"
        COMMAND "${CMAKE_COMMAND}"
                "-DLD=${PLUME_DEKO3D_BIN}/aarch64-none-elf-ld${PLUME_DEKO3D_HOST_EXE}"
                "-DNM=${PLUME_DEKO3D_BIN}/aarch64-none-elf-nm${PLUME_DEKO3D_HOST_EXE}"
                "-DOBJCOPY=${PLUME_DEKO3D_BIN}/aarch64-none-elf-objcopy${PLUME_DEKO3D_HOST_EXE}"
                "-DARCHIVE=$<TARGET_FILE:uamlib>" "-DOUT=${plume_uam_local}"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/plume_uam_localize.cmake"
        DEPENDS uamlib "${CMAKE_CURRENT_SOURCE_DIR}/plume_uam_localize.cmake"
        COMMENT "uam with its strong symbols local but its API (uam_local.o)"
        VERBATIM)
    add_custom_target(plume_uam_local DEPENDS "${plume_uam_local}")
    add_dependencies(plume plume_uam_local)
    target_link_libraries(plume PUBLIC "${plume_uam_local}" "${_plume_dkp}/libnx/lib/libdeko3d.a" nx)
    message(STATUS "Plume - deko3d back end: ON (uam ${PLUME_SWITCH_UAM_DIR})")
endif()

if(PLUME_SDL_VULKAN_ENABLED)
    target_compile_definitions(plume PUBLIC PLUME_SDL_VULKAN_ENABLED)
    target_include_directories(plume PUBLIC ${SDL2_INCLUDE_DIRS})
endif()

if(PLUME_D3D12_AGILITY_SDK_ENABLED)
    target_compile_definitions(plume PUBLIC PLUME_D3D12_AGILITY_SDK_ENABLED)
    target_compile_definitions(plume PRIVATE D3D12MA_USING_DIRECTX_HEADERS)
    target_link_libraries(plume PRIVATE Microsoft::DirectX-Headers Microsoft::DirectX-Guids Microsoft::DirectX12-Agility)
endif()

# Platform-specific includes and shader compilation
if(APPLE)
    if(PLUME_APPLE_RETINA_ENABLED)
        target_compile_definitions(plume PRIVATE PLUME_APPLE_RETINA_ENABLED)
    endif()

    target_include_directories(plume PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/contrib/metal-cpp
    )
endif()

# Add examples if requested
if(PLUME_BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()

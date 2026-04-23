# Set OpenGL_GL_PREFERENCE to new "GLVND" even when legacy library exists and
# cmake is <= 3.10
#
# See https://cmake.org/cmake/help/latest/policy/CMP0072.html for more
# information.
if(POLICY CMP0072)
  cmake_policy(SET CMP0072 NEW)
endif()

set(RAYLIB_DEPENDENCIES "include(CMakeFindDependencyMacro)")

if (${PLATFORM} STREQUAL "Desktop")
    set(PLATFORM_CPP "PLATFORM_DESKTOP")

    if (APPLE)
        # Need to force OpenGL 3.3 on OS X
        # See: https://github.com/raysan5/raylib/issues/341
        set(GRAPHICS "GRAPHICS_API_OPENGL_33")
        find_library(OPENGL_LIBRARY OpenGL)
        set(LIBS_PRIVATE ${OPENGL_LIBRARY})
        link_libraries("${LIBS_PRIVATE}")
        if (NOT CMAKE_SYSTEM STRLESS "Darwin-18.0.0")
            add_definitions(-DGL_SILENCE_DEPRECATION)
            MESSAGE(AUTHOR_WARNING "OpenGL is deprecated starting with macOS 10.14 (Mojave)!")
        endif ()
    elseif (WIN32)
        add_definitions(-D_CRT_SECURE_NO_WARNINGS)
        find_package(OpenGL QUIET)
        set(LIBS_PRIVATE ${OPENGL_LIBRARIES} winmm)
    elseif("${CMAKE_SYSTEM_NAME}" MATCHES "QNX")
        set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
        find_library(GLESV2 GLESv2)
        find_library(EGL EGL)
        set(LIBS_PUBLIC m)
        set(LIBS_PRIVATE ${GLESV2} ${EGL} atomic pthread dl)
    elseif (UNIX)
        find_library(pthread NAMES pthread)
        find_package(OpenGL QUIET)
        if ("${OPENGL_LIBRARIES}" STREQUAL "")
            set(OPENGL_LIBRARIES "GL")
        endif ()

        if ("${CMAKE_SYSTEM_NAME}" MATCHES "(Net|Open)BSD")
            find_library(OSS_LIBRARY ossaudio)
        endif ()

        set(LIBS_PRIVATE pthread ${OPENGL_LIBRARIES} ${OSS_LIBRARY})
        set(LIBS_PUBLIC m)
    else ()
        find_library(pthread NAMES pthread)
        find_package(OpenGL QUIET)
        if ("${OPENGL_LIBRARIES}" STREQUAL "")
            set(OPENGL_LIBRARIES "GL")
        endif ()

        set(LIBS_PRIVATE pthread ${OPENGL_LIBRARIES} ${OSS_LIBRARY})
        set(LIBS_PUBLIC m)

        if ("${CMAKE_SYSTEM_NAME}" MATCHES "(Net|Open)BSD")
            find_library(OSS_LIBRARY ossaudio)
        else ()
            set(LIBS_PRIVATE ${LIBS_PRIVATE} atomic)
        endif ()

        if (NOT "${CMAKE_SYSTEM_NAME}" MATCHES "(Net|Open)BSD" AND USE_AUDIO)
            set(LIBS_PRIVATE ${LIBS_PRIVATE} dl)
        endif ()
    endif ()

elseif (${PLATFORM} STREQUAL "Web")
    set(PLATFORM_CPP "PLATFORM_WEB")
    if(NOT GRAPHICS)
        set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
    endif()
    set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")

elseif (${PLATFORM} STREQUAL "Android")
    set(PLATFORM_CPP "PLATFORM_ANDROID")
    set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    list(APPEND raylib_sources ${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c)
    include_directories(${ANDROID_NDK}/sources/android/native_app_glue)

    # NOTE: We remove '-Wl,--no-undefined' (set by default) as it conflicts with '-Wl,-undefined,dynamic_lookup' needed 
    #       for compiling with the missing 'void main(void)' declaration in `android_main()`.
    #       We also remove other unnecessary or problematic flags.

    string(REPLACE "-Wl,--no-undefined -Qunused-arguments" "" CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")
    string(REPLACE "-static-libstdc++" "" CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS}")

    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--exclude-libs,libatomic.a -Wl,--build-id -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--warn-shared-textrel -Wl,--fatal-warnings -u ANativeActivity_onCreate -Wl,-undefined,dynamic_lookup")

    find_library(OPENGL_LIBRARY OpenGL)
    set(LIBS_PRIVATE log android EGL GLESv2 OpenSLES atomic c)
    set(LIBS_PUBLIC m)

elseif ("${PLATFORM}" STREQUAL "DRM")
    set(PLATFORM_CPP "PLATFORM_DRM")

    add_definitions(-D_DEFAULT_SOURCE)
    add_definitions(-DPLATFORM_DRM)

    find_library(DRM drm)

    if (NOT CMAKE_CROSSCOMPILING OR NOT CMAKE_SYSROOT)
        include_directories(/usr/include/libdrm)
    endif ()

    if ("${OPENGL_VERSION}" STREQUAL "Software")
        # software rendering does not require EGL/GBM.
        set(GRAPHICS "GRAPHICS_API_OPENGL_SOFTWARE")
        set(LIBS_PRIVATE ${DRM} atomic pthread dl)
    else ()
        set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
        add_definitions(-DEGL_NO_X11)

        find_library(GLESV2 GLESv2)
        find_library(EGL EGL)
        find_library(GBM gbm)

        set(LIBS_PRIVATE ${GLESV2} ${EGL} ${DRM} ${GBM} atomic pthread dl)
    endif ()
    set(LIBS_PUBLIC m)

elseif ("${PLATFORM}" STREQUAL "SDL")
	# First, check if SDL is included as a subdirectory
	if(TARGET SDL3::SDL3)
		message(STATUS "Using SDL3 from subdirectory")
		set(PLATFORM_CPP "PLATFORM_DESKTOP_SDL")
		set(LIBS_PRIVATE SDL3::SDL3)
		add_compile_definitions(USING_SDL3_PROJECT)
	elseif(TARGET SDL2::SDL2)
		message(STATUS "Using SDL2 from subdirectory")
		set(PLATFORM_CPP "PLATFORM_DESKTOP_SDL")
		set(LIBS_PRIVATE SDL2::SDL2)
		add_compile_definitions(USING_SDL2_PROJECT)
	else()
		# No SDL added via add_subdirectory(), try find_package()
		message(STATUS "No SDL target from subdirectory, searching via find_package()...")

		# First try SDL3
		find_package(SDL3 QUIET)
		if(SDL3_FOUND)
			message(STATUS "Found SDL3 via find_package()")
			set(LIBS_PUBLIC SDL3::SDL3)
			set(RAYLIB_DEPENDENCIES "${RAYLIB_DEPENDENCIES}\nfind_dependency(SDL3 REQUIRED)")
			set(PLATFORM_CPP "PLATFORM_DESKTOP_SDL")
			add_compile_definitions(USING_SDL3_PACKAGE)
		else()
			# Fallback to SDL2
			find_package(SDL2 REQUIRED)
			message(STATUS "Found SDL2 via find_package()")
			set(PLATFORM_CPP "PLATFORM_DESKTOP_SDL")
			set(LIBS_PUBLIC SDL2::SDL2)
			set(RAYLIB_DEPENDENCIES "${RAYLIB_DEPENDENCIES}\nfind_dependency(SDL2 REQUIRED)")
			add_compile_definitions(USING_SDL2_PACKAGE)
		endif()
	endif()	

elseif ("${PLATFORM}" STREQUAL "RGFW")
    set(PLATFORM_CPP "PLATFORM_DESKTOP_RGFW")

    if (APPLE)
        find_library(COCOA Cocoa)
        find_library(OPENGL OpenGL)

        set(LIBS_PRIVATE ${COCOA} ${OPENGL})
    elseif (WIN32)
        find_package(OpenGL REQUIRED)

        set(LIBS_PRIVATE ${OPENGL_LIBRARIES} gdi32)
    elseif("${CMAKE_SYSTEM_NAME}" MATCHES "QNX")
        message(FATAL_ERROR "RGFW platform does not support QNX. Use PLATFORM=Desktop or PLATFORM=SDL instead.")
    elseif (UNIX)
        find_package(X11 REQUIRED)
        find_package(OpenGL REQUIRED)

        set(LIBS_PRIVATE ${X11_LIBRARIES} ${OPENGL_LIBRARIES})
    endif ()

elseif ("${PLATFORM}" STREQUAL "WebRGFW")
    set(PLATFORM_CPP "PLATFORM_WEB_RGFW")
    set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
    set(CMAKE_STATIC_LIBRARY_SUFFIX ".a")

elseif ("${PLATFORM}" STREQUAL "Memory")
    set(PLATFORM_CPP "PLATFORM_MEMORY")
    set(GRAPHICS "GRAPHICS_API_OPENGL_SOFTWARE")
    set(OPENGL_VERSION "Software")

    if(WIN32 OR CMAKE_C_COMPILER MATCHES "mingw|mingw32|mingw64")
        set(LIBS_PRIVATE winmm)
    endif()
endif ()

if (NOT ${OPENGL_VERSION} MATCHES "OFF")
    set(SUGGESTED_GRAPHICS "${GRAPHICS}")

    if (${OPENGL_VERSION} MATCHES "4.3")
        set(GRAPHICS "GRAPHICS_API_OPENGL_43")
    elseif (${OPENGL_VERSION} MATCHES "3.3")
        set(GRAPHICS "GRAPHICS_API_OPENGL_33")
    elseif (${OPENGL_VERSION} MATCHES "2.1")
        set(GRAPHICS "GRAPHICS_API_OPENGL_21")
    elseif (${OPENGL_VERSION} MATCHES "1.1")
        set(GRAPHICS "GRAPHICS_API_OPENGL_11")
    elseif (${OPENGL_VERSION} MATCHES "ES 2.0")
        set(GRAPHICS "GRAPHICS_API_OPENGL_ES2")
    elseif (${OPENGL_VERSION} MATCHES "ES 3.0")
        set(GRAPHICS "GRAPHICS_API_OPENGL_ES3")
    elseif (${OPENGL_VERSION} MATCHES "Software")
        set(GRAPHICS "GRAPHICS_API_OPENGL_SOFTWARE")
    endif ()
    if (NOT "${SUGGESTED_GRAPHICS}" STREQUAL "" AND NOT "${SUGGESTED_GRAPHICS}" STREQUAL "${GRAPHICS}")
        message(WARNING "You are overriding the suggested GRAPHICS=${SUGGESTED_GRAPHICS} with ${GRAPHICS}! This may fail.")
    endif ()
endif ()

if (NOT GRAPHICS)
    set(GRAPHICS "GRAPHICS_API_OPENGL_33")
endif ()

set(LIBS_PRIVATE ${LIBS_PRIVATE} ${OPENAL_LIBRARY})

if (${PLATFORM} MATCHES "Desktop")
    set(LIBS_PRIVATE ${LIBS_PRIVATE} glfw)
endif ()

# Font rendering (TTF/OTF) requires FreeType for rasterization and HarfBuzz for shaping.
# On Linux/macOS these are normally installed via the system package manager; on Windows
# they're not, so we fall back to FetchContent to build them from source automatically.
# Users can force FetchContent with -DRAYLIB_FETCH_FONT_DEPS=ON.
option(RAYLIB_FETCH_FONT_DEPS "Always build FreeType and HarfBuzz from source via FetchContent" OFF)

if (SUPPORT_FILEFORMAT_TTF)
    set(_raylib_fetch_freetype ${RAYLIB_FETCH_FONT_DEPS})
    set(_raylib_fetch_harfbuzz ${RAYLIB_FETCH_FONT_DEPS})

    # --- FreeType: prefer system install, fall back to FetchContent ---
    if (NOT _raylib_fetch_freetype)
        find_package(Freetype QUIET)
        if (NOT Freetype_FOUND)
            message(STATUS "raylib: Freetype not found via find_package, will build from source via FetchContent")
            set(_raylib_fetch_freetype TRUE)
        endif ()
    endif ()

    # --- HarfBuzz: try pkg-config, then CMake config (vcpkg), then FetchContent ---
    if (NOT _raylib_fetch_harfbuzz)
        set(HARFBUZZ_FOUND FALSE)
        find_package(PkgConfig QUIET)
        if (PkgConfig_FOUND)
            pkg_check_modules(HARFBUZZ QUIET IMPORTED_TARGET harfbuzz)
        endif ()
        if (NOT HARFBUZZ_FOUND)
            find_package(harfbuzz QUIET CONFIG)
            if (TARGET harfbuzz::harfbuzz)
                set(HARFBUZZ_FOUND TRUE)
            endif ()
        endif ()
        if (NOT HARFBUZZ_FOUND)
            message(STATUS "raylib: HarfBuzz not found via pkg-config or find_package, will build from source via FetchContent")
            set(_raylib_fetch_harfbuzz TRUE)
        endif ()
    endif ()

    if (_raylib_fetch_freetype OR _raylib_fetch_harfbuzz)
        include(FetchContent)
    endif ()

    # FreeType from source: minimal config, no external image codecs or compression libs
    if (_raylib_fetch_freetype)
        set(FT_DISABLE_ZLIB ON CACHE BOOL "" FORCE)
        set(FT_DISABLE_BZIP2 ON CACHE BOOL "" FORCE)
        set(FT_DISABLE_PNG ON CACHE BOOL "" FORCE)
        set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "" FORCE)  # Avoid circular dep (FT optional auto-hinting)
        set(FT_DISABLE_BROTLI ON CACHE BOOL "" FORCE)
        FetchContent_Declare(freetype
            GIT_REPOSITORY https://gitlab.freedesktop.org/freetype/freetype.git
            GIT_TAG VER-2-13-3
            GIT_SHALLOW TRUE)
        FetchContent_MakeAvailable(freetype)
        if (NOT TARGET Freetype::Freetype)
            add_library(Freetype::Freetype ALIAS freetype)
        endif ()
    endif ()

    # HarfBuzz from source: only what we need (no ICU/Graphite/GLib/GObject)
    if (_raylib_fetch_harfbuzz)
        set(HB_HAVE_FREETYPE ON CACHE BOOL "" FORCE)
        set(HB_BUILD_SUBSET OFF CACHE BOOL "" FORCE)
        set(HB_BUILD_TESTS OFF CACHE BOOL "" FORCE)
        set(HB_BUILD_UTILS OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_ICU OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_GRAPHITE2 OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_GLIB OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_GOBJECT OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_CORETEXT OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_GDI OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_UNISCRIBE OFF CACHE BOOL "" FORCE)
        set(HB_HAVE_DIRECTWRITE OFF CACHE BOOL "" FORCE)
        FetchContent_Declare(harfbuzz
            GIT_REPOSITORY https://github.com/harfbuzz/harfbuzz.git
            GIT_TAG 10.4.0
            GIT_SHALLOW TRUE)
        FetchContent_MakeAvailable(harfbuzz)
    endif ()

    # Link FreeType (via imported target if present, otherwise classic vars)
    if (TARGET Freetype::Freetype)
        set(LIBS_PRIVATE ${LIBS_PRIVATE} Freetype::Freetype)
    else ()
        include_directories(${FREETYPE_INCLUDE_DIRS})
        set(LIBS_PRIVATE ${LIBS_PRIVATE} ${FREETYPE_LIBRARIES})
    endif ()

    # Link HarfBuzz (config package, pkg-config, or in-tree FetchContent target)
    if (TARGET harfbuzz::harfbuzz)
        set(LIBS_PRIVATE ${LIBS_PRIVATE} harfbuzz::harfbuzz)
    elseif (TARGET PkgConfig::HARFBUZZ)
        set(LIBS_PRIVATE ${LIBS_PRIVATE} PkgConfig::HARFBUZZ)
    elseif (TARGET harfbuzz)
        set(LIBS_PRIVATE ${LIBS_PRIVATE} harfbuzz)
    endif ()

    # Only surface a find_dependency() call in raylib-config.cmake when FreeType came from
    # the system; when built in-tree there's nothing for downstream to find.
    if (NOT _raylib_fetch_freetype)
        set(RAYLIB_DEPENDENCIES "${RAYLIB_DEPENDENCIES}\nfind_dependency(Freetype)")
    endif ()
endif ()

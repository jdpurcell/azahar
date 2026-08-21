
# Determines parameters based on the host and target for downloading the right Qt binaries.
function(determine_qt_parameters target host_out type_out arch_out arch_path_out host_type_out host_arch_out host_arch_path_out)
    # Determine installation parameters for OS, architecture, and compiler
    if (WIN32)
        set(host "windows")
        set(type "desktop")

        if (MINGW)
            set(arch "win64_mingw")
            set(arch_path "mingw_64")
        elseif (MSVC)
            if ("arm64" IN_LIST ARCHITECTURE)
                set(arch_path "msvc2022_arm64")
                set(arch "win64_msvc2022_arm64_cross_compiled")
            elseif ("x86_64" IN_LIST ARCHITECTURE)
                set(arch_path "msvc2022_64")
                set(arch "win64_${arch_path}")
            else()
                message(FATAL_ERROR "Unsupported bundled Qt architecture. Enable USE_SYSTEM_QT and provide your own.")
            endif()

            # In case we're cross-compiling, prepare to also fetch the correct host Qt tools.
            if (CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "AMD64")
                set(host_arch_path "msvc2022_64")
            elseif (CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ARM64")
                set(host_arch_path "msvc2022_64")
            endif()
            set(host_arch "win64_${host_arch_path}")
        else()
            message(FATAL_ERROR "Unsupported bundled Qt toolchain. Enable USE_SYSTEM_QT and provide your own.")
        endif()
    elseif (APPLE)
        set(host "mac")
        set(type "desktop")
        set(arch "clang_64")
        set(arch_path "macos")

        if (IOS)
            set(host_type "${type}")
            set(host_arch "${arch}")
            set(host_arch_path "${arch_path}")

            set(type "ios")
            set(arch "ios")
            set(arch_path "ios")
        endif()
    else()
        set(host "linux")
        set(type "desktop")
        set(arch "linux_gcc_64")
        set(arch_path "linux")
    endif()

    set(${host_out} "${host}" PARENT_SCOPE)
    set(${type_out} "${type}" PARENT_SCOPE)
    set(${arch_out} "${arch}" PARENT_SCOPE)
    set(${arch_path_out} "${arch_path}" PARENT_SCOPE)
    if (DEFINED host_type)
        set(${host_type_out} "${host_type}" PARENT_SCOPE)
    else()
        set(${host_type_out} "${type}" PARENT_SCOPE)
    endif()
    if (DEFINED host_arch)
        set(${host_arch_out} "${host_arch}" PARENT_SCOPE)
    else()
        set(${host_arch_out} "${arch}" PARENT_SCOPE)
    endif()
    if (DEFINED host_arch_path)
        set(${host_arch_path_out} "${host_arch_path}" PARENT_SCOPE)
    else()
        set(${host_arch_path_out} "${arch_path}" PARENT_SCOPE)
    endif()
endfunction()

# Download Qt binaries for a specifc configuration.
function(download_qt_configuration prefix_out target host type arch arch_path base_path)
    set(prefix "${base_path}/${target}/${arch_path}")
    set(install_args install-qt ${host} ${type} ${target} ${arch} --outputdir ${base_path}
            --modules qtmultimedia --archives qttranslations qttools qtsvg qtbase qtdeclarative qtmultimedia)

    if (NOT EXISTS "${prefix}")
        message(STATUS "Downloading Qt binaries for ${target}:${host}:${type}:${arch}:${arch_path}")
        set(naqt_path "${base_path}/naqt")
        set(naqt_dll "${naqt_path}/naqt.dll")
        if (NOT EXISTS "${naqt_dll}")
            set(naqt_archive "${base_path}/naqt.zip")
            file(DOWNLOAD
                    https://github.com/jdpurcell/naqt/releases/download/latest/naqt.zip
                    "${naqt_archive}" SHOW_PROGRESS TLS_VERIFY ON STATUS download_status)
            list(GET download_status 0 download_status_code)
            list(GET download_status 1 download_status_message)
            if (NOT download_status_code EQUAL 0)
                file(REMOVE "${naqt_archive}")
                message(FATAL_ERROR "Failed to download naqt: ${download_status_message}")
            endif()

            file(MAKE_DIRECTORY "${naqt_path}")
            file(ARCHIVE_EXTRACT INPUT "${naqt_archive}" DESTINATION "${naqt_path}")
            file(REMOVE "${naqt_archive}")
        endif()

        find_program(DOTNET_EXECUTABLE dotnet REQUIRED)
        execute_process(COMMAND "${DOTNET_EXECUTABLE}" "${naqt_dll}" ${install_args}
                WORKING_DIRECTORY "${base_path}" RESULT_VARIABLE install_result)
        if (NOT install_result EQUAL 0)
            message(FATAL_ERROR "naqt failed to install Qt (exit code ${install_result})")
        endif()

        message(STATUS "Downloaded Qt binaries for ${target}:${host}:${type}:${arch}:${arch_path} to ${prefix}")
    endif()

    set(${prefix_out} "${prefix}" PARENT_SCOPE)
endfunction()

# This function downloads Qt using naqt.
# The path of the downloaded content will be added to the CMAKE_PREFIX_PATH.
# QT_TARGET_PATH is set to the Qt for the compile target platform.
# QT_HOST_PATH is set to a host-compatible Qt, for running tools.
# Params:
#   target: Full Qt version number to download.
function(download_qt target)
    if (target MATCHES "tools_.*")
        message(FATAL_ERROR "naqt does not support installing Qt tools")
    endif()
    determine_qt_parameters("${target}" host type arch arch_path host_type host_arch host_arch_path)

    get_external_prefix(qt base_path)
    file(MAKE_DIRECTORY "${base_path}")

    download_qt_configuration(prefix "${target}" "${host}" "${type}" "${arch}" "${arch_path}" "${base_path}")
    if (DEFINED host_arch_path AND NOT "${host_arch_path}" STREQUAL "${arch_path}")
        download_qt_configuration(host_prefix "${target}" "${host}" "${host_type}" "${host_arch}" "${host_arch_path}" "${base_path}")
    else()
        set(host_prefix "${prefix}")
    endif()

    set(QT_TARGET_PATH "${prefix}" CACHE STRING "")
    set(QT_HOST_PATH "${host_prefix}" CACHE STRING "")

    # Add the target Qt prefix path so CMake can locate it.
    list(APPEND CMAKE_PREFIX_PATH "${prefix}")
    set(CMAKE_PREFIX_PATH ${CMAKE_PREFIX_PATH} PARENT_SCOPE)
endfunction()

function(download_moltenvk)
    set(MOLTENVK_TAR "${CMAKE_BINARY_DIR}/externals/MoltenVK.tar")
    if (NOT EXISTS "${CMAKE_BINARY_DIR}/externals/MoltenVK")
        if (NOT EXISTS ${MOLTENVK_TAR})
            file(DOWNLOAD https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.1/MoltenVK-all.tar
                ${MOLTENVK_TAR} SHOW_PROGRESS)
        endif()

        execute_process(COMMAND ${CMAKE_COMMAND} -E tar xf "${MOLTENVK_TAR}"
            WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/externals")
    endif()
endfunction()

function(get_external_prefix lib_name prefix_var)
    set(${prefix_var} "${CMAKE_BINARY_DIR}/externals/${lib_name}" PARENT_SCOPE)
endfunction()

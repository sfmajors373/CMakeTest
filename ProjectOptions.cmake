include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(CMakeTest_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(CMakeTest_setup_options)
  option(CMakeTest_ENABLE_HARDENING "Enable hardening" ON)
  option(CMakeTest_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    CMakeTest_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    CMakeTest_ENABLE_HARDENING
    OFF)

  CMakeTest_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR CMakeTest_PACKAGING_MAINTAINER_MODE)
    option(CMakeTest_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(CMakeTest_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(CMakeTest_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(CMakeTest_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(CMakeTest_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(CMakeTest_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(CMakeTest_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(CMakeTest_ENABLE_PCH "Enable precompiled headers" OFF)
    option(CMakeTest_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(CMakeTest_ENABLE_IPO "Enable IPO/LTO" ON)
    option(CMakeTest_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(CMakeTest_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(CMakeTest_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(CMakeTest_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(CMakeTest_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(CMakeTest_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(CMakeTest_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(CMakeTest_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(CMakeTest_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(CMakeTest_ENABLE_PCH "Enable precompiled headers" OFF)
    option(CMakeTest_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      CMakeTest_ENABLE_IPO
      CMakeTest_WARNINGS_AS_ERRORS
      CMakeTest_ENABLE_USER_LINKER
      CMakeTest_ENABLE_SANITIZER_ADDRESS
      CMakeTest_ENABLE_SANITIZER_LEAK
      CMakeTest_ENABLE_SANITIZER_UNDEFINED
      CMakeTest_ENABLE_SANITIZER_THREAD
      CMakeTest_ENABLE_SANITIZER_MEMORY
      CMakeTest_ENABLE_UNITY_BUILD
      CMakeTest_ENABLE_CLANG_TIDY
      CMakeTest_ENABLE_CPPCHECK
      CMakeTest_ENABLE_COVERAGE
      CMakeTest_ENABLE_PCH
      CMakeTest_ENABLE_CACHE)
  endif()

  CMakeTest_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (CMakeTest_ENABLE_SANITIZER_ADDRESS OR CMakeTest_ENABLE_SANITIZER_THREAD OR CMakeTest_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(CMakeTest_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(CMakeTest_global_options)
  if(CMakeTest_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    CMakeTest_enable_ipo()
  endif()

  CMakeTest_supports_sanitizers()

  if(CMakeTest_ENABLE_HARDENING AND CMakeTest_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR CMakeTest_ENABLE_SANITIZER_UNDEFINED
       OR CMakeTest_ENABLE_SANITIZER_ADDRESS
       OR CMakeTest_ENABLE_SANITIZER_THREAD
       OR CMakeTest_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${CMakeTest_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${CMakeTest_ENABLE_SANITIZER_UNDEFINED}")
    CMakeTest_enable_hardening(CMakeTest_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(CMakeTest_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(CMakeTest_warnings INTERFACE)
  add_library(CMakeTest_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  CMakeTest_set_project_warnings(
    CMakeTest_warnings
    ${CMakeTest_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(CMakeTest_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(CMakeTest_options)
  endif()

  include(cmake/Sanitizers.cmake)
  CMakeTest_enable_sanitizers(
    CMakeTest_options
    ${CMakeTest_ENABLE_SANITIZER_ADDRESS}
    ${CMakeTest_ENABLE_SANITIZER_LEAK}
    ${CMakeTest_ENABLE_SANITIZER_UNDEFINED}
    ${CMakeTest_ENABLE_SANITIZER_THREAD}
    ${CMakeTest_ENABLE_SANITIZER_MEMORY})

  set_target_properties(CMakeTest_options PROPERTIES UNITY_BUILD ${CMakeTest_ENABLE_UNITY_BUILD})

  if(CMakeTest_ENABLE_PCH)
    target_precompile_headers(
      CMakeTest_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(CMakeTest_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    CMakeTest_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(CMakeTest_ENABLE_CLANG_TIDY)
    CMakeTest_enable_clang_tidy(CMakeTest_options ${CMakeTest_WARNINGS_AS_ERRORS})
  endif()

  if(CMakeTest_ENABLE_CPPCHECK)
    CMakeTest_enable_cppcheck(${CMakeTest_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(CMakeTest_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    CMakeTest_enable_coverage(CMakeTest_options)
  endif()

  if(CMakeTest_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(CMakeTest_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(CMakeTest_ENABLE_HARDENING AND NOT CMakeTest_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR CMakeTest_ENABLE_SANITIZER_UNDEFINED
       OR CMakeTest_ENABLE_SANITIZER_ADDRESS
       OR CMakeTest_ENABLE_SANITIZER_THREAD
       OR CMakeTest_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    CMakeTest_enable_hardening(CMakeTest_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()

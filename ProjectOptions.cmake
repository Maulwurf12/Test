include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(Test_supports_sanitizers)
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

macro(Test_setup_options)
  option(Test_ENABLE_HARDENING "Enable hardening" ON)
  option(Test_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    Test_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    Test_ENABLE_HARDENING
    OFF)

  Test_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR Test_PACKAGING_MAINTAINER_MODE)
    option(Test_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(Test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(Test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Test_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(Test_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(Test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Test_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(Test_ENABLE_IPO "Enable IPO/LTO" ON)
    option(Test_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(Test_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(Test_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(Test_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(Test_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(Test_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(Test_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(Test_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(Test_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(Test_ENABLE_PCH "Enable precompiled headers" OFF)
    option(Test_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      Test_ENABLE_IPO
      Test_WARNINGS_AS_ERRORS
      Test_ENABLE_USER_LINKER
      Test_ENABLE_SANITIZER_ADDRESS
      Test_ENABLE_SANITIZER_LEAK
      Test_ENABLE_SANITIZER_UNDEFINED
      Test_ENABLE_SANITIZER_THREAD
      Test_ENABLE_SANITIZER_MEMORY
      Test_ENABLE_UNITY_BUILD
      Test_ENABLE_CLANG_TIDY
      Test_ENABLE_CPPCHECK
      Test_ENABLE_COVERAGE
      Test_ENABLE_PCH
      Test_ENABLE_CACHE)
  endif()

  Test_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (Test_ENABLE_SANITIZER_ADDRESS OR Test_ENABLE_SANITIZER_THREAD OR Test_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(Test_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(Test_global_options)
  if(Test_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    Test_enable_ipo()
  endif()

  Test_supports_sanitizers()

  if(Test_ENABLE_HARDENING AND Test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Test_ENABLE_SANITIZER_UNDEFINED
       OR Test_ENABLE_SANITIZER_ADDRESS
       OR Test_ENABLE_SANITIZER_THREAD
       OR Test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${Test_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${Test_ENABLE_SANITIZER_UNDEFINED}")
    Test_enable_hardening(Test_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(Test_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(Test_warnings INTERFACE)
  add_library(Test_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  Test_set_project_warnings(
    Test_warnings
    ${Test_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(Test_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    Test_configure_linker(Test_options)
  endif()

  include(cmake/Sanitizers.cmake)
  Test_enable_sanitizers(
    Test_options
    ${Test_ENABLE_SANITIZER_ADDRESS}
    ${Test_ENABLE_SANITIZER_LEAK}
    ${Test_ENABLE_SANITIZER_UNDEFINED}
    ${Test_ENABLE_SANITIZER_THREAD}
    ${Test_ENABLE_SANITIZER_MEMORY})

  set_target_properties(Test_options PROPERTIES UNITY_BUILD ${Test_ENABLE_UNITY_BUILD})

  if(Test_ENABLE_PCH)
    target_precompile_headers(
      Test_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(Test_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    Test_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(Test_ENABLE_CLANG_TIDY)
    Test_enable_clang_tidy(Test_options ${Test_WARNINGS_AS_ERRORS})
  endif()

  if(Test_ENABLE_CPPCHECK)
    Test_enable_cppcheck(${Test_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(Test_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    Test_enable_coverage(Test_options)
  endif()

  if(Test_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(Test_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(Test_ENABLE_HARDENING AND NOT Test_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR Test_ENABLE_SANITIZER_UNDEFINED
       OR Test_ENABLE_SANITIZER_ADDRESS
       OR Test_ENABLE_SANITIZER_THREAD
       OR Test_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    Test_enable_hardening(Test_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()

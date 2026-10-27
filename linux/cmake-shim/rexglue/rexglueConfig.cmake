# The package's rexglue config, with the code translator (rexglue.exe) run through Proton on Linux.
set(_ttt2_real "${CMAKE_CURRENT_LIST_DIR}/../../../rex/prebuilt/sdk/lib/cmake/rexglue")
get_filename_component(_ttt2_real "${_ttt2_real}" ABSOLUTE)
include("${_ttt2_real}/rexglueConfig.cmake")
set_target_properties(rex::rexglue PROPERTIES
    IMPORTED_LOCATION_RELEASE "${CMAKE_CURRENT_LIST_DIR}/../../rexglue-wine.sh")

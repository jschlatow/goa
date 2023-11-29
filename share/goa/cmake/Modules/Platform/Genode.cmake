set(CMAKE_FIND_LIBRARY_SUFFIXES ".lib.so")
set(CMAKE_FIND_LIBRARY_PREFIXES "")
set(CMAKE_SHARED_LIBRARY_SUFFIX ".lib.so")
set(CMAKE_SHARED_LIBRARY_RPATH_LINK_C_FLAG "-Wl,-rpath-link,")

# library that contains 'dlopen' and friends
set(CMAKE_DL_LIBS "-l:libc.lib.so")

# force link libgcc to all targets, yet
# since this file is parsed multiple times, we must take care to only
# execute this command once
if (NOT GENODE)
	link_libraries(gcc)
endif()

set(GENODE 1)


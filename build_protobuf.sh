#!/usr/bin/env bash

BUILD_JOBS=2
BUILD_PARALLEL_ARGS=(--parallel "${BUILD_JOBS}")

if [ "$OSTYPE" == "msys" ]; then
    # Visual Studio 2022 using toolkit from Visual Studio 2017
    GENERATOR=("Visual Studio 17 2022")
    GENERATOR_TOOLSET="v142"
    GENERATOR_ARGUMENTS="-A x64 -T ${GENERATOR_TOOLSET}"

    # Visual Studio 2019 using default toolkit
    # GENERATOR=("Visual Studio 16 2019")
    # GENERATOR_ARGUMENTS="-A x64 -T ${GENERATOR_TOOLSET}"

    # Visual Studio 2017 - default toolkit
    # GENERATOR=("Visual Studio 15 2017 Win64")
    # GENERATOR_ARGUMENTS="-T ${GENERATOR_TOOLSET}"
elif [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Unix Makefiles (for Ubuntu and other Linux systems)
    GENERATOR=("Unix Makefiles")
    GENERATOR_ARGUMENTS=""
else
    echo Unknown OSTYPE: $OSTYPE
fi

ROOT_DIR=$(pwd)
rm -rf osi-dependencies
mkdir osi-dependencies
cd osi-dependencies

# build and install zlib
git clone --depth 1 --branch v1.3.1 https://github.com/madler/zlib.git
cd zlib
mkdir build && mkdir install
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    -DCMAKE_INSTALL_PREFIX="install"
cmake --build build --config Release "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --prefix install
cd ..

# build and install abseil
git clone --depth 1 --branch 20240722.1 https://github.com/abseil/abseil-cpp.git
cd abseil-cpp
mkdir build
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
	-DCMAKE_CXX_STANDARD=17 \
	-DABSL_ENABLE_INSTALL=ON \
	-DABSL_BUILD_TESTING=OFF \
	-DABSL_USE_GOOGLETEST_HEAD=OFF \
	-DABSL_MSVC_STATIC_RUNTIME=OFF \
	-DABSL_PROPAGATE_CXX_STD=ON

cmake --build build --config Release "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --prefix dist
cd ..

# build and install protobuf
git clone --depth 1 --branch v29.3 https://github.com/protocolbuffers/protobuf.git
cd protobuf
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B cmake-out \
	-DCMAKE_INSTALL_PREFIX=install \
	-DCMAKE_CXX_STANDARD=17 \
	-DCMAKE_PREFIX_PATH="../abseil-cpp/dist/;../zlib/install" \
	-Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_MSVC_STATIC_RUNTIME=OFF \
	-Dprotobuf_ABSL_PROVIDER="package" \
	-Dprotobuf_BUILD_SHARED_LIBS=OFF

cmake --build cmake-out --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install cmake-out --prefix install
cd $ROOT_DIR

# build and install osi
git clone --branch v3.8.0-rc1 --recurse-submodules https://github.com/OpenSimulationInterface/osi-cpp.git
mkdir osi-cpp-install
cd osi-cpp
mkdir build

PROTO_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/protobuf/install")
ABSL_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/abseil-cpp/dist")
ABSL_LIB_DIR="${ABSL_PATH}/lib"

PROTO_LIB_DIR="${PROTO_PATH}/lib"
ABSL_LIB_DIR="${ABSL_PATH}/lib"

# 2. Collect BOTH Abseil and Protobuf internal libs
# This ensures we grab utf8_range.lib and utf8_validity.lib from the protobuf/install/lib folder
ABSL_LIBS=$(ls "${ABSL_LIB_DIR}"/*.lib | xargs -n 1 basename | tr '\n' ' ')
PROTO_INTERNAL_LIBS=$(ls "${PROTO_LIB_DIR}"/utf8_*.lib | xargs -n 1 basename | tr '\n' ' ')

# 3. Combine them for the standard libraries flag
ALL_EXTRA_LIBS="${ABSL_LIBS} ${PROTO_INTERNAL_LIBS}"

cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    "-DCMAKE_CXX_STANDARD=17" \
    "-DCMAKE_PREFIX_PATH=${PROTO_PATH}" \
    "-DCMAKE_CXX_FLAGS=-I${ABSL_PATH}/include" \
    "-DCMAKE_EXE_LINKER_FLAGS=/LIBPATH:\"${ABSL_LIB_DIR}\" /LIBPATH:\"${PROTO_LIB_DIR}\"" \
    "-DCMAKE_SHARED_LINKER_FLAGS=/LIBPATH:\"${ABSL_LIB_DIR}\" /LIBPATH:\"${PROTO_LIB_DIR}\"" \
    "-DCMAKE_CXX_STANDARD_LIBRARIES=${ALL_EXTRA_LIBS}" \
    "-DOSI_INSTALL_LIB_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/lib")" \
    "-DOSI_INSTALL_INCLUDE_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/include")" \
    "-DOSI_INSTALL_CMAKE_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/cmake")"

cmake --build build --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build

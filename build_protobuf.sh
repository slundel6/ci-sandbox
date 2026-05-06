#!/usr/bin/env bash

set -euo pipefail

BUILD_JOBS=8
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    BUILD_PARALLEL_ARGS=(--parallel "${BUILD_JOBS}")
else
    BUILD_PARALLEL_ARGS=(-j "${BUILD_JOBS}")
fi

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
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
    -DCMAKE_INSTALL_PREFIX="install" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build --config Release "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config Release --prefix install
cd ..

# build and install abseil
git clone --depth 1 --branch 20240722.1 https://github.com/abseil/abseil-cpp.git
cd abseil-cpp
mkdir build
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
	-DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-DABSL_ENABLE_INSTALL=ON \
	-DABSL_BUILD_TESTING=OFF \
	-DABSL_USE_GOOGLETEST_HEAD=OFF \
	-DABSL_MSVC_STATIC_RUNTIME=OFF \
	-DABSL_PROPAGATE_CXX_STD=ON

cmake --build build --config Release "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --prefix install
# cd ..

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    ZLIB_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/zlib/install")
    ABSL_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/abseil-cpp/install")
else
    ZLIB_PATH="${ROOT_DIR}/osi-dependencies/zlib/install"
    ABSL_PATH="${ROOT_DIR}/osi-dependencies/abseil-cpp/install"
fi

# build and install protobuf
git clone --depth 1 --branch v29.3 https://github.com/protocolbuffers/protobuf.git
cd protobuf
# git submodule update --init --recursive
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B cmake-out \
	-DCMAKE_INSTALL_PREFIX=install \
	-DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_MSVC_STATIC_RUNTIME=OFF \
	-Dprotobuf_ABSL_PROVIDER="package" \
	-DCMAKE_PREFIX_PATH="${ZLIB_PATH};${ABSL_PATH}" \
	-Dprotobuf_BUILD_SHARED_LIBS=OFF

cmake --build cmake-out --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install cmake-out --config Release --prefix install
cd $ROOT_DIR
# build and install osi

# git clone --depth 1 --branch main --recurse-submodules https://github.com/slundel6/osi-cpp.git
git clone --branch v3.8.0-rc1 --recurse-submodules https://github.com/OpenSimulationInterface/osi-cpp.git
mkdir osi-cpp-install
cd osi-cpp
mkdir build

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    PROTO_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/protobuf/install")
    OSI_INSTALL_PREFIX=$(cygpath -m "${ROOT_DIR}/osi-cpp-install")
else
    PROTO_PATH="${ROOT_DIR}/osi-dependencies/protobuf/install"
    OSI_INSTALL_PREFIX="${ROOT_DIR}/osi-cpp-install"
fi

cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    "-DCMAKE_CXX_STANDARD=17" \
    "-DCMAKE_BUILD_TYPE=Release" \
    "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON" \
    "-Dprotobuf_MODULE_COMPATIBLE=ON" \
    "-DCMAKE_PREFIX_PATH=${PROTO_PATH}" \
    "-DCMAKE_CXX_FLAGS=-I${ABSL_PATH}/include" \
    "-DCMAKE_INSTALL_PREFIX=${OSI_INSTALL_PREFIX}"

cmake --build build --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config Release
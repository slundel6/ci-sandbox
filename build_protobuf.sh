#!/usr/bin/env bash

BUILD_JOBS=2
BUILD_PARALLEL_ARGS=(--parallel "${BUILD_JOBS}")

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
cmake --install build --prefix install
cd ..

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
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B cmake-out \
	-DCMAKE_INSTALL_PREFIX=install \
	-DCMAKE_CXX_STANDARD=17 \
	-DCMAKE_PREFIX_PATH="${ABSL_PATH};${ZLIB_PATH}" \
	-Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_MSVC_STATIC_RUNTIME=OFF \
	-Dprotobuf_ABSL_PROVIDER="package" \
	-Dprotobuf_BUILD_SHARED_LIBS=OFF

cmake --build cmake-out --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install cmake-out --prefix install
cd $ROOT_DIR

# build and install osi
git clone --depth 1 --branch main --recurse-submodules https://github.com/slundel6/osi-cpp.git
mkdir osi-cpp-install
cd osi-cpp
mkdir build

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    PROTO_PATH=$(cygpath -m "${ROOT_DIR}/osi-dependencies/protobuf/install")
else
    PROTO_PATH="${ROOT_DIR}/osi-dependencies/protobuf/install"
fi

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    OSI_LIB_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/lib")
    OSI_INCLUDE_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/include")
    OSI_CMAKE_DIR=$(cygpath -m "${ROOT_DIR}/osi-cpp-install/cmake")
else
    OSI_LIB_DIR="${ROOT_DIR}/osi-cpp-install/lib"
    OSI_INCLUDE_DIR="${ROOT_DIR}/osi-cpp-install/include"
    OSI_CMAKE_DIR="${ROOT_DIR}/osi-cpp-install/cmake"
fi

cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    "-DCMAKE_CXX_STANDARD=17" \
    "-DCMAKE_BUILD_TYPE=Release" \
    "-DCMAKE_PREFIX_PATH=${PROTO_PATH};${ABSL_PATH};${ZLIB_PATH}" \
    "-DOSI_INSTALL_LIB_DIR=${OSI_LIB_DIR}" \
    "-DOSI_INSTALL_INCLUDE_DIR=${OSI_INCLUDE_DIR}" \
    "-DOSI_INSTALL_CMAKE_DIR=${OSI_CMAKE_DIR}"

cmake --build build --config Release --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config Release

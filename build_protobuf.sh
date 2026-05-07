#!/usr/bin/env bash

set -euo pipefail

BUILD_JOBS=8
BUILD_TYPE=${BUILD_TYPE:-Release}
PROTOBUF_SHARED=${PROTOBUF_SHARED:-OFF}

if [[ "${BUILD_TYPE}" != "Release" && "${BUILD_TYPE}" != "Debug" ]]; then
    echo "Unsupported BUILD_TYPE: ${BUILD_TYPE}. Use Release or Debug."
    exit 1
fi

if [[ "${PROTOBUF_SHARED}" != "ON" && "${PROTOBUF_SHARED}" != "OFF" ]]; then
    echo "Unsupported PROTOBUF_SHARED: ${PROTOBUF_SHARED}. Use ON or OFF."
    exit 1
fi

ABSL_SHARED="${PROTOBUF_SHARED}"
ABSL_WINDOWS_EXPORT_ALL_SYMBOLS_FLAG=()
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]] && [[ "${ABSL_SHARED}" == "ON" ]]; then
    ABSL_WINDOWS_EXPORT_ALL_SYMBOLS_FLAG=(-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON)
fi

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
elif [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Unix Makefiles (for Ubuntu and other Linux systems)
    GENERATOR=("Unix Makefiles")
    GENERATOR_ARGUMENTS=""
else
    echo Unknown OSTYPE: $OSTYPE
fi

ROOT_DIR=$(pwd)
DEPS_INSTALL_FOLDER="${ROOT_DIR}/osi-dependencies/install"

rm -rf osi-dependencies
mkdir -p "${DEPS_INSTALL_FOLDER}"
cd osi-dependencies

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    DEPS_CMAKE_PREFIX=$(cygpath -m "${DEPS_INSTALL_FOLDER}")
else
    DEPS_CMAKE_PREFIX="${DEPS_INSTALL_FOLDER}"
fi

# build and install zlib
git clone --depth 1 --branch v1.3.1 https://github.com/madler/zlib.git
cd zlib
mkdir build
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    -DCMAKE_INSTALL_PREFIX="${DEPS_CMAKE_PREFIX}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

cmake --build build --config "${BUILD_TYPE}" "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config "${BUILD_TYPE}" --prefix "${DEPS_CMAKE_PREFIX}"
cd "${ROOT_DIR}/osi-dependencies"

# build and install abseil
git clone --depth 1 --branch 20240722.1 https://github.com/abseil/abseil-cpp.git
cd abseil-cpp
mkdir build
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
	-DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    "${ABSL_WINDOWS_EXPORT_ALL_SYMBOLS_FLAG[@]}" \
    -DBUILD_SHARED_LIBS="${ABSL_SHARED}" \
	-DABSL_ENABLE_INSTALL=ON \
	-DABSL_BUILD_TESTING=OFF \
	-DABSL_USE_GOOGLETEST_HEAD=OFF \
	-DABSL_MSVC_STATIC_RUNTIME=OFF \
	-DABSL_PROPAGATE_CXX_STD=ON

cmake --build build --config "${BUILD_TYPE}" "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config "${BUILD_TYPE}" --prefix "${DEPS_CMAKE_PREFIX}"
cd "${ROOT_DIR}/osi-dependencies"

# build and install protobuf
git clone --depth 1 --branch v29.3 https://github.com/protocolbuffers/protobuf.git
cd protobuf
cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B cmake-out \
    -DCMAKE_INSTALL_PREFIX="${DEPS_CMAKE_PREFIX}" \
	-DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
	-Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_MSVC_STATIC_RUNTIME=OFF \
	-Dprotobuf_ABSL_PROVIDER="package" \
    -DCMAKE_PREFIX_PATH="${DEPS_CMAKE_PREFIX}" \
    -Dprotobuf_BUILD_SHARED_LIBS="${PROTOBUF_SHARED}"

cmake --build cmake-out --config "${BUILD_TYPE}" --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install cmake-out --config "${BUILD_TYPE}" --prefix "${DEPS_CMAKE_PREFIX}"
cd "${ROOT_DIR}"

# build and install osi
git clone --branch v3.8.0-rc1 --recurse-submodules https://github.com/OpenSimulationInterface/osi-cpp.git
mkdir osi-cpp-install
cd osi-cpp
mkdir build

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    PROTO_CMAKE_DIR=$(cygpath -m "${DEPS_INSTALL_FOLDER}/lib/cmake/protobuf")
    OSI_INSTALL_PREFIX=$(cygpath -m "${ROOT_DIR}/osi-cpp-install")
    ABSL_INCLUDE_PATH=$(cygpath -m "${DEPS_INSTALL_FOLDER}/include")
    OSI_CXX_FLAGS_RELEASE="/EHsc /I${ABSL_INCLUDE_PATH}"
    OSI_CXX_FLAGS_DEBUG="/EHsc /I${ABSL_INCLUDE_PATH}"
    if [[ "${PROTOBUF_SHARED}" == "ON" ]]; then
        OSI_CXX_FLAGS_RELEASE="${OSI_CXX_FLAGS_RELEASE} /DPROTOBUF_USE_DLLS"
        OSI_CXX_FLAGS_DEBUG="${OSI_CXX_FLAGS_DEBUG} /DPROTOBUF_USE_DLLS"
    fi
else
    PROTO_CMAKE_DIR="${DEPS_INSTALL_FOLDER}/lib/cmake/protobuf"
    OSI_INSTALL_PREFIX="${ROOT_DIR}/osi-cpp-install"
    ABSL_INCLUDE_PATH="${DEPS_INSTALL_FOLDER}/include"
    OSI_CXX_FLAGS_RELEASE="-I${ABSL_INCLUDE_PATH}"
    OSI_CXX_FLAGS_DEBUG="-I${ABSL_INCLUDE_PATH}"
fi

cmake -G "${GENERATOR[@]}" ${GENERATOR_ARGUMENTS} -S . -B build \
    "-DCMAKE_CXX_STANDARD=17" \
    "-DCMAKE_BUILD_TYPE=${BUILD_TYPE}" \
    "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON" \
    "-Dprotobuf_MODULE_COMPATIBLE=ON" \
    "-DProtobuf_DIR=${PROTO_CMAKE_DIR}" \
    "-DCMAKE_PREFIX_PATH=${DEPS_CMAKE_PREFIX}" \
    "-DCMAKE_CXX_FLAGS_RELEASE=${OSI_CXX_FLAGS_RELEASE}" \
    "-DCMAKE_CXX_FLAGS_DEBUG=${OSI_CXX_FLAGS_DEBUG}" \
    "-DCMAKE_INSTALL_PREFIX=${OSI_INSTALL_PREFIX}"

cmake --build build --config "${BUILD_TYPE}" --clean-first "${BUILD_PARALLEL_ARGS[@]}"
cmake --install build --config "${BUILD_TYPE}"

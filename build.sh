#!/usr/bin/env bash

# Copyright 2022 Imperial College London
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x
set -e
set -u

WORK="$(pwd)"

help | head

uname

case "$(uname)" in
"Linux")
  NINJA_OS="linux"
  BUILD_PLATFORM="Linux_x64"
  PYTHON="python3"
  # Provided by build.yml.
  export CC="${LINUX_CC}"
  export CXX="${LINUX_CXX}"
  ;;

"Darwin")
  NINJA_OS="mac"
  BUILD_PLATFORM="Mac_x64"
  PYTHON="python3"
  ;;

"MINGW"*|"MSYS_NT"*)
  NINJA_OS="win"
  BUILD_PLATFORM="Windows_x64"
  PYTHON="python"
  CMAKE_OPTIONS+=("-DCMAKE_C_COMPILER=cl.exe" "-DCMAKE_CXX_COMPILER=cl.exe")
  choco install zip
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

COMMIT_ID="$(cat "${WORK}/COMMIT_ID")"

INSTALL_DIR="build-clang-${COMMIT_ID}-${BUILD_PLATFORM}_${CONFIG}"

export PATH="${HOME}/bin:$PATH"

mkdir -p "${HOME}/bin"

pushd "${HOME}/bin"

# Install ninja.
curl -fsSL -o ninja-build.zip "https://github.com/ninja-build/ninja/releases/download/v1.9.0/ninja-${NINJA_OS}.zip"
unzip ninja-build.zip

ls

popd

CMAKE_GENERATOR="Ninja"
CMAKE_BUILD_TYPE="${CONFIG}"
CMAKE_OPTIONS="TODO"

git clone https://github.com/llvm/llvm-project.git
cd llvm-project
git checkout "${COMMIT_ID}"

BUILD_DIR="b_${CONFIG}"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake ../llvm -G "${CMAKE_GENERATOR}" "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" "-DLLVM_ENABLE_PROJECTS='clang'"
cmake --build . --config "${CMAKE_BUILD_TYPE}"
cmake "-DCMAKE_INSTALL_PREFIX=../${INSTALL_DIR}" "-DBUILD_TYPE=${CMAKE_BUILD_TYPE}" -P cmake_install.cmake

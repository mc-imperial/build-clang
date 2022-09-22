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

# Old bash versions can't expand empty arrays, so we always include at least this option.
CMAKE_OPTIONS=("-DCMAKE_OSX_ARCHITECTURES=x86_64")

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

if [ -z ${USE_SANITIZER+x} ]
then
    INSTALL_DIR="${INSTALL_DIR}-${USE_SANITIZER}-Sanitizer"
fi

export PATH="${HOME}/bin:$PATH"

mkdir -p "${HOME}/bin"

pushd "${HOME}/bin"

# Install github-release-retry.
"${PYTHON}" -m pip install --user 'github-release-retry==1.*'

# Install ninja.
curl -fsSL -o ninja-build.zip "https://github.com/ninja-build/ninja/releases/download/v1.9.0/ninja-${NINJA_OS}.zip"
unzip ninja-build.zip

ls

popd

CMAKE_GENERATOR="Ninja"
CMAKE_BUILD_TYPE="${CONFIG}"

git clone https://github.com/llvm/llvm-project.git
cd llvm-project
git checkout "${COMMIT_ID}"

BUILD_DIR="b_${CONFIG}"

CMAKE_OPTIONS+=("-DLLVM_ENABLE_PROJECTS='clang'" "-DLLVM_TARGETS_TO_BUILD=X86")

echo "${USE_SANITIZER}"

if [ -z ${USE_SANITIZER+x} ]
then
    echo "FOUND IT!"
else
    echo "DID NOT FIND IT!"
fi
exit 1


if [ -z ${USE_SANITIZER+x} ]
then
    CMAKE_OPTIONS+=("-DLLVM_USE_SANITIZER=${USE_SANITIZER}")
fi

mkdir -p "${BUILD_DIR}"
pushd "${BUILD_DIR}"
cmake ../llvm -G "${CMAKE_GENERATOR}" "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}" "${CMAKE_OPTIONS[@]}"
cmake --build . --config "${CMAKE_BUILD_TYPE}"
cmake "-DCMAKE_INSTALL_PREFIX=../${INSTALL_DIR}" "-DBUILD_TYPE=${CMAKE_BUILD_TYPE}" -P cmake_install.cmake
popd

# zip file.
pushd "${INSTALL_DIR}"
zip -r "../${INSTALL_DIR}.zip" ./*
popd

# We do not use the GITHUB_TOKEN provided by GitHub Actions.
# We cannot set enviroment variables or secrets that start with GITHUB_ in .yml files,
# but the github-release-retry tool requires GITHUB_TOKEN, so we set it here.
export GITHUB_TOKEN="${GH_TOKEN}"

DESCRIPTION="$(echo -e "Automated build for llvm-project version ${COMMIT_ID}.")"

"${PYTHON}" -m github_release_retry.github_release_retry \
  --user "mc-imperial" \
  --repo "build-clang" \
  --tag_name "github/mc-imperial/build-clang/${COMMIT_ID}" \
  --target_commitish "${GITHUB_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${INSTALL_DIR}.zip"

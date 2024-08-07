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
  sudo apt install -y gcc-multilib libc++-12-dev clang-12
  NINJA_OS="linux"
  BUILD_PLATFORM="${OS}_x64"
  PYTHON="python3"
  df -h
  sudo apt clean
  # shellcheck disable=SC2046
  docker rmi -f $(docker image ls -aq)
  sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc
  df -h

  if [ "${BUILD_WITH_PREBUILT_CLANG}" == 1 ]
  then
    mkdir -p "${HOME}/clang+llvm"
    pushd "${HOME}/clang+llvm"
      # Install pre-built clang.
      curl -fsSL -o clang+llvm.zip "https://github.com/mc-imperial/build-clang/releases/download/bootstrap-llvmorg-14.0.6/build-clang-llvmorg-14.0.6-${BUILD_PLATFORM}_Release.zip"
      unzip clang+llvm.zip
    popd
    export PATH="${HOME}/clang+llvm/bin:$PATH"
  fi
  export CC=clang
  export CXX=clang++
  which "${CC}"
  which "${CXX}"
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
  choco install zip
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

export PATH="${HOME}/bin:$PATH"
mkdir -p "${HOME}/bin"

pushd "${HOME}/bin"

  # Install github-release-retry.
  "${PYTHON}" -m pip install --user 'github-release-retry==1.*'

  # Install ninja.
  curl -fsSL -o ninja-build.zip "https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-${NINJA_OS}.zip"
  unzip ninja-build.zip

  ls

popd

git clone https://github.com/llvm/llvm-project.git
cd llvm-project
COMMIT_ID="$(cat "${WORK}/COMMIT_ID")"
git checkout "${COMMIT_ID}"

INSTALL_DIR="build-clang-${COMMIT_ID}-${BUILD_PLATFORM}_${CONFIG}"

BUILD_DIR="b_${CONFIG}"
mkdir "${BUILD_DIR}"

case "$(uname)" in
"Linux")
  if [ "${BUILD_WITH_PREBUILT_CLANG}" == 0 ]
  then
    INSTALL_DIR="${INSTALL_DIR}-stock-clang"
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" -S llvm -B "${BUILD_DIR}" -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra"
  else
    INSTALL_DIR="${INSTALL_DIR}-prebuilt-clang"
    cmake -G Ninja -C clang/cmake/caches/Fuchsia.cmake -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" -S llvm -B "${BUILD_DIR}"
  fi
  ;;

"Darwin")
  cmake -G Ninja -C clang/cmake/caches/Fuchsia.cmake -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" -S llvm -B "${BUILD_DIR}"
  ;;

"MINGW"*|"MSYS_NT"*)
  cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl.exe -DCMAKE_CXX_COMPILER=cl.exe -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" -S llvm -B "${BUILD_DIR}" -DLLVM_ENABLE_PROJECTS="clang"
  ;;

*)
  echo "Unknown OS"
  exit 1
  ;;
esac

cmake --build "${BUILD_DIR}"
cmake --install "${BUILD_DIR}"

# Remove the build directory to save space.
rm -rf "${BUILD_DIR}"

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
  --tag_name "${COMMIT_ID}" \
  --target_commitish "${GITHUB_SHA}" \
  --body_string "${DESCRIPTION}" \
  "${INSTALL_DIR}.zip"

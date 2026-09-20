#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${repo_root}"

usage() {
  cat <<'EOF'
Install host packages and fetch Blender's pinned build dependencies.

Usage: ./install_deps.sh [--no-system] [--no-update]

  --no-system  Do not install Ubuntu packages.
  --no-update  Do not fetch Git LFS assets or precompiled libraries.

The default performs both steps. Blender 5.2 removed the old PACKAGES_ALL
system-library path, so this script installs the required host tools and uses
Blender's official update helper to fetch lib/linux_x64 and LFS assets.
EOF
}

install_system=true
run_update=true

for arg in "$@"; do
  case "${arg}" in
    --no-system)
      install_system=false
      ;;
    --no-update)
      run_update=false
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${install_system}" == true ]]; then
  if [[ ! -r /etc/os-release ]]; then
    echo "Unable to identify this Linux distribution." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && " ${ID_LIKE:-} " != *" debian "* ]]; then
    echo "This helper supports Ubuntu/Debian hosts, found: ${PRETTY_NAME:-unknown}." >&2
    exit 1
  fi

  python3 build_files/build_environment/install_linux_packages.py --distro-id debian

  apt_packages=(ccache dpkg-dev)
  if apt-cache show gcc-14 >/dev/null 2>&1 && apt-cache show g++-14 >/dev/null 2>&1; then
    apt_packages+=(gcc-14 g++-14)
  else
    echo "GCC 14 packages are unavailable from APT." >&2
    echo "Install GCC 14 or newer before building Blender 5.2." >&2
    exit 1
  fi

  if (( EUID == 0 )); then
    apt-get install -y "${apt_packages[@]}"
  else
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo is required to install ${apt_packages[*]}." >&2
      exit 1
    fi
    sudo apt-get install -y "${apt_packages[@]}"
  fi
fi

if [[ "${run_update}" == true ]]; then
  if ! command -v git-lfs >/dev/null 2>&1; then
    echo "git-lfs is not installed; rerun without --no-system." >&2
    exit 1
  fi
  # Fetch the pinned libraries without moving the user's Blender branch.
  python3 build_files/utils/make_update.py --no-blender
  git lfs pull
fi

case "$(uname -m)" in
  x86_64)
    library_arch="x64"
    ;;
  aarch64 | arm64)
    library_arch="arm64"
    ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

supported_python="$(
  sed -n 's/^set(_PYTHON_VERSION_SUPPORTED[[:space:]]\+\([0-9][0-9.]*\)).*/\1/p' \
    build_files/cmake/Modules/FindPythonLibsUnix.cmake
)"
supported_python="${supported_python// /}"
bundled_python="${repo_root}/lib/linux_${library_arch}/python/bin/python${supported_python}"

if [[ ! -x "${bundled_python}" ]]; then
  echo "Pinned Blender dependencies are incomplete: ${bundled_python} is missing." >&2
  exit 1
fi

"${bundled_python}" - <<'PY'
import numpy
import setuptools
import wheel

print(f"Pinned Python dependencies ready (Python packages: numpy {numpy.__version__}, setuptools {setuptools.__version__})")
PY

if [[ -n "${CONDA_PREFIX:-}" && -x "${CONDA_PREFIX}/bin/python" ]]; then
  conda_python="${CONDA_PREFIX}/bin/python"
  conda_python_version="$(
    "${conda_python}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'
  )"
  if ! "${conda_python}" - "${supported_python}" <<'PY'
import sys

required = tuple(map(int, sys.argv[1].split(".")))
raise SystemExit(sys.version_info[:2] < required)
PY
  then
    echo "Active Conda Python ${conda_python_version} is older than Blender's Python ${supported_python}." >&2
    exit 1
  fi

  if ! "${conda_python}" -c \
    'import cattrs, Cython, MaterialX, numpy, requests, setuptools, wheel, zstandard' >/dev/null 2>&1
  then
    "${conda_python}" -m pip install --only-binary=:all: \
      cattrs cython MaterialX 'numpy>=2.2,<3.0' requests setuptools wheel zstandard
  fi
  "${conda_python}" - <<'PY'
import numpy
import sys

print(f"Conda Python dependencies ready ({sys.executable}, NumPy {numpy.__version__})")
PY
fi

echo "Blender build dependencies are ready."

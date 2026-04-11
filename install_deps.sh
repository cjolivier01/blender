#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mapfile -t blender_packages < <(REPO_ROOT="$repo_root" python3 <<'PY'
import importlib.util
import logging
import os
import types
from pathlib import Path

module_path = Path(os.environ["REPO_ROOT"]) / "build_files/build_environment/install_linux_packages.py"
spec = importlib.util.spec_from_file_location("blender_install_linux_packages", module_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

settings = types.SimpleNamespace(
    distro_id=mod.DISTRO_ID_DEBIAN,
    no_sudo=True,
    logger=logging.getLogger("install_deps"),
)
installer = mod.PackageInstaller(settings)

packages = []
seen = set()


def add_package(name):
    if name in {None, ...}:
        return
    if name in seen:
        return
    seen.add(name)
    packages.append(name)


def collect(packages_to_scan, parent_packages=()):
    for package in packages_to_scan:
        if package.is_group:
            for distro_name in installer.package_distro_name(package, parent_packages):
                add_package(distro_name)
            continue

        distro_name = installer.package_distro_name(package, parent_packages)[0]
        add_package(distro_name)

        if package.sub_packages:
            collect(package.sub_packages, parent_packages + (package,))


collect(mod.PACKAGES_ALL)
print("\n".join(packages))
PY
)

if [[ ${#blender_packages[@]} -eq 0 ]]; then
  echo "Failed to resolve Blender dependency packages." >&2
  exit 1
fi

echo "Updating apt package index..."
sudo apt update

available_packages=()
missing_packages=()

for package in "${blender_packages[@]}"; do
  if apt-cache show "$package" >/dev/null 2>&1; then
    available_packages+=("$package")
  else
    missing_packages+=("$package")
  fi
done

if [[ ${#missing_packages[@]} -gt 0 ]]; then
  echo "Skipping unavailable packages on this apt repository:" >&2
  printf '  %s\n' "${missing_packages[@]}" >&2
fi

if [[ ${#available_packages[@]} -eq 0 ]]; then
  echo "No installable Blender dependencies found in apt repositories." >&2
  exit 1
fi

echo "Installing ${#available_packages[@]} Blender packages (mandatory + optional where available)..."
sudo apt install -y "${available_packages[@]}"

pip install MaterialX


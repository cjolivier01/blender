# SPDX-FileCopyrightText: 2026 Blender Foundation
#
# SPDX-License-Identifier: GPL-2.0-or-later

# RPM packaging enables DESTDIR in packaging.cmake. Using that mode for DEB
# would preserve the build tree's local CMAKE_INSTALL_PREFIX in the package
# instead of using CPACK_PACKAGING_INSTALL_PREFIX.
if(CPACK_GENERATOR STREQUAL "DEB")
  set(CPACK_SET_DESTDIR OFF)
endif()

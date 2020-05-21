{ stdenv, fetchFromGitHub, cmake, rocm-cmake
, libglvnd, libX11, libelf
, roct, rocr, rocm-opencl-src, comgr, clang}:
stdenv.mkDerivation {
  pname = "rocclr";
  version = "20200430";
  src = fetchFromGitHub {
    owner = "ROCm-Developer-Tools";
    repo = "ROCclr";
    rev = "3307d9d94093e836dec9796b9d3182fecf4dcb1d";
    sha256 = "0rhh2qxbyq6n63r182hi9wgq43fc12dqcq0y9cickkw05vhzi26s";
  };
  nativeBuildInputs = [ cmake rocm-cmake ];
  buildInputs = [ libglvnd libX11 roct rocr comgr clang ];
  propagatedBuildInputs = [ libelf ];
  prePatch = ''
    sed 's|FILE "''${CMAKE_CURRENT_BINARY_DIR}/amdvdi_staticTargets.cmake"|FILE "''${CMAKE_INSTALL_PREFIX}/share/cmake/amdvdi_staticTargets.cmake"|g' -i CMakeLists.txt
  '';
  cmakeFlags = [
    "-DOPENCL_DIR=${rocm-opencl-src}"
  ];
  preFixup = ''
    mv $out/include/include/* $out/include
    ln -s $out/include/compiler/lib/include/* $out/include/include
    ln -s $out/include/compiler/lib/include/* $out/include
  '';
}

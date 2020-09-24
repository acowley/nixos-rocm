{stdenv, fetchFromGitHub, lib, config, cmake, pkgconfig, gtest, rocm-cmake, rocm-runtime, hip

# The test suite takes a long time to build
, doCheck ? false
}:
stdenv.mkDerivation rec {
  inherit doCheck;
  name = "rocprim";
  version = "3.8.0";
  src = fetchFromGitHub {
    owner = "ROCmSoftwarePlatform";
    repo = "rocPRIM";
    rev = "rocm-${version}";
    sha256 = "0sfypzcpkknn8m4j3w8wahzgjaa8qir7rxmxywwa3vg7a2a4xmdc";
  };
  nativeBuildInputs = [ cmake rocm-cmake pkgconfig ]
    ++ stdenv.lib.optional doCheck gtest;
  buildInputs = [ rocm-runtime hip ];
  cmakeFlags = [
    "-DCMAKE_CXX_COMPILER=hipcc"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DAMDGPU_TARGETS=${lib.strings.concatStringsSep ";" (config.rocmTargets or ["gfx803" "gfx900" "gfx906"])}"
    "-DBUILD_TEST=${if doCheck then "YES" else "NO"}"
    "${if doCheck then "-DAMDGPU_TEST_TARGETS=${lib.strings.concatStringsSep ";" (config.rocmTargets or ["gfx803" "gfx900" "gfx906"])}" else ""}"
  ];
  patchPhase = ''
    sed -e '/find_package(Git/,/endif()/d' \
        -e '/download_project(/,/^[[:space:]]*)/d' \
        -i cmake/Dependencies.cmake
    #sed 's,include(cmake/VerifyCompiler.cmake),,' -i CMakeLists.txt
  '';
  checkPhase = ''
    ctest
  '';
}

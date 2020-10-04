{stdenv, fetchFromGitHub, cmake, rocm-thunk, rocm-runtime, rocminfo, hip
, python, buildPythonPackage, fetchPypi, ply }:
let
  CppHeaderParser = buildPythonPackage rec {
    pname = "CppHeaderParser";
    version = "2.7.4";

    src = fetchPypi {
      inherit pname version;
      sha256 = "0hncwd9y5ayk8wa6bqhp551mcamcvh84h89ba3labc4mdm0k0arq";
    };

    doCheck = false;
    propagatedBuildInputs = [ ply ];

    meta = with stdenv.lib; {
      homepage = http://senexcanis.com/open-source/cppheaderparser/;
      description = "Parse C++ header files and generate a data structure representing the class";
      license = licenses.bsd3;
      maintainers = [];
    };
  };
  pyenv = python.withPackages (ps: [ CppHeaderParser ]);
in stdenv.mkDerivation rec {
  name = "roctracer";
  version = "3.8.0";
  src = fetchFromGitHub {
    owner = "ROCm-Developer-Tools";
    repo = "roctracer";
    rev = "rocm-${version}";
    sha256 = "1b3bh9skhvkrw4q2hzd0i2yhgmm17y0hvi8plz9vg397yv1za80k";
  };
  src2 = fetchFromGitHub {
    owner = "ROCmSoftwarePlatform";
    repo = "hsa-class";
    rev = "19b1191cf9ff73e72a73e34fdcec142efb43eb77";
    sha256 = "0j35ns2s4b426v6jppchsp6k5xi90xvq6agzz85h5p1qv0fvapl4";
  };
  nativeBuildInputs = [ cmake pyenv ];
  buildInputs = [ rocm-thunk rocm-runtime rocminfo hip ];
  preConfigure = ''
    export HIP_PATH=${hip}
    export HIP_VDI=1
    ln -s ${src2} "test/hsa"
  '';
  patchPhase = ''
    patchShebangs script
    patchShebangs bin
    patchShebangs test
    sed 's|/usr/bin/clang++|clang++|' -i cmake_modules/env.cmake
    sed -e 's|"libhip_hcc.so"|"${hip}/lib/libhip_hcc.so"|' \
        -i src/core/loader.h
  '';
  cmakeFlags = [
    "-DHIP_PATH=${hip}"
    "-DHIP_VDI=1"
  ];
  postFixup = ''
    patchelf --replace-needed libroctracer64.so.1 $out/roctracer/lib/libroctracer64.so.1 $out/roctracer/tool/libtracer_tool.so
    ln -s $out/roctracer/include/* $out/include
  '';

}

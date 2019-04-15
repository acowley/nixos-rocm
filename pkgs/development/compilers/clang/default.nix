{ stdenv, fetchFromGitHub, cmake, python, rocr, rocm-llvm }:
stdenv.mkDerivation rec {
  name = "clang-unwrapped";
  version = "2.3.0";
  src = fetchFromGitHub {
    owner = "RadeonOpenCompute";
    repo = "clang";
    rev = "roc-${version}";
    sha256 = "1frc1r2zw6a89wh7rf2fk7hmklkrsa4ndagw1yldrvpn212i778f";
  };
  nativeBuildInputs = [ cmake python ];
  buildInputs = [ rocm-llvm rocr ];
  hardeningDisable = ["all"];
  cmakeFlags = [
    "-DLLVM_CMAKE_PATH=${rocm-llvm}/lib/cmake/llvm"
    "-DLLVM_MAIN_SRC_DIR=${rocm-llvm.src}"
    "-DCLANG_SOURCE_DIR=${src}"
  ];
  VCSVersion = ''
    #undef LLVM_REVISION
    #undef LLVM_REPOSITORY
    #undef CLANG_REVISION
    #undef CLANG_REPOSITORY
  '';

  # Rather than let cmake extract version information from LLVM or
  # clang source control repositories, we generate the wanted
  # `VCSVersion.inc` file ourselves and remove it from the
  # depencencies of the `clangBasic` target.
  preConfigure = ''
    sed 's/  ''${version_inc}//' -i lib/Basic/CMakeLists.txt
  '';
  postConfigure = ''
    mkdir -p lib/Basic
    echo "$VCSVersion" > lib/Basic/VCSVersion.inc
  '';
}

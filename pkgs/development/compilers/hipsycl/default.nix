{ stdenv, fetchFromGitHub, cmake, python3
, device-libs
, llvm, clang, clang-unwrapped, openmp
, rocr, hip, hipCPU, boost }:
stdenv.mkDerivation rec {
  name = "hipsycl";
  version = "20191217";
  src = fetchFromGitHub {
    owner = "illuhad";
    repo = "hipSYCL";
    rev = "11557a155f576b8cbf504ac8f0151d19b77f54dd";
    sha256 = "0n5qgypyx8qs43y18j1drnanhy7al7namhxn0yzgdws6z7lxsnyz";
  };
  nativeBuildInputs = [ cmake python3 ];
  buildInputs = [ clang openmp hipCPU ];
  cmakeFlags = [
    "-DLLVM_DIR=${llvm}/lib/cmake/llvm"
    "-DCLANG_INCLUDE_PATH=${clang-unwrapped}/lib/clang/10.0.0/include"
    "-DCMAKE_C_COMPILER=${clang}/bin/clang"
    "-DCLANG_EXECUTABLE_PATH=${clang}/bin/clang"
    "-DCMAKE_CXX_COMPILER=${clang}/bin/clang++"
    # ''-DCMAKE_CXX_FLAGS="--hip-device-lib-path=${device-libs}/lib"''
    "-DDISABLE_LLVM_VERSION_CHECK=YES"
    "-DWITH_CUDA_BACKEND=NO"
    "-DWITH_ROCM_BACKEND=YES"
    "-DROCM_PATH=${device-libs}"
  ];
  propagatedBuildInputs = [ hip rocr ];

  prePatch = ''
    patchShebangs bin
    mkdir -p contrib
    ln -s ${hipCPU}/* contrib/hipCPU/
    mkdir -p contrib/HIP/include/
    ln -s ${hip}/include/hip contrib/HIP/include/
  '';
}

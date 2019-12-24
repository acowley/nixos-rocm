{stdenv, fetchFromGitHub, cmake }:
stdenv.mkDerivation {
  name = "hipCPU";
  version = "20190813";
  src = fetchFromGitHub {
    owner = "illuhad";
    repo = "hipCPU";
    rev = "d5b28e3bfc88fbf5aa31a5d4db904f6d9f697522";
    sha256 = "19jcabv6iqb12qa7iiqigiynn4x6wvrr48kws96v2ya5jb7fiaam";
  };
  nativeBuildInputs = [ cmake ];

  patchPhase = ''
    sed "s|DESTINATION include/| DESTINATION $out|g" -i CMakeLists.txt
  '';
}

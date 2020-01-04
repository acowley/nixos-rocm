# This is adapted from the nixpkgs tensorflow wheel-based derivation.
# Usage note: This derivation includes a `setupHook` that sets
# `LD_PRELOAD` to avoid a crash due to conflicting libstdc++
# definitions. To benefit from this hook, add `tensorflow-rocm` to a
# `nix-shell` as its own entity rather than among a list of packages
# in a `withPackages` call. For example:
# `nix-shell -p 'python37.withPackages (ps: [ps.jupyter])' -p tensorflow-rocm`
#
# You can then start `jupyter-notebook` as normal.
{ stdenv
, lib
, fetchurl
, buildPythonPackage
, fetchPypi
, astor
, numpy
, six
, termcolor
, wrapt
, protobuf
, absl-py
, astunparse
, grpcio
, google-pasta
, markdown
, mock
, backports_weakref
, enum34
, werkzeug
, wheel
, tensorflow-tensorboard
, tensorflow-estimator
, zlib
, python, bootstrapped-pip
, symlinkJoin
, keras-applications
, keras-preprocessing
, writeText
, addOpenGLRunpath

# ROCm components
, hcc, hcc-unwrapped
, hip, miopen-hip, miopengemm, rocrand, rocfft, rocblas
, rocr, rccl, cxlactivitylogger
}:
assert python.pythonVersion == "3.7";

# We keep this binary build for two reasons:
# - the source build doesn't work on Darwin.
# - the source build is currently brittle and not easy to maintain

let
  rocmtoolkit_joined = symlinkJoin {
    name = "unsplit_rocmtoolkit";
    paths = [ hcc hcc-unwrapped
              hip miopen-hip miopengemm
              rocrand rocfft rocblas rocr rccl cxlactivitylogger ];
  };

  gast_0_2_2 = buildPythonPackage rec {
    pname = "gast";
    version = "0.2.2";
    src = fetchPypi {
      inherit pname version;
      sha256 = "1w5dzdb3gpcfmd2s0b93d8gff40a1s41rv31458z14inb3s9v4zy";
    };
    propagatedBuildInputs = [ astunparse ];
  };
  tensorboard_1_14_0 = buildPythonPackage rec {
    pname = "tensorflow-tensorboard";
    version = "1.14.0";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/91/2d/2ed263449a078cd9c8a9ba50ebd50123adf1f8cfbea1492f9084169b89d9/tensorboard-1.14.0-py3-none-any.whl";
      sha256 = "1z631614jk5zgasgmwfr33gz8bwv11p9f5llzlwvx3a8rnyv3q2h";
    };
    propagatedBuildInputs = [
      numpy
      werkzeug
      protobuf
      markdown
      grpcio absl-py
      wheel
    ];
  };
  tensorflow-estimator_1_14_0 = buildPythonPackage rec {
    pname = "tensorflow-estimator";
    version = "1.14.0";
    format = "wheel";
    src = fetchurl {
      url = "https://files.pythonhosted.org/packages/3c/d5/21860a5b11caf0678fbc8319341b0ae21a07156911132e0e71bffed0510d/tensorflow_estimator-1.14.0-py2.py3-none-any.whl";
      sha256 = "14irpsyj14vn2dpwr601f54058wywci1pv0hss8s01rl0rk3y1ya";
    };
  };
in buildPythonPackage {
  pname = "tensorflow";
  version = "1.14.5";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/61/1c/f4be8af7b4961e96eb7064c85d6141a55b7b7fd44ec24162529398b0f8c9/tensorflow_rocm-1.14.5-cp37-cp37m-manylinux1_x86_64.whl";
    sha256 = "0zr0dnnc1i3gz6ijf0mzcb7gdc3vd6cyqbm8kw3p6nn8f39x58ss";
  };

  propagatedBuildInputs = [
    protobuf
    numpy
    termcolor
    grpcio
    six
    astor
    absl-py
    gast_0_2_2
    google-pasta
    wrapt
    # tensorflow-estimator
    # tensorflow-tensorboard
    tensorflow-estimator_1_14_0
    tensorboard_1_14_0
    keras-applications
    keras-preprocessing
  ];

  nativeBuildInputs = [ addOpenGLRunpath rocmtoolkit_joined ];

  preInstall = ''
    pushd dist
    echo 'manylinux1_compatible = True' > _manylinux.py
    popd
  '';

  # Upstream has a pip hack that results in bin/tensorboard being in both tensorflow
  # and the propageted input tensorflow-tensorboard which causes environment collisions.
  # another possibility would be to have tensorboard only in the buildInputs
  # https://github.com/tensorflow/tensorflow/blob/v1.7.1/tensorflow/tools/pip_package/setup.py#L79
  postInstall = ''
    rm $out/bin/tensorboard
  '';

  # Note that we need to run *after* the fixup phase because the
  # libraries are loaded at runtime. If we run in preFixup then
  # patchelf --shrink-rpath will remove the cuda libraries.
  postFixup = let
    rpath = stdenv.lib.makeLibraryPath
              [ stdenv.cc.cc.lib zlib rocmtoolkit_joined ];
  in
  lib.optionalString (stdenv.isLinux) ''
    rrPath="$out/${python.sitePackages}/tensorflow/:$out/${python.sitePackages}/tensorflow/contrib/tensor_forest/:${rpath}"
    internalLibPath="$out/${python.sitePackages}/tensorflow/python/_pywrap_tensorflow_internal.so"
    find $out -type f \( -name '*.so' -or -name '*.so.*' \) | while read lib; do
      patchelf --set-rpath "$rrPath" "$lib"
      addOpenGLRunpath "$lib"
    done
  '';

  meta = with stdenv.lib; {
    description = "Computation using data flow graphs for scalable machine learning";
    homepage = http://tensorflow.org;
    license = licenses.asl20;
    maintainers = with maintainers; [ acowley ];
    platforms = with platforms; linux;
  };
}

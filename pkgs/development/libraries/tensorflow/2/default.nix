{ stdenv, pkgs, bazel_3, buildBazelPackage, lib, fetchFromGitHub, fetchpatch, symlinkJoin
, addOpenGLRunpath
# Python deps
, buildPythonPackage, isPy3k, isPy27, pythonOlder, pythonAtLeast, python
# Python libraries
, numpy, tensorflow-tensorboard_2, backports_weakref, mock, enum34, absl-py
, future, setuptools, setuptools_scm, wheel, keras-preprocessing, keras-applications, google-pasta
, functools32, portpicker, typing-extensions
, opt-einsum, astunparse, h5py
, termcolor, grpcio, six, wrapt, protobuf, tensorflow-estimator_2
, flatbuffers-py
# Common deps
, git, swig, which, binutils, glibcLocales, cython
# Common libraries
, jemalloc, openmpi, astor, gast, grpc, sqlite, openssl, jsoncpp, re2
, curl, snappy, flatbuffers, icu, double-conversion, libpng, libjpeg, giflib
# Upsteam by default includes cuda support since tensorflow 1.15. We could do
# that in nix as well. It would make some things easier and less confusing, but
# it would also make the default tensorflow package unfree. See
# https://groups.google.com/a/tensorflow.org/forum/#!topic/developers/iRCt5m4qUz0
, cudaSupport ? false, cudatoolkit ? null, cudnn ? null, nccl ? null
# ROCm deps
, rocmSupport ? false, config ? null, runCommand ? null, lndir ? null
, clang ? null, lld ? null
, rocm-runtime ? null, rccl ? null
, hip ? null, rocprim ? null, hipcub ? null, rocsparse ? null, hipsparse ? null, rocblas ? null
, miopengemm ? null, miopen-hip ? null, rocrand ? null, rocfft ? null, roctracer ? null
# MKL Support
, mklSupport ? false, mkl ? null
# XLA without CUDA is broken
, xlaSupport ? (cudaSupport || rocmSupport)
# Default from ./configure script
, cudaCapabilities ? [ "3.5" "5.2" ]
, sse42Support ? stdenv.hostPlatform.sse4_2Support
, avx2Support  ? stdenv.hostPlatform.avx2Support
, fmaSupport   ? stdenv.hostPlatform.fmaSupport
# Darwin deps
, Foundation ? null, Security ? null
}:

assert ! (cudaSupport && rocmSupport);

assert cudaSupport -> cudatoolkit != null
                   && cudnn != null;
                   
assert rocmSupport -> config != null
                   && runCommand != null
                   && lndir != null
                   && clang != null
                   && lld != null
                   && rocm-runtime != null
                   && rccl != null
                   && hip != null
                   && rocprim != null
                   && hipcub != null
                   && rocsparse != null
                   && hipsparse != null
                   && rocblas != null
                   && miopengemm != null
                   && miopen-hip != null
                   && rocrand != null
                   && rocfft != null
                   && roctracer != null;

# unsupported combination
assert ! (stdenv.isDarwin && cudaSupport);

assert ! (stdenv.isDarwin && rocmSupport);

assert stdenv.isDarwin -> Foundation != null
                       && Security != null;

assert mklSupport -> mkl != null;

let
  withTensorboard = pythonOlder "3.6";

  cudatoolkit_joined = if cudaSupport then (symlinkJoin {
    name = "${cudatoolkit.name}-merged";
    paths = [
      cudatoolkit.lib
      cudatoolkit.out
    ] ++ lib.optionals (lib.versionOlder cudatoolkit.version "11") [
      # for some reason some of the required libs are in the targets/x86_64-linux
      # directory; not sure why but this works around it
      "${cudatoolkit}/targets/${stdenv.system}"
    ];
  }) else {};

  cudatoolkit_cc_joined = if cudaSupport then (symlinkJoin {
    name = "${cudatoolkit.cc.name}-merged";
    paths = [
      cudatoolkit.cc
      binutils.bintools # for ar, dwp, nm, objcopy, objdump, strip
    ];
  }) else {};

  rocmtoolkit_joined = if rocmSupport then runCommand "unsplit_rocmtoolkit" {} ''
    mkdir -p $out
    ln -s ${clang} $out/clang
    ln -s ${lld} $out/lld
    ln -s ${hip} $out/hip
    ln -s ${hipsparse} $out/hipsparse
    ln -s ${rocrand}/hiprand $out/hiprand
    ln -s ${rocrand}/rocrand $out/rocrand
    ln -s ${rocfft} $out/rocfft
    ln -s ${rocblas} $out/rocblas
    ln -s ${miopen-hip} $out/miopen
    ln -s ${miopengemm} $out/miopengemm
    ln -s ${rccl} $out/rccl
    ln -s ${hipcub} $out/hipcub
    ln -s ${rocprim} $out/rocprim
    ln -s ${rocm-runtime} $out/hsa
    ln -s ${roctracer} $out/roctracer
    for i in ${clang} ${lld} ${hip} ${hipsparse} ${rocrand}/hiprand ${rocrand}/rocrand ${rocfft} ${rocblas} ${miopen-hip} ${miopengemm} ${rccl} ${hipcub} ${rocprim} ${rocm-runtime} ${roctracer} ${binutils.bintools}; do
      ${lndir}/bin/lndir -silent $i $out
    done
    ln -s ${rocrand}/hiprand/include $out/include/hiprand
    mkdir $out/.info
    echo ${rocm-runtime.version} > $out/.info/version-dev
  '' else {};

  # Needed for _some_ system libraries, grep INCLUDEDIR.
  includes_joined = symlinkJoin {
    name = "tensorflow-deps-merged";
    paths = [
      pkgs.protobuf
      jsoncpp
    ];
  };

  tfFeature = x: if x then "1" else "0";

  version = "1e62e70e55dfbe2fdbca76cbf020c5b4c3732ade";
  variant = if (cudaSupport || rocmSupport) then (if cudaSupport then "-gpu" else "-rocm") else "";
  pname = "tensorflow${variant}";

  pythonEnv = python.withPackages (_:
    [ # python deps needed during wheel build time (not runtime, see the buildPythonPackage part for that)
      numpy
      keras-preprocessing
      protobuf
      portpicker
      wrapt
      gast
      astor
      absl-py
      termcolor
      keras-applications
      setuptools
      setuptools_scm
      wheel
  ] ++ lib.optionals (!isPy3k)
  [ future
    functools32
    mock
  ]);

  bazel-build = buildBazelPackage {
    name = "${pname}-${version}";
    bazel = bazel_3;

    src = fetchFromGitHub {
      owner = "ROCmSoftwarePlatform";
      repo = "tensorflow-upstream";
      #rev = "v${version}";
      rev = version;
      sha256 = "0z3v3m0sx1kdwy1bynxgcwpsvg7r4yjxj27xhy9cfc7s02wdbbd8";
    };

    patches = [
      # Fixes for NixOS jsoncpp
      #../system-jsoncpp.patch

      ./lift-gast-restriction.patch

      # see https://github.com/tensorflow/tensorflow/issues/40688
      #(fetchpatch {
      #  url = "https://github.com/tensorflow/tensorflow/commit/75ea0b31477d6ba9e990e296bbbd8ca4e7eebadf.patch";
      #  sha256 = "1xp1icacig0xm0nmb05sbrf4nw4xbln9fhc308birrv8286zx7wv";
      #})

      # see https://github.com/tensorflow/tensorflow/issues/40884
      #(fetchpatch {
      #  url = "https://github.com/tensorflow/tensorflow/pull/41867/commits/65341f73d110bf173325768947343e1bb8f699fc.patch";
      #  sha256 = "18ykkycaag1pcarz53bz6ydxjlah92j4178qn58gcayx1fy7hvh3";
      #})
    ] ++ lib.optionals rocmSupport [
      ./add-docker-rules.patch
      ./rocm-create-sed-target.patch
    ];

    # On update, it can be useful to steal the changes from gentoo
    # https://gitweb.gentoo.org/repo/gentoo.git/tree/sci-libs/tensorflow

    nativeBuildInputs = [
      swig which pythonEnv
    ] ++ lib.optional (cudaSupport || rocmSupport) addOpenGLRunpath;

    buildInputs = [
      jemalloc
      openmpi
      glibcLocales
      git

      # libs taken from system through the TF_SYS_LIBS mechanism
      grpc
      sqlite
      openssl
      jsoncpp
      pkgs.protobuf
      curl
      snappy
      flatbuffers
      icu
      double-conversion
      libpng
      libjpeg
      giflib
      re2
      pkgs.lmdb
    ] ++ lib.optionals cudaSupport [
      cudatoolkit
      cudnn
    ] ++ lib.optionals rocmSupport [
      rocmtoolkit_joined
    ] ++ lib.optionals mklSupport [
      mkl
    ] ++ lib.optionals stdenv.isDarwin [
      Foundation
      Security
    ];

    # arbitrarily set to the current latest bazel version, overly careful
    TF_IGNORE_MAX_BAZEL_VERSION = true;

    # Take as many libraries from the system as possible. Keep in sync with
    # list of valid syslibs in
    # https://github.com/tensorflow/tensorflow/blob/master/third_party/systemlibs/syslibs_configure.bzl
    TF_SYSTEM_LIBS = lib.concatStringsSep "," [
      "absl_py"
      "astor_archive"
      "astunparse_archive"
      "boringssl"
      # Not packaged in nixpkgs
      # "com_github_googleapis_googleapis"
      # "com_github_googlecloudplatform_google_cloud_cpp"
      "com_github_grpc_grpc"
      "com_google_protobuf"
      "com_googlesource_code_re2"
      "curl"
      "cython"
      "double_conversion"
      "enum34_archive"
      "flatbuffers"
      "functools32_archive"
      "gast_archive"
      "gif"
      "hwloc"
      "icu"
      "jsoncpp_git"
      "libjpeg_turbo"
      "lmdb"
      "nasm"
      # "nsync" # not packaged in nixpkgs
      "opt_einsum_archive"
      "org_sqlite"
      "pasta"
      "pcre"
      "png"
      "pybind11"
      "six_archive"
      "snappy"
      #"swig"
      "termcolor_archive"
      "wrapt"
      "zlib"
    ];

    INCLUDEDIR = "${includes_joined}/include";

    PYTHON_BIN_PATH = pythonEnv.interpreter;

    TF_NEED_GCP = true;
    TF_NEED_HDFS = true;
    TF_ENABLE_XLA = tfFeature xlaSupport;

    CC_OPT_FLAGS = " ";

    # https://github.com/tensorflow/tensorflow/issues/14454
    # This has been fixed.
    #TF_NEED_MPI = tfFeature cudaSupport;

    TF_NEED_CUDA = tfFeature cudaSupport;
    TF_CUDA_PATHS = lib.optionalString cudaSupport "${cudatoolkit_joined},${cudnn},${nccl}";
    #GCC_HOST_COMPILER_PREFIX = lib.optionalString cudaSupport "${cudatoolkit_cc_joined}/bin";
    GCC_HOST_COMPILER_PATH = lib.optionalString cudaSupport "${cudatoolkit_cc_joined}/bin/gcc";
    TF_CUDA_COMPUTE_CAPABILITIES = lib.optionalString cudaSupport (lib.concatStringsSep "," cudaCapabilities);

    TF_NEED_ROCM = tfFeature rocmSupport;
    ROCM_PATH = lib.optionalString rocmSupport "${rocmtoolkit_joined}";
    TF_ROCM_VERSION = lib.optionalString rocmSupport "3.8.0";
    #TF_MIOPEN_VERSION = "${miopen.version}";
    ROCM_TOOLKIT_PATH = lib.optionalString rocmSupport "${rocmtoolkit_joined}";
    TF_ROCM_AMDGPU_TARGETS = lib.optionalString rocmSupport "${lib.strings.concatStringsSep "," (config.rocmTargets or ["gfx803" "gfx900" "gfx906"])}";
    
    GCC_HOST_COMPILER_PREFIX = lib.optionalString (cudaSupport || rocmSupport) (if cudaSupport then "${cudatoolkit_cc_joined}/bin" else "${rocmtoolkit_joined}/bin");

    postPatch = ''
      # Tensorboard pulls in a bunch of dependencies, some of which may
      # include security vulnerabilities. So we make it optional.
      # https://github.com/tensorflow/tensorflow/issues/20280#issuecomment-400230560
      sed -i '/tensorboard >=/d' tensorflow/tools/pip_package/setup.py

      # numpy 1.19 added in https://github.com/tensorflow/tensorflow/commit/75ea0b31477d6ba9e990e296bbbd8ca4e7eebadf.patch
      sed -i 's/numpy >= 1.16.0, < 1.19.0/numpy >= 1.16.0/' tensorflow/tools/pip_package/setup.py

      # bazel 3.3 should work just as well as bazel 3.1
      rm -f .bazelversion
    '' + lib.optionalString rocmSupport ''
      # The following takes all symlinks in the unsplit_rocmtoolkit directory and includes them in the Bazel build. The second part of this printf is needed
      # due to the failure to pick up the resource-root directory in clang-wrapped, since that is a symlink and the first part of the printf follows it. 
      printf -v allpossibledirs '%s\n' "$(dirname $(find -L ${rocmtoolkit_joined} -type f,l -exec realpath {} \;))" "$(find -L /nix/store -wholename '${clang}*' -type d)"
      sed -e "s|nixos sed target|[ \"$(echo "$allpossibledirs" | sort -u | sed ':a;N;$!ba;s/\n/", "/g')\" ]|" -i ./third_party/gpus/rocm_configure.bzl
    '';

    preConfigure = let
      opt_flags = []
        ++ lib.optionals sse42Support ["-msse4.2"]
        ++ lib.optionals avx2Support ["-mavx2"]
        ++ lib.optionals fmaSupport ["-mfma"];
    in ''
      patchShebangs configure

      # dummy ldconfig
      mkdir dummy-ldconfig
      echo "#!${stdenv.shell}" > dummy-ldconfig/ldconfig
      chmod +x dummy-ldconfig/ldconfig
      export PATH="$PWD/dummy-ldconfig:$PATH"

      export PYTHON_LIB_PATH="$NIX_BUILD_TOP/site-packages"
      export CC_OPT_FLAGS="${lib.concatStringsSep " " opt_flags}"
      mkdir -p "$PYTHON_LIB_PATH"

      # To avoid mixing Python 2 and Python 3
      unset PYTHONPATH
    '';

    configurePhase = ''
      runHook preConfigure
      ./configure
      runHook postConfigure
    '';

    hardeningDisable = [ "format" ];

    bazelBuildFlags = [
      "--config=opt" # optimize using the flags set in the configure phase
    ] ++ lib.optionals rocmSupport [
      "--config=rocm"
    ] ++ lib.optionals mklSupport [ 
      "--config=mkl" 
    ];

    bazelTarget = "//tensorflow/tools/pip_package:build_pip_package //tensorflow/tools/lib_package:libtensorflow";

    removeRulesCC = false;

    fetchAttrs = {
      # So that checksums don't depend on these.
      TF_SYSTEM_LIBS = null;

      # cudaSupport causes fetch of ncclArchive, resulting in different hashes
      sha256 = if (cudaSupport || rocmSupport) then if cudaSupport then
        "0pf8128chkm6fxnhd4956n6gvijlj00mjmvry33gq3xx3bayhs9g"
      else # rocmSupport 
        "1bgk434sggmrry2n24r2b64hd1swsavchl9dr18ydygryqnm04ds"
      else
        "0mkgss2nyk21zlj8hp24cs3dmpdnxk8qi6qq4hyc18lp82p09xwa";
    };

    buildAttrs = {
      outputs = [ "out" "python" ];

      preBuild = ''
        patchShebangs .
      '';

      installPhase = ''
        mkdir -p "$out"
        tar -xf bazel-bin/tensorflow/tools/lib_package/libtensorflow.tar.gz -C "$out"
        # Write pkgconfig file.
        mkdir "$out/lib/pkgconfig"
        cat > "$out/lib/pkgconfig/tensorflow.pc" << EOF
        Name: TensorFlow
        Version: ${version}
        Description: Library for computation using data flow graphs for scalable machine learning
        Requires:
        Libs: -L$out/lib -ltensorflow
        Cflags: -I$out/include/tensorflow
        EOF

        # build the source code, then copy it to $python (build_pip_package
        # actually builds a symlink farm so we must dereference them).
        bazel-bin/tensorflow/tools/pip_package/build_pip_package --src "$PWD/dist"
        cp -Lr "$PWD/dist" "$python"
      '';

      postFixup = lib.optionalString (cudaSupport || rocmSupport) ''
        find $out -type f \( -name '*.so' -or -name '*.so.*' \) | while read lib; do
          addOpenGLRunpath "$lib"
        done
      '';
    };

    meta = with stdenv.lib; {
      description = "Computation using data flow graphs for scalable machine learning";
      homepage = "http://tensorflow.org";
      license = licenses.asl20;
      maintainers = with maintainers; [ jyp abbradar wulfsta ];
      platforms = with platforms; linux ++ darwin;
      # The py2 build fails due to some issue importing protobuf. Possibly related to the fix in
      # https://github.com/akesandgren/easybuild-easyblocks/commit/1f2e517ddfd1b00a342c6abb55aef3fd93671a2b
      broken = !(xlaSupport -> (cudaSupport || rocmSupport)) || !isPy3k;
    };
  };

in buildPythonPackage {
  inherit version pname;
  disabled = isPy27;

  src = bazel-build.python;

  # Upstream has a pip hack that results in bin/tensorboard being in both tensorflow
  # and the propagated input tensorflow-tensorboard, which causes environment collisions.
  # Another possibility would be to have tensorboard only in the buildInputs
  # https://github.com/tensorflow/tensorflow/blob/v1.7.1/tensorflow/tools/pip_package/setup.py#L79
  postInstall = ''
    rm $out/bin/tensorboard
  '';

  setupPyGlobalFlags = [ "--project_name ${pname}" ];

  # tensorflow/tools/pip_package/setup.py
  propagatedBuildInputs = [
    absl-py
    astor
    gast
    google-pasta
    keras-applications
    keras-preprocessing
    numpy
    six
    protobuf
    portpicker
    typing-extensions
    flatbuffers-py
    tensorflow-estimator_2
    termcolor
    wrapt
    grpcio
    opt-einsum
    astunparse
    h5py
  ] ++ lib.optionals (!isPy3k) [
    mock
    future
    functools32
  ] ++ lib.optionals (pythonOlder "3.4") [
    backports_weakref enum34
  ] ++ lib.optionals withTensorboard [
    tensorflow-tensorboard_2
  ];

  nativeBuildInputs = [ setuptools setuptools_scm ] ++ lib.optionals (cudaSupport || rocmSupport) [ addOpenGLRunpath ];

  postFixup = lib.optionalString (cudaSupport || rocmSupport) ''
    find $out -type f \( -name '*.so' -or -name '*.so.*' \) | while read lib; do
      addOpenGLRunpath "$lib"
  '' + lib.optionalString (cudaSupport) ''
      patchelf --set-rpath "${cudatoolkit}/lib:${cudatoolkit.lib}/lib:${cudnn}/lib:${nccl}/lib:$(patchelf --print-rpath "$lib")" "$lib"
  '' + lib.optionalString (cudaSupport || rocmSupport) ''
    done
  '';

  # Actual tests are slow and impure.
  # TODO try to run them anyway
  # TODO better test (files in tensorflow/tools/ci_build/builds/*test)
  checkPhase = ''
    ${python.interpreter} <<EOF
    # A simple "Hello world"
    import tensorflow as tf
    hello = tf.constant("Hello, world!")
    tf.print(hello)

    # Fit a simple model to random data
    import numpy as np
    np.random.seed(0)
    tf.random.set_seed(0)
    model = tf.keras.models.Sequential([
        tf.keras.layers.Dense(1, activation="linear")
    ])
    model.compile(optimizer="sgd", loss="mse")

    x = np.random.uniform(size=(1,1))
    y = np.random.uniform(size=(1,))
    model.fit(x, y, epochs=1)
    EOF
  '';
  # Regression test for #77626 removed because not more `tensorflow.contrib`.

  passthru = {
    deps = bazel-build.deps;
    libtensorflow = bazel-build.out;
  };

  inherit (bazel-build) meta;
}

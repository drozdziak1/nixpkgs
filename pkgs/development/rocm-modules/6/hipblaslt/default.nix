{lib,
  stdenv,
  fetchFromGitHub,
  rocmUpdateScript,
  clang-unwrapped,
  cmake,
  rocm-cmake,
  clr,
  gfortran,
  rocblas,
  rocsolver,
  gtest,
  hipblas,
  msgpack,

  git,
  python3,
  python3Packages,
  
  lapack-reference,
  # tensile,
  buildTests ? false,
  buildBenchmarks ? false,
  buildSamples ? false,

  buildTensile ? false,
  tensileLogic ? "asm_full",
  tensileCOVersion ? "V3",
  # https://github.com/ROCm/Tensile/issues/1757
  # Allows gfx101* users to use rocBLAS normally.
  # Turn the below two values to `true` after the fix has been cherry-picked
  # into a release. Just backporting that single fix is not enough because it
  # depends on some previous commits.
  tensileSepArch ? false,
  tensileLazyLib ? false,
  tensileLibFormat ? "msgpack",
  gpuTargets ? [],
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "hipblaslt";
  version = "6.0.2";

  outputs = ["out"]
            ++ lib.optionals buildTests [
              "test"
            ]
            ++ lib.optionals buildBenchmarks [
              "benchmark"
            ]
            ++ lib.optionals buildBenchmarks [
              "sample"
            ];

  src = fetchFromGitHub {
    owner = "ROCm";
    repo = "hipBLASLt";
    rev = "rocm-${finalAttrs.version}";
    hash = "sha256-ZXiq5e6C7MU0nTpill/jCsjt1y3vwdt2xrrqCA6cCtw=";
  };

  nativeBuildInputs = [
    cmake
    rocm-cmake
    clr
    gfortran
  ];

  buildInputs =
    [
      rocblas
      rocsolver
      hipblas

      git
      msgpack
      (python3.withPackages (ps: [ps.joblib ps.pyyaml]))
    ]
    ++ lib.optionals buildTests [
      gtest
    ]
    ++ lib.optionals (buildTests || buildBenchmarks) [
      lapack-reference
    ];
  cmakeFlags =
    [
      "-DCMAKE_C_COMPILER=${clr}/bin/hipcc"
      "-DCMAKE_CXX_COMPILER=${clr}/bin/hipcc"
      # Manually define CMAKE_INSTALL_<DIR>
      # See: https://github.com/NixOS/nixpkgs/pull/197838
      "-DCMAKE_INSTALL_BINDIR=bin"
      "-DCMAKE_INSTALL_LIBDIR=lib"
      "-DCMAKE_INSTALL_INCLUDEDIR=include"
      (lib.cmakeFeature "AMDGPU_TARGETS" (lib.concatStringsSep ";" gpuTargets))
      (lib.cmakeFeature "ROCM_PATH" "${clr}")
    ]
    ++ lib.optionals buildTests [
      "-DBUILD_CLIENTS_TESTS=ON"
    ]
    ++ lib.optionals buildBenchmarks [
      "-DBUILD_CLIENTS_BENCHMARKS=ON"
    ]
    ++ lib.optionals buildSamples [
      "-DBUILD_CLIENTS_SAMPLES=ON"
    ]
    ++ lib.optionals buildTensile [
      # (lib.cmakeFeature "Tensile_COMPILER" "${clr}/bin/hipcc")
      (lib.cmakeFeature "Tensile_LOGIC" tensileLogic)
      (lib.cmakeFeature "Tensile_CODE_OBJECT_VERSION" tensileCOVersion)
      (lib.cmakeBool "Tensile_SEPARATE_ARCHITECTURES" tensileSepArch)
      (lib.cmakeBool "Tensile_LAZY_LIBRARY_LOADING" tensileLazyLib)
      (lib.cmakeFeature "Tensile_LIBRARY_FORMAT" tensileLibFormat)
      (lib.cmakeBool "Tensile_PRINT_DEBUG" true)
    ];
  patchPhase = ''
      sed -i 's:toolchain=.*:toolchain=${clang-unwrapped}/bin/clang++:g' tensilelite/Tensile/Ops/gen_assembly.sh
  '';
  
  postInstall =
    lib.optionalString buildTests ''
      mkdir -p $test/bin
      mv $out/bin/hipblaslt-test $test/bin
    ''
    +
    lib.optionalString buildBenchmarks ''
      mkdir -p $benchmark/bin
      mv $out/bin/hipblaslt-bench $benchmark/bin
    ''
    + lib.optionalString buildSamples ''
      mkdir -p $sample/bin
      mv $out/bin/example-* $sample/bin
    ''
    + lib.optionalString (buildTests || buildBenchmarks || buildSamples) ''
      rmdir $out/bin
    '';

  passthru.updateScript = rocmUpdateScript {
    name = finalAttrs.pname;
    owner = finalAttrs.src.owner;
    repo = finalAttrs.src.repo;
  };

  meta = with lib; {
    description = "hipBLASLt is a library that provides general matrix-matrix operations with a flexible API and extends functionalities beyond a traditional BLAS library";
    homepage = "https://github.com/ROCm/hipBLASLt";
    license = with licenses; [ mit ];
    maintainers = teams.rocm.members;
    platforms = platforms.linux;
    broken =
      versions.minor finalAttrs.version != versions.minor stdenv.cc.version
      || versionAtLeast finalAttrs.version "7.0.0";
  };
})

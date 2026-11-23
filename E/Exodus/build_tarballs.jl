# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg
const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "macos_sdks.jl"))
# include(joinpath(YGGDRASIL_DIR, "platforms", "mpi.jl"))

name = "Exodus"
version = v"9.6.0"

# Collection of sources required to complete build
sources = [
    GitSource("https://github.com/sandialabs/seacas", "86638545f4f7a616ecfb10016865a18373c87611"),
    DirectorySource("bundled")
]

# Bash recipe for building across all platforms
script = raw"""
# export MPITRAMPOLINE_CC="${CC}"
# export MPITRAMPOLINE_CXX="${CXX}"
# export MPITRAMPOLINE_FC="${FC}"

# below needed to use CMake_jll
apk del cmake

cd $WORKSPACE/srcdir/seacas

for p in ../patches/*.patch; do
    atomic_patch -p1 "${p}"
done

mkdir build
cd build

cmake \
    -D CMAKE_INSTALL_PREFIX=${prefix} \
    -D CMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -D CMAKE_BUILD_TYPE=Release \
    \
    -D Seacas_ENABLE_STRONG_C_COMPILE_WARNINGS="" \
    -D Seacas_ENABLE_STRONG_CXX_COMPILE_WARNINGS="" \
    -D CMAKE_INSTALL_RPATH:PATH="${libdir}" \
    -D BUILD_SHARED_LIBS:BOOL=YES \
    -D Seacas_ENABLE_SEACASExodus=YES \
    -D Seacas_ENABLE_SEACASExodus_cpp=YES \
    -D Seacas_ENABLE_SEACASExodus_for=NO \
    -D Seacas_ENABLE_SEACASExoIIv2for32=NO \
    -D Seacas_ENABLE_TESTS=NO \
    -D SEACASExodus_ENABLE_STATIC:BOOL=NO \
    -D Seacas_SKIP_FORTRANCINTERFACE_VERIFY_TEST:BOOL=YES \
    -D Seacas_HIDE_DEPRECATED_CODE:BOOL=NO \
    -D Seacas_ENABLE_Fortran=NO \
    \
    -D Seacas_ENABLE_SEACASEjoin::BOOL=OFF \
    -D Seacas_ENABLE_SEACASEpu:BOOL=ON \
    -D Seacas_ENABLE_SEACASExodiff:BOOL=ON \
    -D Seacas_ENABLE_SEACASIoss:BOOL=OFF \
    -D Seacas_ENABLE_SEACASNemslice:BOOL=ON \
    -D Seacas_ENABLE_SEACASNemspread:BOOL=ON \
    -D Seacas_ENABLE_SEACASSkinner:BOOL=OFF \
    -D Seacas_ENABLE_Zoltan:BOOL=OFF \
    \
    -D TPL_ENABLE_Netcdf:BOOL=YES \
    -D TPL_ENABLE_MPI:BOOL=NO \
    -D TPL_ENABLE_Pthread:BOOL=NO \
    -D SEACASExodus_ENABLE_THREADSAFE:BOOL=NO \
    \
    -D NetCDF_ROOT:PATH=${prefix} \
    -D HDF5_ROOT:PATH=${prefix} \
    -D HDF5_NO_SYSTEM_PATHS=YES \
    -D PNetCDF_ROOT:PATH=${prefix} \
    \
    ..

make -j${nproc}
make install

# below is an absolute hack to fix a tree hash mismatch on macos
# this is due to a case insensitivity issue. 
#
# The issue is caused by a duplicate folder in destdir/lib/cmake
# called "Seacas" which is a duplibcate of "SEACAS".
#
# The build process has far too many CMake files to track this down.
#
rm -r "${prefix}/lib/cmake/Seacas"
"""

sources, script = require_macos_sdk("14.0", sources, script)

# augment_platform_block = """
# using Base.BinaryPlatforms
# $(MPI.augment)
# augment_platform!(platform::Platform) = augment_mpi!(platform)
# """

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [
    Platform("x86_64", "linux"; libc = "glibc"),
    Platform("aarch64", "linux"; libc = "glibc"),
    Platform("x86_64", "macos"),
    Platform("aarch64","macos"),
    Platform("x86_64", "windows"),
    Platform("i686", "windows"),
]

platforms = expand_cxxstring_abis(platforms)
# platforms, platform_dependencies = MPI.augment_platforms(platforms)

# The products that we will ensure are always built
products = [
    LibraryProduct("libexodus", :libexodus)
    ExecutableProduct("epu", :epu_exe)
    ExecutableProduct("exodiff", :exodiff_exe)
    ExecutableProduct("nem_slice", :nem_slice_exe)
    ExecutableProduct("nem_spread", :nem_spread_exe)
    # ExecutableProduct("skinner", :skinner_exe)
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency(PackageSpec(name="Fmt_jll", uuid="5dc1e892-f187-50dd-85f3-7dff85c47fc5"))
    Dependency(PackageSpec(name="HDF5_jll", uuid="0234f1f7-429e-5d53-9886-15a909be8d59"))
    Dependency(PackageSpec(name="NetCDF_jll", uuid="7243133f-43d8-5620-bbf4-c2c921802cf3"))
    Dependency(PackageSpec(name="Zlib_jll", uuid="83775a58-1f1d-513f-b197-d71354ab007a"))
    HostBuildDependency(PackageSpec(name="CMake_jll", uuid="3f4e10e2-61f2-5801-8945-23b9d642d0e6"))
]
# append!(dependencies, platform_dependencies)

# Don't look for `mpiwrapper.so` when BinaryBuilder examines and `dlopen`s the shared libraries.
# (MPItrampoline will skip its automatic initialization.)
# ENV["MPITRAMPOLINE_DELAY_INIT"] = "1"

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(
    ARGS, name, version, sources, script, platforms, products, dependencies;
    # augment_platform_block,
    julia_compat="1.6", preferred_gcc_version=v"9"
)

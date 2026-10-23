# Clang 22 for Mavericks

Clang/LLVM toolchain for Mac OS X 10.9 Mavericks.

## Compiling

### Directly on Mavericks

```sh
sudo installer -pkg mavericks-clang-22-native-<version>.pkg -target /
```

In a new Terminal:

```sh
clang++-22 -o hello hello.cpp
./hello
```

### From Apple Silicon

```sh
sudo installer -pkg mavericks-clang-22-cross-<version>.pkg -target /
```

In a new Terminal:

```sh
clang++-22 -o hello hello.cpp
scp hello your-mavericks-system:
```

## Linux x86_64 host (in development)

The Linux compiler targets Mavericks; it does not build Linux executables. Its supported
host baseline is glibc 2.35 (Ubuntu 22.04), with Python 3.9+ for SDK setup. Use host-native
CMake and Ninja or Make, and keep build/cache directories on local disk.

The release archive is `clang22-<version>-linux-x86_64.tar.gz`, rooted at
`opt/mavergreen/clang22`. Fetch it by an exact version and SHA-256 with shipyard's
`fetch_product_tar.sh`, which returns the extracted compiler prefix. Apple SDK bytes
are fetched separately:

```sh
TC=$(sh "$SHIPYARD_SCRIPTS/fetch_product_tar.sh" clang22 "$VERSION" "$SHA256" "$HOME/.cache/mavergreen/clang22/$VERSION")
"$TC/bin/setup-sdk" "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh")"
"$TC/bin/clang++" hello.cpp -o hello-mavericks
```

Run `hello-mavericks` on Mavericks. For CMake projects, pass shipyard's
`MavericksToolchain.cmake`, `CMAKE_C_COMPILER=$TC/bin/clang`,
`CMAKE_CXX_COMPILER=$TC/bin/clang++`, and the colocated LLVM archive/readers explicitly.
Configure cannot execute target programs on Linux; test them on the target instead.
If the SDK cache moves, rerun `setup-sdk` with the new verified SDK path.

Maintainers build the Linux host tools using `build/linux/Dockerfile` and its pinned base
image/package lock. The first bootstrap is GCC 12.3; LLVM source signatures and every
patch in `patches/` are verified/applied as for the Mac variants. A matching Mac build
exports the target files. `build/rehearse-linux.sh` assembles and tests the compiler in
the baseline container, saving Mach-O test witnesses for `tests/target/runner.sh` on
Mavericks. The compiler archive and manifest are published only after those tests and
profile readback pass. Linux packaging/signing of Mac products remains out of scope.

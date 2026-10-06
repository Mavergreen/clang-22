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

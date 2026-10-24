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
sudo longboat sdk install 10.9
```

In a new Terminal:

```sh
clang++-22 -o hello hello.cpp
scp hello your-mavericks-system:
```

### From Linux

```sh
sudo tar -C /opt/mavergreen -zxpf clang22-<version>-linux-x86_64.tar.gz
sudo longboat sdk install 10.9
```

In a new terminal:

```sh
clang++-22 -o hello hello.cpp
scp hello your-mavericks-system:
```

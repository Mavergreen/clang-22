# Clang 22 for Mavericks

Clang/LLVM toolchain for Mac OS X 10.9 Mavericks.

## Compiling

Install [Longboat](https://github.com/Mavergreen/longboat),
then fetch the 10.9 SDK:

```sh
sudo longboat sdk install 10.9
```

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

### From Linux

```sh
sudo tar -C /opt/mavergreen -zxpf clang22-<version>-linux-x86_64.tar.gz
```

In a new terminal:

```sh
clang++-22 -o hello hello.cpp
scp hello your-mavericks-system:
```

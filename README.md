# CrossArm

CrossArm sets up a Docker-based ARM GNU/Linux cross-compilation environment with a host-mounted sysroot and a launcher script.

## Supported toolchains

Currently available through `install.sh`:

- `arm-linux-gnueabihf` (`7.2-2017.11`)

You can list supported versions with:

```bash
./install.sh --list-versions
```

## Requirements

`install.sh` expects these programs to be installed on the host:

- `docker`
- `wget`
- `tar`
- `sed`

No root is required for a normal install.

## Install

Default install:

```bash
./install.sh
```

By default this creates:

- Docker image: `crossarm`
- Sysroot directory: `~/.crossarm/crossarm-arm`
- Launcher script: `~/.local/bin/crossarm-arm`

If `~/.local/bin` is not in your `PATH`, add it before using the launcher.

Show all install options:

```bash
./install.sh --help
```

## Common options

```text
-a, --architecture ARCH
    Toolchain architecture (default: arm-linux-gnueabihf)

-v, --architecture-version VERSION
    Toolchain version (default: 7.2-2017.11)

-s, --suffix NAME
    Launcher/sysroot suffix (default: arm)

--launcher-path PATH
    Install path for the launcher script (default: ~/.local/bin)

--sysroot-path PATH
    Host path where the downloaded toolchain is stored (default: ~/.crossarm)

-n, --no-cache
    Build Docker image without cache

--dry-run
    Print commands without executing them

-u, --uninstall
    Remove installed sysroot and launcher

-V, --version
    Print installer version
```

## Usage

Open an interactive shell for the current directory:

```bash
crossarm-arm
```

Mount a different project directory:

```bash
crossarm-arm /path/to/project
```

Run a command directly inside the container:

```bash
crossarm-arm -c "cmake -S . -B build"
```

## Environment inside the container

The container sets these useful variables:

- `CROSS_COMPILE` (for example `arm-linux-gnueabihf-`)
- `SYSROOT`
- `CMAKE_TOOLCHAIN` (points to `/crossarm/toolchain.cmake`)

Toolchain binaries are added to `PATH`, so this works in the container:

```bash
${CROSS_COMPILE}gcc main.c -o main
```

For CMake, either use the env var or pass the file explicitly:

```bash
cmake -S . -B build -DCMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN"
```

## Uninstall

Remove launcher + sysroot:

```bash
./install.sh -u
```

The Docker image is not removed automatically. Remove it manually if needed:

```bash
docker rmi crossarm
```

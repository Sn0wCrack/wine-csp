# wine-csp

Customised Wine builds with CSP patches using the wine-tkg build system.

## Supported Versions

- Wine 11.4
- Wine 11.11

## Building Locally

Install dependencies (Ubuntu/Debian):

```bash
sudo apt-get install git wget xz-utils bubblewrap autoconf gcc g++ gcc-mingw-w64 g++-mingw-w64
```

Build a specific version:

```bash
WINE_VERSION=11.4 ./build-wine-csp.sh
```

Output tarballs are named `wine-csp-<version>-<arch>.tar.xz`.


## Credits

- parka6060 - https://github.com/parka6060/CSPenguin-Installer
- Kron4ek - https://github.com/Kron4ek/Wine-Builds
- Frog Family - https://github.com/Frogging-Family/wine-tkg-git
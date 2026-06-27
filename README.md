# wine-csp

Customised Wine builds with CSP patches.

Builds vanilla Wine from official WineHQ sources with CSP-specific patches
applied inside reproducible chroot environments. Mirrors the approach from
[Kron4ek/Wine-Builds](https://github.com/Kron4ek/Wine-Builds).

## Supported Versions

- Wine 11.4
- Wine 11.11

## Building Locally

First, create the build chroots (requires root):

```bash
sudo apt install debootstrap perl bubblewrap
sudo ./create-ubuntu-bootstraps.sh
```

Then build a specific version (does not require root):

```bash
WINE_VERSION=11.4 ./build-wine-csp.sh
```

Output tarballs are named `wine-csp-<version>-<arch>.tar.xz`.

## How It Works

- `create-ubuntu-bootstraps.sh` creates 64-bit and 32-bit Ubuntu 22.04
  chroots with all Wine build dependencies pre-installed using debootstrap.
- `build-wine-csp.sh` downloads the Wine source, applies CSP patches, then
  uses bubblewrap to run `configure` and `make` inside the appropriate
  chroot for each architecture.

## GitHub Actions

Two workflows:

- **Bootstraps CI** (`.github/workflows/bootstraps.yml`): Creates and uploads
  the chroots as a cached artifact. Runs on a schedule and on demand.
- **Build** (`.github/workflows/build.yml`): Downloads the bootstraps and
  builds all Wine versions. Triggered by creating a release. Tarballs are
  uploaded to the release assets.

## Adding a New Version

1. Place patches in `patches/<version>/` with `.patch` extension
2. Add the version to the matrix in `.github/workflows/build.yml`

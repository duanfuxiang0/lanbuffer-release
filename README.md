# lanbuffer-release

This repository is intended to host **prebuilt LanBuffer server binaries** for macOS/Linux and a standalone `install.sh` that does **not** require source code.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/duanfuxiang0/lanbuffer-release/main/install.sh | bash
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/duanfuxiang0/lanbuffer-release/main/install.sh | bash -s -- --version v1.0.2
```

## Publishing (from private source repo)

The private source repo’s GitHub Actions workflow should:

- build `lanbuffer` for:
  - `x86_64-unknown-linux-musl`
  - `aarch64-unknown-linux-musl`
  - `x86_64-apple-darwin`
  - `aarch64-apple-darwin`
- upload assets to this repo as a GitHub Release:
  - `lanbuffer-<version>-<target>.tar.gz`
  - `lanbuffer-<version>-<target>.tar.gz.sha256`

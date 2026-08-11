# lerobot-jetson

A Docker image for running [LeRobot](https://github.com/huggingface/lerobot) on NVIDIA Jetson boards.

`jetson-containers`, the usual way to build ML containers for Jetson, has been effectively unmaintained for a while (see [dusty-nv/jetson-containers#1270](https://github.com/dusty-nv/jetson-containers/issues/1270)) and its `lerobot` package is stale — missing `torchcodec`, using a renamed extra, referencing a CLI script that no longer exists. This repo ships a working image directly instead of waiting on that to get fixed.

## Status

- **Orin / JetPack 6.2 (L4T R36.4.x) / CUDA 12.6** — the only target so far.
- Other boards/JetPack versions: not tested, PRs welcome.

## Usage

```bash
docker pull ghcr.io/ravediamond/lerobot-jetson:latest
docker run --runtime nvidia -it ghcr.io/ravediamond/lerobot-jetson:latest
```

Or build it yourself:

```bash
docker build -t lerobot-jetson .
```

## What's different from jetson-containers' `lerobot` package

- `torchcodec` installed explicitly (missing upstream, needed by lerobot's video pipeline on aarch64).
- `pi0` extra renamed to `pi`; added `smolvla`.
- PyTorch pulled from NVIDIA's Jetson wheel index for JetPack 6.2/CUDA 12.6, not built from source.

## Building on Jetson

The image builds natively on the Jetson itself — no cross-compilation, no QEMU. If you want to build it via GitHub Actions on this repo, point it at a self-hosted runner registered on an actual Jetson; GitHub's hosted runners are x86_64 and emulating an aarch64 CUDA build there is impractically slow.

## License

Apache 2.0, matching LeRobot.

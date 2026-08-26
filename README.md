# lerobot-jetson

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Jetson%20Orin-76B900?logo=nvidia&logoColor=white)
![JetPack](https://img.shields.io/badge/JetPack-6.2-76B900?logo=nvidia&logoColor=white)

A Docker image for running [LeRobot](https://github.com/huggingface/lerobot) on NVIDIA Jetson boards.

The usual way to get an ML container on Jetson is [`jetson-containers`](https://github.com/dusty-nv/jetson-containers), but that project has been effectively unmaintained since its original maintainer stepped away in 2025 ([issue #1270](https://github.com/dusty-nv/jetson-containers/issues/1270)), and its `lerobot` package hasn't kept up — missing `torchcodec`, an extra that got renamed upstream, and a CLI script that doesn't exist anymore. Rather than wait for that to get fixed, this repo just ships a working image directly.

## Status

Both `Dockerfile` (builds torch/torchcodec/torchvision from source) and `Dockerfile.fast` (reuses artifacts already built bare-metal on this board) confirmed working end-to-end on a real Jetson Orin as of 2026-08-26: torch sees the GPU, torchvision's compiled ops load correctly, torchcodec decodes video on CUDA (a real `.cuda()` tensor comes out, not just a clean import), and `import lerobot` plus a policy import (SmolVLA) succeed.

That last part — `import lerobot` actually succeeding — took a second pass to get right: an earlier verification only checked torch/torchcodec imports, not lerobot itself. lerobot pulls in torchvision, and the generic PyPI wheel for it silently fails at runtime against a from-source torch build (`RuntimeError: operator torchvision::nms does not exist`) despite installing and importing cleanly — pip has no way to know it's the wrong build. Both Dockerfiles now build torchvision from source too, the same way they already did for torch/torchcodec.

Only Orin / JetPack 6.2 (L4T R36.4.x) / CUDA 12.6 has been tried. Other boards or JetPack versions: unknown, PRs welcome.

No image is published to GHCR yet — for now, building it yourself is the only option.

## Requirements

- A Jetson Orin on JetPack 6.2
- Docker with the NVIDIA container runtime set as default (this is standard on JetPack images)

## Usage

```bash
git clone https://github.com/ravediamond/lerobot-jetson.git
cd lerobot-jetson
docker build -t lerobot-jetson .
docker run --runtime nvidia -it -e HF_TOKEN=<your-hf-token> lerobot-jetson
```

Budget a few hours for the first build. No prebuilt cp312 wheel for torch or torchcodec exists anywhere for this platform yet — checked both NVIDIA's own redist and the jetson-ai-lab community index, which only goes up to cp310 — so both get compiled from source. Once built, Docker's layer caching makes rebuilds fast unless you bump a version.

`HF_TOKEN` is optional but recommended: without it, every pull from the Hub (datasets, pretrained policies) hits the unauthenticated rate limit, which is fine for a one-off test but bites fast on repeated runs.

## What's different from jetson-containers' `lerobot` package

- `torchcodec` and `torchvision` are both built from source and installed explicitly. `torchcodec` is missing entirely from the upstream package; `torchvision` is present but as a generic PyPI wheel that's silently ABI-incompatible with a from-source torch build here.
- The `pi0` extra was renamed to `pi` upstream a while back; this Dockerfile uses the current name and adds `smolvla` too.
- PyTorch is built from source for cp312, with a handful of flags that turned out to matter a lot on this hardware — flash-attention, memory-efficient attention, and NVSHMEM are all disabled. More on why below.

## Where these build steps came from

Every non-obvious line in the `Dockerfile` — the disabled PyTorch features, the pinned ffnvcodec headers, dav1d built from source instead of using apt's too-old version, the extra `libopenblas0`/`libcusparselt0` runtime packages, the `ensurepip` step right after creating the venv — exists because something broke without it, on this actual hardware, not because it seemed like a good idea in the abstract. A few examples:

- `USE_NVSHMEM=0`: PyTorch's CMake auto-enables NVSHMEM (a multi-node feature, meaningless on a single-board device) whenever it spots the `nvidia-nvshmem` pip package, then fails to link it at the very end of an hours-long compile.
- `libcusparselt0`: torch needs it at runtime, but the base image doesn't have the NVIDIA CUDA apt repo configured at all, let alone the package — just installing the package isn't enough, the repo has to be added first.
- The venv from `uv venv` doesn't ship `pip`. Easy to miss, breaks the very next line.

None of this is written up in full yet — if something breaks and you want the reasoning behind a specific line, open an issue here.

## Building on Jetson

The image builds natively on the board itself — no cross-compilation, no QEMU. If you want to wire this repo up to GitHub Actions, point the workflow at a self-hosted runner registered on an actual Jetson. GitHub's hosted runners are x86_64, and emulating an aarch64 CUDA build on one of those would be painfully slow, if it worked at all.

## License

Apache 2.0, matching LeRobot.

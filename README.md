# lerobot-jetson

A Docker image for running [LeRobot](https://github.com/huggingface/lerobot) on NVIDIA Jetson boards.

`jetson-containers`, the usual way to build ML containers for Jetson, has been effectively unmaintained for a while (see [dusty-nv/jetson-containers#1270](https://github.com/dusty-nv/jetson-containers/issues/1270)) and its `lerobot` package is stale — missing `torchcodec`, using a renamed extra, referencing a CLI script that no longer exists. This repo ships a working image directly instead of waiting on that to get fixed.

## Status

- **Orin / JetPack 6.2 (L4T R36.4.x) / CUDA 12.6** — the only target so far.
- Other boards/JetPack versions: not tested, PRs welcome.
- **Runtime stack verified working on real Orin hardware (2026-08-12)**: torch sees the GPU,
  torchcodec decodes video on CUDA (real `.cuda()` tensor out, not just a clean import), lerobot
  installs and imports clean. Verified via a prebuilt-artifact build path on the exact machine that
  produced the wheels; the `Dockerfile` in this repo (full from-source build, what a fresh clone
  actually runs) carries the same fixes but hasn't completed a full from-scratch run yet — that's
  the next real test, and it'll surface faster since caching means most of what could break here
  already broke and got fixed once.

## Usage

```bash
docker pull ghcr.io/ravediamond/lerobot-jetson:latest
docker run --runtime nvidia -it ghcr.io/ravediamond/lerobot-jetson:latest
```

Or build it yourself:

```bash
docker build -t lerobot-jetson .
```

Expect a few hours on the first build — no prebuilt cp312 torch/torchcodec wheel exists for this
platform yet (checked NVIDIA's redist and the jetson-ai-lab community index, cp310 only), so both
get compiled from source. Docker layer caching makes rebuilds fast unless you bump a version.

## What's different from jetson-containers' `lerobot` package

- `torchcodec` built from source and installed explicitly (missing upstream, needed by lerobot's
  video pipeline on aarch64 — no prebuilt wheel exists for cp312 on this platform).
- `pi0` extra renamed to `pi`; added `smolvla`.
- PyTorch built from source for cp312, matching flags verified to actually work on this hardware
  (flash-attention/mem-efficient-attention/NVSHMEM disabled — see below).

## Where these build steps came from

Every non-obvious flag in the `Dockerfile` (disabled PyTorch features, the pinned ffnvcodec
headers, dav1d built from source, the extra `libopenblas0`/`libcusparselt0` runtime deps, the
`ensurepip` step right after creating the venv) traces back to a specific build or runtime failure
hit and fixed on real Orin hardware, not a guess. Full gotcha-by-gotcha writeup not published yet —
open an issue here if something breaks and you want the reasoning behind a specific flag.

## Building on Jetson

The image builds natively on the Jetson itself — no cross-compilation, no QEMU. If you want to build it via GitHub Actions on this repo, point it at a self-hosted runner registered on an actual Jetson; GitHub's hosted runners are x86_64 and emulating an aarch64 CUDA build there is impractically slow.

## License

Apache 2.0, matching LeRobot.

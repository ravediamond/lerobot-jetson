# lerobot-jetson

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-Jetson%20Orin-76B900?logo=nvidia&logoColor=white)
![JetPack](https://img.shields.io/badge/JetPack-6.2-76B900?logo=nvidia&logoColor=white)

A Docker image for running [LeRobot](https://github.com/huggingface/lerobot) on NVIDIA Jetson boards.

The usual way to get an ML container on Jetson is [`jetson-containers`](https://github.com/dusty-nv/jetson-containers), but that project has been effectively unmaintained since its original maintainer stepped away in 2025 ([issue #1270](https://github.com/dusty-nv/jetson-containers/issues/1270)), and its `lerobot` package hasn't kept up — missing `torchcodec`, an extra that got renamed upstream, and a CLI script that doesn't exist anymore. Rather than wait for that to get fixed, this repo just ships a working image directly.

This image runs every experiment on [shissorobotics.com](https://shissorobotics.com), a register of robot-learning papers re-tested on an SO-101 and a Jetson Orin NX ([the register](https://shissorobotics.com/papers/)).

## Status

Both `Dockerfile` (builds torch/torchcodec/torchvision from source) and `Dockerfile.fast` (reuses artifacts already built bare-metal on this board) confirmed working end-to-end on a real Jetson Orin as of 2026-08-26: torch sees the GPU, torchvision's compiled ops load correctly, torchcodec decodes video on CUDA (a real `.cuda()` tensor comes out, not just a clean import), and `import lerobot` plus a policy import (SmolVLA) succeed.

That last part — `import lerobot` actually succeeding — took a second pass to get right: an earlier verification only checked torch/torchcodec imports, not lerobot itself. lerobot pulls in torchvision, and the generic PyPI wheel for it silently fails at runtime against a from-source torch build (`RuntimeError: operator torchvision::nms does not exist`) despite installing and importing cleanly — pip has no way to know it's the wrong build. Both Dockerfiles now build torchvision from source too, the same way they already did for torch/torchcodec.

**2026-08-31 — full from-scratch rebuild, `USE_DISTRIBUTED=1`/`USE_GLOO=1` and `USE_MEM_EFF_ATTENTION=1` confirmed working, not just staged.** Verified live in the built image: `torch.distributed.is_available()`/`is_gloo_available()` both `True`, `lerobot.distributed.utils.is_main_process()` no longer needs the sed-patched stub guard (still applied, now a harmless no-op), `torch.backends.cuda.mem_efficient_sdp_enabled()` is `True`. Total build time 5h 33m, of which PyTorch compilation alone is 92% (~5h 6m) — everything else (ffmpeg, torchcodec, torchvision, lerobot install) finishes in under 15 minutes combined.

Only Orin / JetPack 6.2 (L4T R36.4.x) / CUDA 12.6 has been tried. Other boards or JetPack versions: unknown, PRs welcome.

**2026-09-07 — image published to GHCR**: `ghcr.io/ravediamond/lerobot-jetson:public` / `:latest` (same image, both tags), built from the 2026-08-31 rebuild above. Pull instead of building from scratch unless you need to change something.

**2026-10-06 - release `0.6.2-jp6.2`**: the image now installs every extra of lerobot's `all` (all policies, envs and robots) except `intelrealsense`, whose `pyrealsense2` pin has no aarch64 wheel (so RealSense cameras are not supported in this image yet). lerobot is pinned to commit `200ee53` (0.6.2), and `triton` is installed so `torch.compile` works with the default inductor backend ([#2](https://github.com/ravediamond/lerobot-jetson/issues/2)). `async` and `vla_jepa` are included ([#1](https://github.com/ravediamond/lerobot-jetson/issues/1)). Verified in the built image on a Jetson Orin: torch sees the GPU, torchcodec decodes, torchvision `nms` runs on CUDA, an inductor-compiled kernel runs, `lerobot.async_inference` and the `vla_jepa` policy import, and `pip check` is clean. Image size is about 28 GB (was 24.6 GB). Only `Dockerfile` has these changes, not `Dockerfile.fast` or `Dockerfile.multistage`.

**2026-11-06 - release `0.7.0-jp6.2`**: lerobot v0.7.0 on the same torch 2.11 / torchvision 0.26 / torchcodec 0.11 layers as `0.6.2-jp6.2` (transformers 5.22). v0.7.0 installs CUDA 13 torch from PyPI on Linux and needs NVIDIA driver 580.65 or newer; JetPack 6.2 has driver 540 and CUDA 12.6, so the image keeps its source-built torch and the build fails if an extra replaces it. Built with the new `Dockerfile.upgrade` (`docker build -f Dockerfile.upgrade --build-arg LEROBOT_REF=v0.7.0 -t lerobot-jetson:0.7.0-jp6.2 .`), which starts from a published image and only moves the lerobot install. Checked on an Orin NX: `torch.cuda.is_available()`, SmolVLA and VLA-JEPA imports, SmolVLA loading and `predict_action_chunk` / `select_action` on a Hub checkpoint, and `lerobot-policy-server --help`. Not checked: training, `lerobot-rollout` with a remote policy, and the arm. lerobot's own breaking changes apply (`lerobot.async_inference` is gone, use `lerobot[remote]`; see its v0.7.0 release notes).

Tags: `0.7.0-jp6.2` is the newest release and `latest` points at it. `0.6.2-jp6.2` is the previous release (lerobot 0.6.2) and `public` is the older 2026-08-31 image.

## Requirements

- A Jetson Orin on JetPack 6.2
- Docker with the NVIDIA container runtime set as default (this is standard on JetPack images)

## Usage

Pull the prebuilt image:

```bash
docker pull ghcr.io/ravediamond/lerobot-jetson:0.7.0-jp6.2   # or :latest
docker run --runtime nvidia -it -e HF_TOKEN=<your-hf-token> ghcr.io/ravediamond/lerobot-jetson:0.7.0-jp6.2
```

Or build it yourself:

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
- All of lerobot's extras are installed (`.[all]` minus `intelrealsense`, see `EXCLUDE_EXTRAS` in the `Dockerfile`), not a hand-picked list, and lerobot is pinned to a commit (`LEROBOT_REF`, any branch, tag or SHA works). The build fails if an extra replaces the source-built torch with a PyPI one.
- `triton` is installed so `torch.compile` works with the inductor backend.
- `CMAKE_POLICY_VERSION_MINIMUM=3.5` is set for the install: `egl_probe` (a robomimic/libero dependency) ships a CMake file that CMake 4 rejects.
- PyTorch is built from source for cp312, with a handful of flags that turned out to matter a lot on this hardware — flash-attention and NVSHMEM are disabled, distributed (Gloo backend) and memory-efficient attention are enabled. More on why below.

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

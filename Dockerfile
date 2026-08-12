# LeRobot on NVIDIA Jetson Orin, JetPack 6.2 (L4T R36.4.x), CUDA 12.6
#
# No prebuilt cp312 torch/torchcodec wheel exists anywhere for this platform yet
# (checked both NVIDIA's redist and the jetson-ai-lab community index), so this
# builds torch and torchcodec from source. First build takes a few hours;
# Docker layer caching makes rebuilds fast unless you bump versions.
FROM nvcr.io/nvidia/l4t-jetpack:r36.4.0

ARG LEROBOT_REPO=huggingface/lerobot
ARG LEROBOT_REF=main
ARG PYTHON_VERSION=3.12
ARG TORCH_VERSION=2.11.0
ARG TORCHCODEC_VERSION=0.11.0
ARG TORCH_CUDA_ARCH=8.7

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

# --- base toolchain + Python 3.12 (deadsnakes PPA ships python3.12-dev, apt jammy alone doesn't) ---
RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common curl git ninja-build pkg-config \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev libopenblas0 \
    && rm -rf /var/lib/apt/lists/*

# base image has CUDA itself but not this apt repo, needed for libcusparselt0 (torch links against it)
RUN curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/cuda-archive-keyring.gpg \
        -o /usr/share/keyrings/cuda-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/arm64/ /" \
        > /etc/apt/sources.list.d/cuda-ubuntu2204-arm64.list \
    && apt-get update && apt-get install -y --no-install-recommends libcusparselt0 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"
RUN uv venv --python python${PYTHON_VERSION} /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
# uv-created venvs don't ship pip by default
RUN python3 -m ensurepip --upgrade \
    && python3 -m pip install --upgrade pip setuptools wheel ninja cmake pyyaml numpy

# --- build PyTorch from source ---
# USE_FLASH_ATTENTION/USE_MEM_EFF_ATTENTION off: OOM-kills the 16GB board during the
# backward-kernel compile otherwise; not needed by lerobot's policies (SDPA fallback is fine).
# USE_NVSHMEM off: multi-node feature, irrelevant on a single-board device, but CMake
# auto-enables it if the nvidia-nvshmem pip package is present and silently fails to link.
RUN git clone --recursive --branch v${TORCH_VERSION} https://github.com/pytorch/pytorch.git /opt/pytorch-src
WORKDIR /opt/pytorch-src
RUN USE_CUDA=1 USE_CUDNN=1 \
    TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH}" \
    PYTORCH_BUILD_VERSION=${TORCH_VERSION} PYTORCH_BUILD_NUMBER=1 \
    MAX_JOBS=3 USE_DISTRIBUTED=0 USE_FLASH_ATTENTION=0 USE_MEM_EFF_ATTENTION=0 USE_NVSHMEM=0 \
    python3 setup.py bdist_wheel \
    && python3 -m pip install dist/torch-${TORCH_VERSION}-cp312-cp312-linux_aarch64.whl

# --- build ffmpeg with NVDEC (dav1d >=1.0.0 needed by ffmpeg 8.x, jammy's apt only has 0.9.2) ---
RUN git clone --branch 1.5.1 --depth 1 https://code.videolan.org/videolan/dav1d.git /opt/dav1d-src \
    && apt-get update && apt-get install -y --no-install-recommends meson ninja-build \
    && cd /opt/dav1d-src && meson setup build --buildtype release && ninja -C build install \
    && rm -rf /var/lib/apt/lists/*

# Pin ffnvcodec headers instead of tracking master: newer master renamed a struct field
# (countingType -> countingTypeLSB) that breaks ffmpeg 8.x's nvenc.c.
RUN git clone --branch n13.0.19.0 --depth 1 https://github.com/FFmpeg/nv-codec-headers.git /opt/nv-codec-headers-src \
    && cd /opt/nv-codec-headers-src && make install

RUN git clone --branch n8.1 --depth 1 https://github.com/FFmpeg/FFmpeg.git /opt/ffmpeg-src
WORKDIR /opt/ffmpeg-src
RUN NVCCFLAGS=$(nvcc --list-gpu-code | sed 's/^sm_/-gencode arch=compute_&,code=sm_&/' | tr '\n' ' ') && \
    ./configure --enable-nonfree --enable-cuda-nvcc --enable-libnpp --enable-libdav1d \
        --enable-nvdec --enable-cuvid --enable-nvenc \
        --nvccflags="${NVCCFLAGS}" \
        --extra-cflags=-I/usr/local/cuda/include \
        --extra-ldflags=-L/usr/local/cuda/lib64 \
        --disable-static --enable-shared \
    && make -j3 && make install && ldconfig

# --- build torchcodec from source, CUDA-enabled ---
RUN git clone --branch v${TORCHCODEC_VERSION} --depth 1 https://github.com/pytorch/torchcodec.git /opt/torchcodec-src
WORKDIR /opt/torchcodec-src
RUN ENABLE_CUDA=1 CUDAARCHS=87 I_CONFIRM_THIS_IS_NOT_A_LICENSE_VIOLATION=1 python3 setup.py bdist_wheel \
    && python3 -m pip install dist/torchcodec-*.whl

# --- install lerobot ---
WORKDIR /opt/lerobot
RUN git clone --branch=${LEROBOT_REF} --depth=1 https://github.com/${LEROBOT_REPO} . \
    && python3 -m pip install -e ".[feetech, aloha, pusht, dynamixel, pi, smolvla, test]" --no-build-isolation

# pip resolves lerobot's torchcodec>=0.11.0 constraint against our local build's version tag
# (0.11.0a0 < 0.11.0 per PEP 440) and silently swaps in a generic PyPI wheel that crashes here
# (libnvrtc.so.13 not found - built against CUDA 13's runtime, this board has 12.6). Reassert ours.
RUN python3 -m pip install --force-reinstall --no-deps /opt/torchcodec-src/dist/torchcodec-*.whl

RUN apt-get update && apt-get install -y --no-install-recommends \
        speech-dispatcher speech-dispatcher-espeak-ng ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/lerobot
CMD ["/bin/bash"]

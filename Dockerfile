# LeRobot on NVIDIA Jetson Orin, JetPack 6.2 (L4T R36.4.x), CUDA 12.6
FROM nvcr.io/nvidia/l4t-jetpack:r36.4.0

ARG LEROBOT_REPO=huggingface/lerobot
ARG LEROBOT_REF=main
ARG PYTHON_VERSION=3.12

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        software-properties-common curl git ffmpeg \
        speech-dispatcher speech-dispatcher-espeak-ng \
        libopencv-dev python3-opencv \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /opt/lerobot
RUN git clone --branch=${LEROBOT_REF} --depth=1 https://github.com/${LEROBOT_REPO} . \
    && uv venv --python python${PYTHON_VERSION} /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# NVIDIA's Jetson PyTorch wheel index (aarch64, JetPack 6.2 / CUDA 12.6)
RUN uv pip install --index-url https://pypi.jetson-ai-lab.io/jp6/cu126 torch torchvision \
    && uv pip install -e ".[feetech, aloha, pusht, dynamixel, pi, smolvla, test]" \
    # torchcodec isn't in the default extras; lerobot's video pipeline expects it on aarch64
    && uv pip install torchcodec>=0.11.0

CMD ["/bin/bash"]

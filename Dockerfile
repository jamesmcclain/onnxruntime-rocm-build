FROM ubuntu:22.04 AS stage1
MAINTAINER James McClain <jmcclain@daystrom-data-concepts.com>

ARG ROCM_VERSION=5.7
ARG AMDGPU_VERSION=5.7

ENV PATH "${PATH}:/opt/rocm/bin"

# https://rocm.docs.amd.com/en/latest/deploy/linux/os-native/install.html
RUN --mount=type=cache,target=/var/cache/apt \
    apt update -y && \
    apt install -y wget gpg && \
    mkdir --parents --mode=0755 /etc/apt/keyrings && \
    wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null && \
    apt update -y && \
    sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/${AMDGPU_VERSION}/ubuntu jammy main" | tee /etc/apt/sources.list.d/amdgpu.list' && \
    apt update -y && \
    sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} jammy main" | tee --append /etc/apt/sources.list.d/rocm.list' && \
    apt update -y && \
    sh -c "echo 'Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600' | tee /etc/apt/preferences.d/rocm-pin-600" && \
    apt update -y

RUN --mount=type=cache,target=/var/cache/apt \
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends libelf1 libnuma-dev build-essential git vim-nox cmake-curses-gui kmod file python3 python3-pip rocm-dev rocblas-dev miopen-hip-dev zsh && \
    apt autoremove -y && apt autoclean -y && apt clean -y

WORKDIR /workdir

CMD ["zsh", "-l"]

# DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 -f Dockerfile --target stage1 -t onnxruntime-rocm-stage1 .

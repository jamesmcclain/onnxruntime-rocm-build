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

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install coloredlogs==15.0.1 flatbuffers==23.5.26 humanfriendly==10.0 mpmath==1.3.0 numpy==1.26.0 packaging==23.2 protobuf==4.24.3 sympy==1.12

WORKDIR /workdir

CMD ["zsh", "-l"]

# DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 -f Dockerfile --target stage1 -t onnxruntime-rocm-stage1 .

# ------------------------------------------------------------------------

FROM stage1 AS stage2

ARG ONNXRUNTIME_REPO=https://github.com/Microsoft/onnxruntime
ARG ONNXRUNTIME_BRANCH=main
ARG ONNXRUNTIME_COMMIT=6a5f469d44aca607bd08cc2aca117c33bab31da8

ENV PATH /code/cmake-3.27.3-linux-x86_64/bin:${PATH}

WORKDIR /code

RUN --mount=type=cache,target=/var/cache/apt \
    apt install -y rocm-libs libpython3-dev

RUN wget --quiet https://github.com/Kitware/CMake/releases/download/v3.27.3/cmake-3.27.3-linux-x86_64.tar.gz && \
    tar zxf cmake-3.27.3-linux-x86_64.tar.gz && \
    rm -rf cmake-3.27.3-linux-x86_64.tar.gz

RUN git clone --single-branch --branch ${ONNXRUNTIME_BRANCH} --recursive ${ONNXRUNTIME_REPO} onnxruntime &&\
    /bin/sh onnxruntime/dockerfiles/scripts/install_common_deps.sh &&\
    cd onnxruntime &&\
    git checkout ${ONNXRUNTIME_COMMIT} && \
    /bin/sh ./build.sh --allow_running_as_root --config Release --build_wheel --update --build --parallel \
    	    --cmake_extra_defines onnxruntime_USE_COMPOSABLE_KERNEL=OFF ONNXRUNTIME_VERSION=$(cat ./VERSION_NUMBER) \
	    --use_rocm --rocm_version ${ROCM_VERSION} --rocm_home=/opt/rocm \
	    --skip_submodule_sync --skip_tests
RUN pip install /code/onnxruntime/build/Linux/Release/dist/*.whl

# DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 -f Dockerfile --target stage2 -t onnxruntime-rocm-stage2 .

# ------------------------------------------------------------------------

FROM stage1

COPY --from=stage2 /code/onnxruntime/build/Linux/Release/dist/ /code/onnxruntime/build/Linux/Release/dist/

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install /code/onnxruntime/build/Linux/Release/dist/*.whl

# DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_INLINE_CACHE=1 -f Dockerfile -t jamesmcclain/onnxruntime-rocm:rocm5.7-ubuntu22.04 .

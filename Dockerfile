# ComfyUI + MiniMax H3 Motion Context V2 (Singularity v2) + JupyterLab — RunPod template image
#
# What's baked into the image:  ComfyUI (latest), custom nodes, JupyterLab, your workflow.
# SageAttention 2 is compiled on the pod at first boot (see start.sh).
# What's downloaded on first boot: the ~56 GB of models, into /workspace/models (your network volume),
# so they survive pod restarts and the image stays small enough to push.

ARG CUDA_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    COMFYUI_DIR=/opt/ComfyUI

# ---- system packages (ffmpeg is a hard requirement of ComfyUI-Easy-Media) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev build-essential ninja-build \
        git git-lfs ffmpeg curl wget aria2 rsync ca-certificates \
        openssh-server nano tmux htop libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/venv \
    && pip install --upgrade pip wheel setuptools packaging

# ---- PyTorch (CUDA 12.8 wheels: Ampere through Blackwell / RTX 5090) ----
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128
RUN pip install torch torchvision torchaudio --index-url ${TORCH_INDEX_URL}

# ---- ComfyUI (needs 0.34.0+ for native H3 audio/video keyframes used by Motion Context) ----
ARG COMFYUI_REF=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} \
    && cd ${COMFYUI_DIR} && git checkout ${COMFYUI_REF} \
    && pip install -r requirements.txt

# ---- custom nodes used by the workflow ----
#   ComfyUI-Easy-Media : easy multiTrackEditor / multitrackProject / modelLoaderPack /
#                        multitrackProjectVideoCombine / saveVideo
#   ComfyUI-KJNodes    : ModelPreviewOverrideKJ (taeh3 previews), MiniMaxH3MemoryEfficientSageAttentionPatch
#   ComfyUI-Manager    : so you can add more nodes from the UI
#   cg-use-everywhere  : the workflow was saved with its properties; avoids frontend warnings
RUN cd ${COMFYUI_DIR}/custom_nodes \
    && git clone --depth 1 https://github.com/yolain/ComfyUI-Easy-Media.git \
    && git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes.git \
    && git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git \
    && git clone --depth 1 https://github.com/chrisgoringe/cg-use-everywhere.git \
    && for d in */ ; do \
         if [ -f "$d/requirements.txt" ]; then echo ">> requirements for $d"; pip install -r "$d/requirements.txt"; fi ; \
       done

# ---- SageAttention 2 ----
# Not compiled here: compiling CUDA kernels for 5 GPU generations needs lots of RAM and
# crashed Docker Desktop. start.sh compiles it on the pod's own GPU on first boot instead
# (a few minutes, one architecture) and keeps the wheel on /workspace for later boots.

# ---- JupyterLab + Hugging Face downloader (xet backend for fast large-file pulls) ----
RUN pip install jupyterlab ipywidgets "huggingface_hub[cli,hf_xet]"

# ---- template files ----
COPY scripts/start.sh /start.sh
COPY scripts/download_models.py /opt/template/download_models.py
COPY workflows/ /opt/template/workflows/
RUN chmod +x /start.sh \
    && sed -i 's/#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

WORKDIR /workspace
EXPOSE 8188 8888 22
CMD ["/start.sh"]

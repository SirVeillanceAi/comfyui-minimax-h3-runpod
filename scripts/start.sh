#!/usr/bin/env bash
# Boot script for the ComfyUI MiniMax H3 RunPod template.
# Order: SSH -> persistent folders on /workspace -> JupyterLab -> model download -> ComfyUI.
set -uo pipefail

WS=${WORKSPACE:-/workspace}
COMFY=${COMFYUI_DIR:-/opt/ComfyUI}
LOGS="$WS/logs"
export MODELS_DIR="$WS/models"
mkdir -p "$LOGS" "$WS/output" "$WS/input" "$WS/comfyui-user/default/workflows"

log() { echo "[start] $*"; }
export HF_HOME="${HF_HOME:-$WS/.cache/huggingface}"
if ! mountpoint -q "$WS" 2>/dev/null; then
  log "WARNING: $WS is not a separate volume — it's on the 50 GB container disk, which is too small"
  log "WARNING: for the ~56 GB of models. Redeploy with Volume Disk = 150 GB."
fi

# ---------- SSH (RunPod injects PUBLIC_KEY) ----------
if [ -n "${PUBLIC_KEY:-}" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
  ssh-keygen -A >/dev/null 2>&1
  service ssh start >/dev/null 2>&1 && log "SSH started"
fi

# ---------- models live on the volume ----------
# First boot copies ComfyUI's empty model folder layout to /workspace/models, then
# ComfyUI's own models folder becomes a link to it — every custom node finds the files.
if [ ! -L "$COMFY/models" ]; then
  mkdir -p "$MODELS_DIR"
  if cp -an "$COMFY/models/." "$MODELS_DIR/"; then
    rm -rf "$COMFY/models"
    ln -s "$MODELS_DIR" "$COMFY/models"
  else
    log "Could not copy the model folder layout — leaving $COMFY/models in place"
  fi
fi
mkdir -p "$MODELS_DIR"/{diffusion_models,loras,text_encoders,vae,vae_approx,latent_upscale_models}

# ---------- your workflow shows up in the Workflows sidebar ----------
for f in /opt/template/workflows/*.json; do
  [ -e "$f" ] || continue
  cp -n "$f" "$WS/comfyui-user/default/workflows/" 2>/dev/null || true
done

# ---------- JupyterLab on 8888 ----------
if [ "${DISABLE_JUPYTER:-0}" != "1" ]; then
  TOKEN="${JUPYTER_PASSWORD:-}"
  if [ -z "$TOKEN" ]; then
    TOKEN=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    log "No JUPYTER_PASSWORD set — generated token: $TOKEN"
    echo "$TOKEN" > "$WS/logs/jupyter_token.txt"
  fi
  nohup jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --allow-root \
      --ServerApp.root_dir="$WS" --ServerApp.allow_origin='*' \
      --ServerApp.allow_remote_access=True \
      --IdentityProvider.token="$TOKEN" \
      > "$LOGS/jupyter.log" 2>&1 &
  log "JupyterLab started on 8888 (log: $LOGS/jupyter.log)"
fi

# ---------- SageAttention 2 (compiled for this pod's GPU, cached on the volume) ----------
# Runs in the background while models download; ComfyUI waits for it before starting.
build_sage() {
  if python -c "import sageattention" >/dev/null 2>&1; then log "SageAttention already installed"; return 0; fi
  local cap torchv cache whl
  cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')
  if [ -z "$cap" ]; then log "No GPU visible — skipping SageAttention"; return 0; fi
  torchv=$(python -c "import torch;print(torch.__version__.replace('+','_'))")
  cache="$WS/.cache/sage/sm${cap/./}_torch${torchv}"
  whl=$(ls "$cache"/sageattention-*.whl 2>/dev/null | head -1)
  if [ -z "$whl" ]; then
    log "Compiling SageAttention 2 for compute capability $cap (first boot only, ~5-15 min)"
    rm -rf /tmp/SageAttention && git clone --depth 1 https://github.com/thu-ml/SageAttention.git /tmp/SageAttention || return 1
    mkdir -p "$cache"
    local jobs; jobs=$(( $(nproc) > 16 ? 16 : $(nproc) ))
    ( cd /tmp/SageAttention && TORCH_CUDA_ARCH_LIST="$cap" EXT_PARALLEL=4 MAX_JOBS=$jobs \
        pip wheel --no-build-isolation --no-deps -w "$cache" . ) || { log "SageAttention build failed"; return 1; }
    rm -rf /tmp/SageAttention
    whl=$(ls "$cache"/sageattention-*.whl | head -1)
  fi
  pip install --no-deps "$whl" && log "SageAttention installed from $whl"
}
build_sage > "$LOGS/sageattention.log" 2>&1 &
SAGE_PID=$!

# ---------- models ----------
if [ "${SKIP_MODEL_DOWNLOAD:-0}" != "1" ]; then
  log "Checking / downloading models (~56 GB on first boot) — progress in $LOGS/models.log"
  python /opt/template/download_models.py 2>&1 | tee "$LOGS/models.log" \
    || log "Model download had errors — ComfyUI will still start. See $LOGS/models.log"
fi

if [ -n "${SAGE_PID:-}" ]; then
  log "Waiting for SageAttention (log: $LOGS/sageattention.log)"
  wait "$SAGE_PID" || log "SageAttention not available — use a non-Sage attention option in the workflow"
fi

# ---------- ComfyUI on 8188 (restarts itself if it crashes) ----------
cd "$COMFY" || { log "ComfyUI folder $COMFY missing"; exit 1; }
while true; do
  log "Starting ComfyUI on 8188"
  # shellcheck disable=SC2086
  python main.py --listen 0.0.0.0 --port 8188 \
      --output-directory "$WS/output" \
      --input-directory "$WS/input" \
      --user-directory "$WS/comfyui-user" \
      ${COMFYUI_ARGS:-} 2>&1 | tee -a "$LOGS/comfyui.log"
  log "ComfyUI exited — restarting in 5 s"
  sleep 5
done

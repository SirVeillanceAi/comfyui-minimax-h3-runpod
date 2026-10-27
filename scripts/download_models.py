#!/usr/bin/env python3
"""Download every model the MiniMax H3 Motion Context V2 workflow loads.

Files go to $MODELS_DIR (default /workspace/models) in the standard ComfyUI folders.
Anything already present at the right size is skipped, so re-running is cheap.

Env:
  HF_TOKEN           needed if a repo asks you to accept its license first
  DOWNLOAD_FP16_VAE  1 = also fetch the stock fp16 video VAE (fallback if the int8 VAE
                     ever gives you a black video)
  DL_WORKERS         parallel downloads (default 2)
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

from huggingface_hub import hf_hub_download

MODELS_DIR = os.environ.get("MODELS_DIR", "/workspace/models")
TOKEN = os.environ.get("HF_TOKEN") or None

# (repo, path inside repo, ComfyUI folder, expected bytes or None)
MODELS = [
    # UNETLoader — Singularity v2 ref2va int8 fine-tune (~34 GB)
    ("WarmBloodAban/Minimax-h3_Singularity",
     "Minimax-h3_Singularity_ref2va_v2_int8.safetensors", "diffusion_models", 34004507622),
    # LoraLoaderModelOnly — ref2v turbo 4-step v0.1
    ("Comfy-Org/MiniMax-H3",
     "loras/minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors", "loras", 1956193000),
    # CLIPLoader (type: minimax) — Qwen3-VL 32B nvfp4 text encoder
    ("Comfy-Org/MiniMax-H3",
     "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors", "text_encoders", 15687142551),
    # VAELoader — int8 convrot video VAE (Kijai)
    ("Kijai/MiniMax-H3-experimental",
     "minimax_h3_video_vae_int8_convrot.safetensors", "vae", 3171670912),
    # VAELoader — audio VAE
    ("Comfy-Org/MiniMax-H3",
     "vae/minimax_h3_audio_vae_fp32.safetensors", "vae", 605254808),
    # ModelPreviewOverrideKJ tiny_vae — taeh3 preview decoder
    ("Kijai/MiniMax-H3-TAE",
     "vae_approx/taeh3.safetensors", "vae_approx", 9791388),
    # easy multitrackProject upscale_model (only used if you switch to dual sampling).
    # The repo moved the file into a subfolder; it is saved under the name the workflow expects.
    ("LBH-123-AI/Minimax_h3_latent_Upscaler",
     "minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors",
     "latent_upscale_models", 690592672, "minimax_h3_latent_upscaler_3d_fp16.safetensors"),
]

if os.environ.get("DOWNLOAD_FP16_VAE", "0") == "1":
    MODELS.append(("Comfy-Org/MiniMax-H3",
                   "vae/minimax_h3_video_vae_fp16.safetensors", "vae", None))


def have(dest, size):
    if not os.path.isfile(dest):
        return False
    return size is None or os.path.getsize(dest) == size


def fetch(repo, path, folder, size, name=None):
    name = name or os.path.basename(path)
    dest_dir = os.path.join(MODELS_DIR, folder)
    dest = os.path.join(dest_dir, name)
    if have(dest, size):
        return f"[skip] {folder}/{name}"
    os.makedirs(dest_dir, exist_ok=True)
    staging = os.path.join(MODELS_DIR, ".hf_staging")
    print(f"[get ] {repo} :: {path}", flush=True)
    got = hf_hub_download(repo_id=repo, filename=path, local_dir=staging, token=TOKEN)
    shutil.move(got, dest)
    if size is not None and os.path.getsize(dest) != size:
        raise RuntimeError(f"size mismatch for {name}: {os.path.getsize(dest)} != {size}")
    return f"[done] {folder}/{name}"


def check_space():
    """Stop early with a clear message if the disk can't hold what's still missing."""
    need = 0
    for m in MODELS:
        repo, path, folder, size = m[:4]
        name = m[4] if len(m) > 4 else os.path.basename(path)
        if size and not have(os.path.join(MODELS_DIR, folder, name), size):
            need += size
    os.makedirs(MODELS_DIR, exist_ok=True)
    free = shutil.disk_usage(MODELS_DIR).free
    gb = lambda b: f"{b / 1e9:.0f} GB"
    print(f"Models still to download: {gb(need)}  |  free space in {MODELS_DIR}: {gb(free)}", flush=True)
    if need > free - 2e9:
        print("\nNOT ENOUGH DISK SPACE for the models.\n"
              "Deploy the pod with a Volume Disk of at least 100 GB (the template default is 150 GB),\n"
              "or attach a network volume. On the Deploy page: Edit Template -> Volume Disk.", flush=True)
        sys.exit(2)


def main():
    check_space()
    failed = []
    with ThreadPoolExecutor(max_workers=int(os.environ.get("DL_WORKERS", "2"))) as pool:
        jobs = {pool.submit(fetch, *m): m for m in MODELS}
        for job in as_completed(jobs):
            repo, path = jobs[job][0], jobs[job][1]
            try:
                print(job.result(), flush=True)
            except Exception as e:  # keep going, report at the end
                failed.append((repo, path, e))
                print(f"[FAIL] {repo} :: {path}\n       {e}", flush=True)
    shutil.rmtree(os.path.join(MODELS_DIR, ".hf_staging"), ignore_errors=True)
    if failed:
        print("\nSome downloads failed. If you see 401/403, open the repo page on huggingface.co,"
              " accept its license, and set HF_TOKEN on the pod. Then run:\n"
              "  python /opt/template/download_models.py", flush=True)
        sys.exit(1)
    print("\nAll MiniMax H3 models are in place.", flush=True)


if __name__ == "__main__":
    main()

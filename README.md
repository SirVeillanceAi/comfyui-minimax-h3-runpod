# ComfyUI · MiniMax H3 Motion Context V2 — RunPod template

A Docker image + RunPod template that boots ComfyUI with everything your
`MINIMAX_H3_Motion_Context_V2.json` workflow needs, plus JupyterLab.

| Port | What |
|------|------|
| 8188 | ComfyUI (your workflow is already in the Workflows sidebar) |
| 8888 | JupyterLab (rooted at `/workspace`) |
| 22   | SSH (uses the public key in your RunPod settings) |

## What's inside

**Baked into the image:** ComfyUI (latest, needs 0.34+ for H3 Motion Context), PyTorch CUDA 12.8,
SageAttention 2 (compiled on the pod for its own GPU at first boot, then cached in /workspace/.cache/sage),
JupyterLab, ffmpeg, and these custom nodes:

| Node pack | Nodes from your workflow |
|-----------|--------------------------|
| [ComfyUI-Easy-Media](https://github.com/yolain/ComfyUI-Easy-Media) | MultiTrack Editor, MultiTrack Project, Model Loader Pack, Project Video Combine, Save Video |
| [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes) | ModelPreviewOverrideKJ, MiniMax H3 Mem Eff Sage Attention Patch |
| ComfyUI-Manager | (so you can add more from the UI) |
| cg-use-everywhere | (the workflow was saved with its properties) |

Everything else in the workflow (UNETLoader, CLIPLoader, VAELoader, LoRA loader, schedulers, SaveVideo) is core ComfyUI.

**Downloaded on first boot into `/workspace/models`** (~56 GB, kept on your volume):

| Folder | File | From |
|--------|------|------|
| diffusion_models | Minimax-h3_Singularity_ref2va_v2_int8.safetensors | WarmBloodAban/Minimax-h3_Singularity |
| loras | minimax_h3_ref2v_turbo_4step_v0.1_comfyui_bf16.safetensors | Comfy-Org/MiniMax-H3 |
| text_encoders | qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors | Comfy-Org/MiniMax-H3 |
| vae | minimax_h3_video_vae_int8_convrot.safetensors | Kijai/MiniMax-H3-experimental |
| vae | minimax_h3_audio_vae_fp32.safetensors | Comfy-Org/MiniMax-H3 |
| vae_approx | taeh3.safetensors | Kijai/MiniMax-H3-TAE |
| latent_upscale_models | minimax_h3_latent_upscaler_3d_fp16.safetensors | LBH-123-AI/Minimax_h3_latent_Upscaler |

Models are downloaded at boot instead of baked in because a 60 GB+ image is slow to push,
slow for RunPod to pull, and has to be re-pulled on every new pod.

## Step 1 — get the image onto Docker Hub (pick one)

**A. Build on your PC** (Docker Desktop running):

```powershell
docker login
.\build-and-push.ps1 -DockerHubUser sirveillanceai
```

**B. Let GitHub build it** (nothing heavy on your PC):

1. Create a new repository on github.com (e.g. `SirVeillanceAi/comfyui-minimax-h3-runpod`) and upload this whole folder.
2. In the repo: **Settings → Secrets and variables → Actions → New repository secret**, add
   `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (make the token at hub.docker.com → Account settings → Personal access tokens).
3. **Actions** tab → *Build and push to Docker Hub* → **Run workflow**. It takes about 15–25 minutes.

## Step 2 — create the RunPod template (pick one)

**A. One command:**

```powershell
.\create-runpod-template.ps1 -DockerHubUser sirveillanceai -RunPodApiKey rpa_xxxxx
```

**B. By hand:** RunPod → My Templates → New Template, and copy the values from `runpod-template.json`:
image `sirveillanceai/comfyui-minimax-h3:latest`, container disk 50 GB, volume 150 GB at `/workspace`,
HTTP ports `8188, 8888`, TCP port `22`.

## Environment variables

| Variable | Default | What it does |
|----------|---------|--------------|
| `HF_TOKEN` | — | Hugging Face token, if a model repo asks you to accept its license |
| `JUPYTER_PASSWORD` | random | Jupyter token. If unset, a random one is written to `/workspace/logs/jupyter_token.txt` |
| `COMFYUI_ARGS` | — | Extra ComfyUI flags, e.g. `--reserve-vram 2` |
| `DOWNLOAD_FP16_VAE` | 0 | `1` also fetches the stock fp16 video VAE — fallback if the int8 VAE ever renders black |
| `SKIP_MODEL_DOWNLOAD` | 0 | `1` skips the download check at boot |

## Where things are on the pod

- Logs: `/workspace/logs/` (`models.log`, `comfyui.log`, `jupyter.log`)
- Outputs + Easy-Media projects (context latents for re-rendering a segment): `/workspace/output`
- Re-run the model download any time: `python /opt/template/download_models.py`

## GPU

The Singularity v2 int8 model is 34 GB and the text encoder 15.7 GB. A 48 GB+ card (RTX PRO 6000, L40S,
A6000) is comfortable; a 32 GB RTX 5090 works with ComfyUI's offloading like your local PC.
The nvfp4 text encoder is fastest on Blackwell (RTX 5090 / RTX PRO 6000 / B200).

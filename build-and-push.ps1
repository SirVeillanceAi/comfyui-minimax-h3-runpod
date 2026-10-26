# Build the image on your own PC with Docker Desktop and push it to Docker Hub.
# Usage (PowerShell, in this folder, Docker Desktop running):
#   docker login
#   .\build-and-push.ps1 -DockerHubUser yourname
# BuildJobs is no longer used (SageAttention now compiles on the pod).
param(
  [string]$DockerHubUser = "sirveillanceai",
  [string]$Tag = "latest",
  [int]$BuildJobs = 12
)

$image = "$DockerHubUser/comfyui-minimax-h3:$Tag"
docker build --build-arg BUILD_JOBS=$BuildJobs -t $image $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
docker push $image
if ($LASTEXITCODE -ne 0) { throw "docker push failed" }
Write-Host "Pushed $image"

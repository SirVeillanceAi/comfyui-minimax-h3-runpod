# Creates the RunPod template in your account from runpod-template.json.
# Usage (PowerShell, in this folder):
#   .\create-runpod-template.ps1 -DockerHubUser yourname -RunPodApiKey rpa_xxxxx
# Get an API key at runpod.io > Settings > API Keys (read/write).
param(
  [string]$DockerHubUser = "sirveillanceai",
  [Parameter(Mandatory = $true)][string]$RunPodApiKey
)

$body = Get-Content -Raw -Path "$PSScriptRoot\runpod-template.json"
$body = $body.Replace("YOUR_DOCKERHUB_USERNAME", $DockerHubUser)

$result = Invoke-RestMethod -Method Post -Uri "https://rest.runpod.io/v1/templates" `
  -Headers @{ Authorization = "Bearer $RunPodApiKey" } `
  -ContentType "application/json" -Body $body

Write-Host "Template created: $($result.name)  (id: $($result.id))  image: $($result.imageName)"

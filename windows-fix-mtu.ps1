#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

$tailscaleAdapter = Get-NetAdapter -Name 'Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $tailscaleAdapter) {
    throw "Aucune interface Tailscale detectee. Verifiez que Tailscale est installe et connecte."
}

$interfaceName = $tailscaleAdapter.Name
Write-Host "Configuration MTU de l'interface '$interfaceName' à 1280..."
netsh interface ipv4 set subinterface "$interfaceName" mtu=1280 store=persistent | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "La commande netsh a échoué lors de la configuration MTU."
}

Write-Host "Redémarrage du service Internet Connection Sharing (SharedAccess)..."
if (Get-Service -Name SharedAccess -ErrorAction SilentlyContinue) {
    Restart-Service -Name SharedAccess -Force
    Write-Host "Service SharedAccess redémarré."
} else {
    Write-Warning "Service SharedAccess introuvable sur ce système."
}

Write-Host "Terminé."

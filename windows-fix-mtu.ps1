#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

Write-Host "Configuration MTU de l'interface Tailscale à 1280..."
netsh interface ipv4 set subinterface "Tailscale" mtu=1280 store=persistent | Out-Null

Write-Host "Redémarrage du service Internet Connection Sharing (SharedAccess)..."
if (Get-Service -Name SharedAccess -ErrorAction SilentlyContinue) {
    Restart-Service -Name SharedAccess -Force
    Write-Host "Service SharedAccess redémarré."
} else {
    Write-Warning "Service SharedAccess introuvable sur ce système."
}

Write-Host "Terminé."

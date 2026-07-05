# SelfShield pour Windows 10/11 — installation sans rien acheter, sans app.
#
# Trois couches, appliquées par le SYSTÈME (aucun processus résident,
# 0 RAM/CPU/GPU dédiés, survit au redémarrage) :
#   1. Fichier hosts : ~45 000 domaines vers 0.0.0.0
#   2. DNS filtrant Cloudflare for Families (1.1.1.3), avec DoH natif
#      Windows 11 (chiffré, donc non trafiquable par une app locale)
#   3. Contrôle parental Microsoft Family Safety (optionnel, lien affiché)
#
# Usage (PowerShell en ADMINISTRATEUR) :
#   Set-ExecutionPolicy -Scope Process Bypass -Force
#   .\install-windows.ps1 install      # ou update / uninstall
param([string]$Action = "install")

$HostsUrl  = "https://raw.githubusercontent.com/EDN2025-hub/edn-anki/main/selflock/data/hosts_blocklist.txt"
$HostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$Begin     = "# >>> SelfShield begin >>>"
$End       = "# <<< SelfShield end <<<"
$LocalList = Join-Path $PSScriptRoot "..\data\hosts_blocklist.txt"

function Assert-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Lancer PowerShell en tant qu'administrateur."; exit 1
    }
}

function Get-List {
    $tmp = "$env:TEMP\selfshield_hosts.txt"
    try {
        Invoke-WebRequest -Uri $HostsUrl -OutFile $tmp -UseBasicParsing
        return $tmp
    } catch {
        if (Test-Path $LocalList) { return $LocalList }
        Write-Error "Liste introuvable (réseau + copie locale)."; exit 1
    }
}

function Remove-Block {
    $content = Get-Content $HostsFile -Raw -ErrorAction SilentlyContinue
    if ($content -match [regex]::Escape($Begin)) {
        $pattern = [regex]::Escape($Begin) + "[\s\S]*?" + [regex]::Escape($End)
        ($content -replace $pattern, "").TrimEnd() | Set-Content $HostsFile -Encoding ASCII
    }
}

function Install-Hosts {
    Copy-Item $HostsFile "$HostsFile.selfshield.bak" -Force
    Remove-Block
    $list = Get-Content (Get-List)
    Add-Content $HostsFile -Value $Begin -Encoding ASCII
    Add-Content $HostsFile -Value $list -Encoding ASCII
    Add-Content $HostsFile -Value $End -Encoding ASCII
    Clear-DnsClientCache
    Write-Host "hosts: $((($list | Where-Object { $_ -match '^0\.0\.0\.0' })).Count) entrées installées."
}

function Install-Dns {
    # DoH Cloudflare for Families sur toutes les interfaces actives
    Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses "1.1.1.3","1.0.0.3"
    }
    foreach ($ip in "1.1.1.3","1.0.0.3") {
        try {
            Add-DnsClientDohServerAddress -ServerAddress $ip `
                -DohTemplate "https://family.cloudflare-dns.com/dns-query" `
                -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Host "DNS: Cloudflare for Families (1.1.1.3, DoH) appliqué."
}

function Uninstall-All {
    Remove-Block
    Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses
    }
    Clear-DnsClientCache
    Write-Host "SelfShield retiré."
}

Assert-Admin
switch ($Action) {
    "install"   { Install-Hosts; Install-Dns
        Write-Host @"

À FAIRE MANUELLEMENT (verrouillage fort) :
 1. Utiliser au quotidien un compte Windows NON-administrateur :
    sans droits admin, impossible de modifier hosts ou le DNS.
    Le mot de passe du compte admin peut être détenu par une personne
    de confiance.
 2. Optionnel : Microsoft Family Safety (https://family.microsoft.com)
    pour le filtrage web Edge + limites d'apps, géré à distance par la
    personne de confiance.
 3. Relancer ce script avec 'update' de temps en temps pour rafraîchir
    la liste (ou créer une tâche planifiée hebdomadaire).
"@ }
    "update"    { Install-Hosts }
    "uninstall" { Uninstall-All }
    default     { Write-Host "Usage: .\install-windows.ps1 {install|update|uninstall}" }
}

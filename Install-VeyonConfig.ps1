<#
.SYNOPSIS
    Root wrapper for Veyon Auto-Configuration installer.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Master', 'Slave')]
    [string]$Role,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$targetScript = Join-Path -Path $PSScriptRoot -ChildPath "config\Install-VeyonConfig.ps1"
if (-not (Test-Path -Path $targetScript)) {
    Write-Error "Installer script not found at: $targetScript"
    exit 1
}

& powershell.exe -ExecutionPolicy Bypass -File $targetScript -Role $Role @RemainingArgs
exit $LASTEXITCODE

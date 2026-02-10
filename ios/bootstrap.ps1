Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$envFile = Join-Path $PSScriptRoot ".env.local"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_.StartsWith('#')) { return }
        $parts = $_.Split('=', 2)
        if ($parts.Length -eq 2) {
            [System.Environment]::SetEnvironmentVariable($parts[0], $parts[1])
        }
    }
}

xcodegen generate
Write-Host 'Generated YamabikoChat.xcodeproj'

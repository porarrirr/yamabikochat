Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot
xcodegen generate
Write-Host 'Generated YamabikoChat.xcodeproj'
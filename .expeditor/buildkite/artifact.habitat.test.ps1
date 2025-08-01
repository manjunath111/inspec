#!/usr/bin/env powershell

#Requires -Version 5
# https://stackoverflow.com/questions/9948517
# TODO: Set-StrictMode -Version Latest
$PSDefaultParameterValues['*:ErrorAction']='Stop'
$ErrorActionPreference = 'Stop'
$env:CHEF_LICENSE = 'accept-no-persist'
$env:HAB_LICENSE = 'accept-no-persist'
$Plan = 'inspec'

Write-Host "--- system details"
$Properties = 'Caption', 'CSName', 'Version', 'BuildType', 'OSArchitecture'
Get-CimInstance Win32_OperatingSystem | Select-Object $Properties | Format-Table -AutoSize

Write-Host "--- Installing the version of Habitat required"

function Stop-HabProcess {
  $habProcess = Get-Process hab -ErrorAction SilentlyContinue
  if ($habProcess) {
      Write-Host "Stopping hab process..."
      Stop-Process -Name hab -Force
  }
}

function Install-Habitat {
  Write-Host "Downloading and installing Habitat..."
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/main/components/hab/install.ps1'))
}

try {
  hab --version
}
catch {
  Set-ExecutionPolicy Bypass -Scope Process -Force

  Stop-HabProcess

  # Remove the existing hab.exe if it exists and if you have permissions
  $habPath = "C:\ProgramData\Habitat\hab.exe"
  if (Test-Path $habPath) {
      Write-Host "Attempting to remove existing hab.exe..."
      Remove-Item $habPath -Force -ErrorAction SilentlyContinue
      if (Test-Path $habPath) {
          Write-Host "Failed to remove hab.exe, re-running script with elevated permissions."
          Start-Process powershell -Verb runAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
          exit
      }
  }

  Install-Habitat
}
finally {
  Write-Host ":habicat: I think I have the version I need to build."
}

# Set HAB_ORIGIN after Habitat installation
Write-Host "HAB_ORIGIN set to 'ci' after installation."
$env:HAB_ORIGIN = 'ci'


Write-Host "--- Generating fake origin key"
hab origin key generate $env:HAB_ORIGIN

Write-Host "--- Building $Plan"
$project_root = "$(git rev-parse --show-toplevel)"
Set-Location $project_root

$env:DO_CHECK=$true; hab pkg build .

. $project_root/results/last_build.ps1

Write-Host "--- Installing $pkg_ident/$pkg_artifact"
hab pkg install -b $project_root/results/$pkg_artifact

Write-Host "--- Downloading Ruby + DevKit"
aws s3 cp s3://core-buildkite-cache-chef-prod/rubyinstaller-devkit-2.6.6-1-x64.exe c:/rubyinstaller-devkit-2.6.6-1-x64.exe

Write-Host "--- Installing Ruby + DevKit"
Start-Process c:\rubyinstaller-devkit-2.6.6-1-x64.exe -ArgumentList '/verysilent /dir=C:\\ruby26' -Wait

Write-Host "--- Cleaning up installation"
Remove-Item c:\rubyinstaller-devkit-2.6.6-1-x64.exe -Force

$Env:Path += ";C:\ruby26\bin;C:\hab\bin"

Write-Host "+++ Testing $Plan"

Push-Location $project_root/test/artifact
rake
If ($lastexitcode -ne 0) { Exit $lastexitcode }

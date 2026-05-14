# This file is part of MagiskOnWSALocal.
#
# MagiskOnWSALocal is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# MagiskOnWSALocal is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with MagiskOnWSALocal.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright (C) 2024 LSPosed Contributors
#

$Host.UI.RawUI.WindowTitle = "Installing MagiskOnWSA...."
function Test-Administrator {
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}

function Get-InstalledDependencyVersion {
    param (
        [string]$Name,
        [string]$ProcessorArchitecture
    )
    PROCESS {
        If ($null -Ne $ProcessorArchitecture) {
            return Get-AppxPackage -Name $Name | ForEach-Object { if ($_.Architecture -Eq $ProcessorArchitecture) { $_ } } | Sort-Object -Property Version | Select-Object -ExpandProperty Version -Last 1;
        }
    }
}

Function Check-Windows11 {
    try {
        return (Get-ComputerInfo -Property OsName).OsName -match "Windows 11"
    } catch {
        return $false
    }
}

Function Test-CommandExist {
    Param ($Command)
    $OldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try { if (Get-Command $Command) { RETURN $true } }
    Catch { RETURN $false }
    Finally { $ErrorActionPreference = $OldPreference }
} #end function Test-CommandExist

Function Finish {
    Clear-Host
    Start-Process "wsa://com.topjohnwu.magisk" -ErrorAction SilentlyContinue
    Start-Process "wsa://com.android.vending" -ErrorAction SilentlyContinue
}

If ((Check-Windows11) -And (Test-CommandExist 'pwsh.exe')) {
    $pwsh = "pwsh.exe"
} Else {
    $pwsh = "powershell.exe"
}

If (-Not (Test-Administrator)) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    $Proc = Start-Process -PassThru -Verb RunAs $pwsh -Args "-ExecutionPolicy Bypass -Command Set-Location '$PSScriptRoot'; &'$PSCommandPath' EVAL"
    If ($null -Ne $Proc) {
        $Proc.WaitForExit()
        exit $Proc.ExitCode
    }
    If ($null -Eq $Proc -Or $Proc.ExitCode -Ne 0) {
        Write-Warning "Failed to launch start as Administrator`r`nPress any key to exit"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    }
    exit 1
}
ElseIf (($args.Count -Eq 1) -And ($args[0] -Eq "EVAL")) {
    $Proc = Start-Process -PassThru $pwsh -NoNewWindow -Args "-ExecutionPolicy Bypass -Command Set-Location '$PSScriptRoot'; &'$PSCommandPath'"
    $Proc.WaitForExit()
    exit $Proc.ExitCode
}

$FileList = Get-Content -Path .\filelist.txt
$MissingFiles = $FileList | Where-Object { -Not (Test-Path -Path $_) }
If ($MissingFiles) {
    Write-Error "Some files are missing in the folder: $($MissingFiles -join ', '). Please try to build again. Press any key to exit"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

# Robust discovery of makepri.exe
$MakePriExe = "makepri.exe"
if (-Not (Test-Path -Path $MakePriExe)) {
    $PossiblePaths = @(
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\makepri.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\arm64\makepri.exe",
        "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\makepri.exe"
    )
    foreach ($Path in $PossiblePaths) {
        if (Test-Path -Path $Path) {
            $MakePriExe = $Path
            break
        }
    }
}

If ((Test-Path -Path "MakePri.ps1") -And ((Test-Path -Path $MakePriExe) -Or (Test-CommandExist $MakePriExe))) {
    Write-Output "Running MakePri.ps1 to merge resources..."
    $ProcMakePri = Start-Process $pwsh -PassThru -NoNewWindow -Args "-ExecutionPolicy Bypass -File MakePri.ps1" -WorkingDirectory $PSScriptRoot
    $ProcMakePri.WaitForExit()
    If ($ProcMakePri.ExitCode -Ne 0) {
        Write-Warning "Failed to merge resources, WSA Settings will always be in English`r`nPress any key to continue"
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    $Host.UI.RawUI.WindowTitle = "Installing MagiskOnWSA...."
}

reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1" | Out-Null

# When using PowerShell which is installed with MSIX
# Get-WindowsOptionalFeature and Enable-WindowsOptionalFeature will fail
# See https://github.com/PowerShell/PowerShell/issues/13866
if ($PSHOME.contains("8wekyb3d8bbwe")) {
    Import-Module DISM -UseWindowsPowerShell
}

If ($(Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform').State -Ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -NoRestart -FeatureName 'VirtualMachinePlatform'
    Write-Warning "Need restart to enable virtual machine platform`r`nPress y to restart or press any key to exit"
    $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -Eq $Key.Character) {
        Restart-Computer -Confirm
    }
    Else {
        exit 1
    }
}

[xml]$Xml = Get-Content ".\AppxManifest.xml";
$Name = $Xml.Package.Identity.Name;
Write-Output "Installing $Name version: $($Xml.Package.Identity.Version)"
$ProcessorArchitecture = $Xml.Package.Identity.ProcessorArchitecture;
$Dependencies = $Xml.Package.Dependencies.PackageDependency;
$Dependencies | ForEach-Object {
    $InstalledVersion = Get-InstalledDependencyVersion -Name $_.Name -ProcessorArchitecture $ProcessorArchitecture;
    If ( $InstalledVersion -Lt $_.MinVersion ) {
        if (Test-Path -Path "$($_.Name)_$ProcessorArchitecture.appx") {
            Write-Output "Dependency package $($_.Name) $ProcessorArchitecture required minimum version: $($_.MinVersion). Installing...."
            Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Path "$($_.Name)_$ProcessorArchitecture.appx"
        } else {
            Write-Warning "Dependency package $($_.Name) $ProcessorArchitecture required but installer not found."
        }
    }
    Else {
        Write-Output "Dependency package $($_.Name) $ProcessorArchitecture current version: $InstalledVersion. Nothing to do."
    }
}

$Installed = Get-AppxPackage -Name $Name

If (($null -Ne $Installed) -And (-Not ($Installed.IsDevelopmentMode))) {
    Write-Warning "There is already one installed WSA. Please uninstall it first.`r`nPress y to uninstall existing WSA or press any key to exit"
    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    If ("y" -Eq $key.Character) {
        Clear-Host
        Remove-AppxPackage -Package $Installed.PackageFullName
    }
    Else {
        exit 1
    }
}

If (Test-CommandExist WsaClient) {
    Write-Output "Shutting down WSA...."
    Start-Process WsaClient -Wait -Args "/shutdown" -ErrorAction SilentlyContinue
}
Stop-Process -Name "WsaClient" -ErrorAction SilentlyContinue
Write-Output "Installing MagiskOnWSA...."
Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\AppxManifest.xml
If ($?) {
    Finish
}
ElseIf ($null -Ne $Installed) {
    Write-Error "Failed to update.`r`nPress any key to uninstall existing installation while preserving user data.`r`nTake in mind that this will remove the Android apps' icon from the start menu.`r`nIf you want to cancel, close this window now."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Clear-Host
    Remove-AppxPackage -PreserveApplicationData -Package $Installed.PackageFullName
    Add-AppxPackage -ForceApplicationShutdown -ForceUpdateFromAnyVersion -Register .\AppxManifest.xml
    If ($?) {
        Finish
    }
}
Write-Output "All Done!`r`nPress any key to exit"
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

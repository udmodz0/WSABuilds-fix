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
# Copyright (C) 2023 LSPosed Contributors
#

$Host.UI.RawUI.WindowTitle = "Merging resources...."
If ((Test-Path -Path "pri") -And (Test-Path -Path "xml")) {
    $AppxManifestFile = ".\AppxManifest.xml"
    if (Test-Path -Path ".\resources.pri") {
        Copy-Item .\resources.pri -Destination ".\pri\resources.pri" -Force | Out-Null
    }
    
    $ProcNew = Start-Process -PassThru makepri.exe -NoNewWindow -Args "new /pr .\pri /cf .\xml\priconfig.xml /of .\resources.pri /mn $AppxManifestFile /o"
    $null = $ProcNew.Handle
    $ProcNew.WaitForExit()
    
    If ($ProcNew.ExitCode -Ne 0) {
        Write-Warning "Failed to merge resources from pris. Trying to dump pris to priinfo...."
        if (-Not (Test-Path -Path "priinfo")) {
            New-Item -Path "." -Name "priinfo" -ItemType "directory" | Out-Null
        }
        Clear-Host
        $i = 0
        $PriItem = Get-Item ".\pri\*" -Include "*.pri"
        Write-Output "Dumping resources...."
        $Processes = New-Object System.Collections.Generic.List[System.Diagnostics.Process]
        ForEach ($Item in $PriItem) {
            $Proc = Start-Process -PassThru -WindowStyle Hidden makepri.exe -Args "dump /if $($Item | Resolve-Path -Relative) /o /es .\pri\resources.pri /of .\priinfo\$($Item.Name).xml /dt detailed"
            $Processes.Add($Proc)
            $i = $i + 1
            $Completed = ($i / $PriItem.count) * 100
            Write-Progress -Activity "Dumping resources" -Status "Dumping $($Item.Name):" -PercentComplete $Completed
        }
        
        foreach ($Proc in $Processes) {
            $Proc.WaitForExit()
        }
        
        Write-Progress -Activity "Dumping resources" -Status "Ready" -Completed
        Clear-Host
        Write-Output "Creating pri from dumps...."
        $ProcNewFromDump = Start-Process -PassThru -NoNewWindow makepri.exe -Args "new /pr .\priinfo /cf .\xml\priconfig.xml /of .\resources.pri /mn $AppxManifestFile /o"
        $null = $ProcNewFromDump.Handle
        $ProcNewFromDump.WaitForExit()
        
        if (Test-Path -Path 'priinfo') {
            Remove-Item 'priinfo' -Recurse -Force
        }
        
        If ($ProcNewFromDump.ExitCode -Ne 0) {
            Write-Error "Failed to create resources from priinfos"
            exit 1
        }
    }

    $ProjectXml = [xml](Get-Content $AppxManifestFile)
    $ProjectResources = $ProjectXml.Package.Resources
    
    # Keep track of existing resources to avoid duplicates
    $ExistingResources = @()
    if ($ProjectResources.Resource) {
        foreach ($Res in $ProjectResources.Resource) {
            $ExistingResources += $Res.OuterXml
        }
    }

    $(Get-Item .\xml\* -Exclude "priconfig.xml" -Include "*.xml") | ForEach-Object {
        $ExtraXml = [xml](Get-Content $_)
        if ($ExtraXml.Package.Resources.Resource) {
            foreach ($Res in $ExtraXml.Package.Resources.Resource) {
                if ($ExistingResources -notcontains $Res.OuterXml) {
                    $ProjectResources.AppendChild($ProjectXml.ImportNode($Res, $true)) | Out-Null
                    $ExistingResources += $Res.OuterXml
                }
            }
        }
    }
    $ProjectXml.Save($AppxManifestFile)
    
    # Cleanup only temporary directories, keep the scripts and makepri.exe for potential re-runs or debugging
    if (Test-Path -Path 'pri') {
        Remove-Item 'pri' -Recurse -Force
    }
    if (Test-Path -Path 'xml') {
        Remove-Item 'xml' -Recurse -Force
    }
    
    # Update filelist.txt if it exists
    if (Test-Path -Path "filelist.txt") {
        $FileList = Get-Content -Path "filelist.txt"
        $NewFileList = $FileList | Where-Object { $_ -notmatch '^pri$' -and $_ -notmatch '^xml$' }
        Set-Content -Path "filelist.txt" -Value $NewFileList
    }
    
    exit 0
}

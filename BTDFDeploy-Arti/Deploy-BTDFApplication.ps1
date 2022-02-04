﻿[cmdletBinding()]
param(
    [Parameter(Mandatory=$false,HelpMessage="Leave blank to skip EnvironmentSettings export.")]
    [string]$Environment,

    [Parameter(Mandatory=$true,HelpMessage="In which order to run applications. String will match if it exists in name of artifact. Seperated by "","" (No spaces!). Runs left to right. Case sensetive.")]
	[string]$RunOrder,

    [Parameter(Mandatory=$true,HelpMessage="Path to the directory where the product is installed. EX: C:\Program Files (x86)")]
	[string]$Destination,

    [Parameter(Mandatory=$false,HelpMessage="Name of the cluster controlling bztalk. (Leave empty if target is not in cluster)")]
	[string]$ClusterName,

    [Parameter(Mandatory=$true,HelpMessage="Should this run on the last node? (False = Run on all nodes not running biztalk in the cluster, True = Run on all nodes with a active biztalk service.)")]
	[string]$ShouldRunOnLastNode='true',

    [string]$BTDeployMgmtDB='true',
    [string]$SkipUndeploy='true'
)
. "$PSScriptRoot\Init-BTDFTasks.ps1"


function IsLastNode {
	if([string]::IsNullOrEmpty($ClusterName)){
        Write-Host "Returned true no clustername";
		return $true # This can be redone since this requires ShouldRunOnLastNode to be true
	}
	$OwnerNode = (Get-ClusterGroup -Name $ClusterName).OwnerNode
	Write-Host $env:computername
	Write-Host $OwnerNode
	if($OwnerNode -eq $env:computername){
        Write-Host "Returned true islastnode";
		return $true
	}
    Write-Host "Returned false islastnode";
	return $false
}

$RunOrderArray = $RunOrder.split(",")
# "Shared", "INT", "LAB", "TEST"

$IsLastNodeVal = IsLastNode();
[System.Convert]::ToBoolean($ShouldRunOnLastNode);
[System.Convert]::ToBoolean($IsLastNodeVal);
Write-Host $IsLastNodeVal;
Write-Host $ShouldRunOnLastNode;
if($IsLastNodeVal -eq $ShouldRunOnLastNode){
    $path = "$Env:AGENT_RELEASEDIRECTORY";

    $files = Get-ChildItem $path;

    for(($i = 0); $i -lt $RunOrderArray.count; $i++){

        $CurrentWord = $RunOrderArray[$i];

        foreach ($Name in $files){

            if($Name -Match $CurrentWord){
                $ApplicationPath = Join-Path $Destination $Name
                Write-Host "Name: $Name, Environment: $Environment, Destination: $Destination, BTDeployMgmtDB: $BTDeployMgmtDB" 

                if (Test-Path -Path $ApplicationPath -ErrorAction SilentlyContinue) {
                    if ($Environment)
                    {
                        $EnvironmentSettingsPath = Get-ChildItem -Path $ApplicationPath -Recurse -Filter 'EnvironmentSettings' | Select-Object -ExpandProperty FullName -First 1
                        $EnvironmentSettings = Join-Path $EnvironmentSettingsPath $Environment
                        if ($Environment -notmatch '\.xml') {
                            # This offers backwards compatibility for existing tasks which are set to the environment name, not the full file name.
                            $EnvironmentSettings = "$($EnvironmentSettings)_settings.xml"
                        }
                        if (!(Test-Path -Path $EnvironmentSettings)) {
                            $DeploymentToolsPath = Get-ChildItem -Path $ApplicationPath -Recurse -Filter 'DeployTools' | Select-Object -ExpandProperty FullName -First 1
                            $esxargs = [string[]]@(
                                "`"$EnvironmentSettingsPath\\SettingsFileGenerator.xml`""
                                "`"$EnvironmentSettingsPath`""
                            )
                            $exitCode = (Start-Process -FilePath "`"$DeploymentToolsPath\EnvironmentSettingsExporter.exe`"" -ArgumentList $esxargs -Wait -PassThru).ExitCode
                            if($exitCode -ne 0) {
                                Write-Host "##vso[task.logissue type=error;] Deploy-BTDFApplication Error while calling EnvironmentSettingsExporter, Exit Code: $exitCode"
                            }
                        }
                        Get-Item -Path $EnvironmentSettings -ErrorAction Stop | Out-Null
                    }

                    $BTDFMSBuild = Get-MSBuildPath
                    $BTDFProject = Get-ChildItem -Path $ApplicationPath -Filter '*.btdfproj' -Recurse | Select-Object -ExpandProperty FullName -First 1
                    $DeployResults = Get-ChildItem -Path $ApplicationPath -Filter 'DeployResults' -Recurse | Select-Object -ExpandProperty FullName -First 1
                    $DeployResults = Join-Path $DeployResults 'DeployResults.txt'

                    $arguments = [string[]]@(
                        "/l:FileLogger,Microsoft.Build.Engine;logfile=`"$DeployResults`""
                        '/p:Configuration=Server'
                        "/p:DeployBizTalkMgmtDB=$BTDeployMgmtDB"
                        "/p:ENV_SETTINGS=`"$EnvironmentSettings`""
                        "/p:SkipUndeploy=$SkipUndeploy"
                        '/target:Deploy'
                        "`"$BTDFProject`""
                    )
                    $cmd = $BTDFMSBuild,($arguments -join ' ') -join ' '
                    Write-Host $cmd
                    $exitCode = (Start-Process -FilePath $BTDFMSBuild -ArgumentList $arguments -NoNewWindow -Wait -PassThru).ExitCode
                    Write-Host (Get-Content -Path $DeployResults | Out-String)
                    if($exitCode -ne 0) {
                        Write-Host ("##vso[task.logissue type=error;] Deploy-BTDFApplication error while calling MSBuild, Exit Code: {0}" -f $exitCode)
                        Write-Host ("##vso[task.complete result=Failed;] Deploy-BTDFApplication error while calling MSBuild, Exit Code: {0}" -f $exitCode)
                    } else {
                        Write-Host "##vso[task.complete result=Succeeded;]DONE"
                    }
                } else {
                    Write-Host ("##vso[task.logissue type=error;] BTDF application '{0}' not found at {1}.  Deploy skipped." -f $Name,$ApplicationPath)
                    Write-Host ("##vso[task.complete result=Failed;] BTDF application '{0}' not found at {1}.  Deploy skipped." -f $Name,$ApplicationPath)
                }

            }
        }
    }
}
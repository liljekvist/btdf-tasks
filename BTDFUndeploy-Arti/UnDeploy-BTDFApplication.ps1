﻿[cmdletBinding()]
param(
    [Parameter(Mandatory=$true,HelpMessage="Path to the directory where the product is installed. EX: C:\Program Files (x86)")]
	[string]$Destination,

	[Parameter(Mandatory=$true,HelpMessage="In which order to run applications. String will match if it exists in name of artifact. Seperated by "","" (No spaces!). Runs left to right. Case sensetive.")]
	[string]$RunOrder,

	[Parameter(Mandatory=$true,HelpMessage="Should this run on the last node? (False = Run on all nodes not running biztalk in the cluster, True = Run on all nodes with a active biztalk service.)")]
	[string]$ShouldRunOnLastNode='false',

	[Parameter(Mandatory=$false,HelpMessage="Name of the cluster controlling bztalk. (Leave empty if target is not in cluster and set ShouldRunOnLastNode to true. This will make it run.)")]
	[string]$ClusterName,

	[string]$BTDeployMgmtDB=$true
)
. "$PSScriptRoot\Init-BTDFTasks.ps1"

 # "TEST", "LAB", "INT", "Shared"
# create an array from an arbitrary separator, in this case a space
$RunOrderArray = $RunOrder.split(",")
$Name = '' # Initar den tidigt då jag inte vet hur funktionen får med den.


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

function Test-BTDFApplicationDeployed {
    param(
        [Parameter(ValueFromPipeline=$true)]
        [string[]]$Name
    )
    begin {
        #=== Make sure the ExplorerOM assembly is loaded ===#
        [void] [System.reflection.Assembly]::LoadWithPartialName("Microsoft.BizTalk.ExplorerOM")
        #=== Connect the BizTalk Management database ===#
        $Catalog = New-Object Microsoft.BizTalk.ExplorerOM.BtsCatalogExplorer
        $MgmtDBServer = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\BizTalk Server\3.0\Administration' | Select-Object -ExpandProperty 'MgmtDBServer'
        $MgmtDBName = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\BizTalk Server\3.0\Administration' | Select-Object -ExpandProperty 'MgmtDBName'
        $Catalog.ConnectionString = "SERVER=$MgmtDBServer;DATABASE=$MgmtDBName;Integrated Security=SSPI"
    }
    process {
        #=== Loop through applications in the catalog trying to find a name match ===#
        foreach($app in $Name) {
            $Catalog.Applications.Name -contains $app
        }
    }
}


$IsLastNodeVal = IsLastNode;
$ShouldRunOnLastNode = [System.Convert]::ToBoolean($ShouldRunOnLastNode);
$IsLastNodeVal = [System.Convert]::ToBoolean($IsLastNodeVal);
Write-Host "IsLastNodeVal: " + $IsLastNodeVal;
Write-Host "ShouldRunOnLastNode: " + $ShouldRunOnLastNode;

$t = [bool]$IsLastNodeVal -eq [bool]$ShouldRunOnLastNode;

Write-Host "Will run: $t";

if($t){
    Write-Host "Running on node " + $env:computername;

	$path = "$Env:AGENT_RELEASEDIRECTORY";

	$files = Get-ChildItem $path;
	for(($i = 0); $i -lt $RunOrderArray.count; $i++){

		$CurrentWord = $RunOrderArray[$i];
		Write-Host $CurrentWord;

		foreach ($Name in $files){

			if($Name -Match $CurrentWord){
				
				$ApplicationPath = Join-Path $Destination $Name
				Write-Host "Name: $Name, Destination: $Destination, BTDeployMgmtDB: $BTDeployMgmtDB" 


				## On the server whe MgmtDB must be undeployed, check if the application is installed. On the other servers, test if the path exists.
				if ($BTDeployMgmtDB -eq "true" -And -Not(Test-BTDFApplicationDeployed -Name $Name))
				{
					Write-Host ("##vso[task.logissue type=warning;] BTDF application '{0}' not in catalog.  Undeploy skipped." -f $Name)
				}
				else
				{
					if (Test-Path -Path $ApplicationPath -ErrorAction SilentlyContinue) {
						$BTDFProject = Get-ChildItem -Path $ApplicationPath -Filter '*.btdfproj' -Recurse | Select-Object -ExpandProperty FullName -First 1
						$DeployResults = Get-ChildItem -Path $ApplicationPath -Filter 'DeployResults' -Recurse | Select-Object -ExpandProperty FullName -First 1
						if ($null -eq $DeployResults) {
							Write-Host ("##vso[task.logissue type=warning;] BTDF application '{0}' not found." -f $ApplicationPath)
						} else {
							$DeployResults = Join-Path $DeployResults 'DeployResults.txt'

							$BTDFMSBuild = Get-MSBuildPath
							$arguments = [string[]]@(
								"/l:FileLogger,Microsoft.Build.Engine;logfile=`"$DeployResults`""
								"/p:Configuration=Server"
								"/p:DeployBizTalkMgmtDB=$BTDeployMgmtDB"
								'/target:Undeploy'
								"""$BTDFProject"""
							)
							$cmd = $BTDFMSBuild,($arguments -join ' ') -join ' '
							Write-Host $cmd
							$exitCode = (Start-Process -FilePath "$BTDFMSBuild" -ArgumentList $arguments -Wait -PassThru).ExitCode
							Write-Host (Get-Content -Path $DeployResults | Out-String)

							if($exitCode -ne 0) {
								Write-Host "##vso[task.logissue type=error;] Error while calling MSBuild, Exit Code: $exitCode"
								Write-Host ("##vso[task.complete result=Failed;] Undeploy-BTDFApplication error while calling MSBuild, Exit Code: {0}" -f $exitCode)
							} else {
								Write-Host "##vso[task.complete result=Succeeded;]DONE"
							}
						}
					} else {
						Write-Host ("##vso[task.logissue type=warning;] BTDF application '{0}' not found at {1}.  Undeploy skipped." -f $Name,$ApplicationPath)
					}
				}
			}

			else {
				Write-Host "Not a match!";
			}
		}
	}
}

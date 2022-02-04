param(
    [Parameter(HelpMessage="Additional msiexec.exe command line arguments")]
    [string]$Arguments,

    [Parameter(Mandatory=$true,HelpMessage="Should this run on the last node? (False = Run on all nodes not running biztalk in the cluster, True = Run on all nodes with a active biztalk service.)")]
	[string]$ShouldRunOnLastNode='false',

	[Parameter(Mandatory=$false,HelpMessage="Name of the cluster controlling bztalk. (Leave empty if target is not in cluster and set ShouldRunOnLastNode to true. This will make it run.)")]
	[string]$ClusterName
)
. "$PSScriptRoot\Init-BTDFTasks.ps1"
. "$PSScriptRoot\Get-MSIFileInformation.ps1"


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

$path = "$Env:AGENT_RELEASEDIRECTORY";

$files = Get-ChildItem $path;
$IsLastNodeVal = IsLastNode;
[System.Convert]::ToBoolean($ShouldRunOnLastNode);
[System.Convert]::ToBoolean($IsLastNodeVal);
Write-Host $IsLastNodeVal;
Write-Host $ShouldRunOnLastNode;
if($IsLastNodeVal -eq $ShouldRunOnLastNode){
    foreach ($Product in $files){

        $InstallGuid = [Guid]::Empty

        if (-not [Guid]::TryParse($Product, [ref] $InstallGuid)) {
            if (Test-Path -Path "$Product" -ErrorAction SilentlyContinue) {
                $MSI = Get-Item -Path "$Product" -ErrorAction Stop
                $FoundMSIGuid = Get-MSIFileInformation -Path "$MSI" -Property "ProductCode"
                if (-not [Guid]::TryParse($FoundMSIGuid, [ref] $InstallGuid)) {
                    $Name = [Regex]::Match($MSI.BaseName,'^(\.?[a-zA-Z]+)*').Value
                }
            } else {
                $Name = "$Product"
            }

            if([Guid]::Empty -eq $InstallGuid) {
                $InstallGuid = Get-ChildItem $UninstallPath | Where-Object { ( $_ | Get-ItemProperty -Name DisplayName -ErrorAction SilentlyContinue).DisplayName -eq "$Name" } | Select-Object -ExpandProperty PSChildName
                if ($null -eq $InstallGuid) {
                    Write-Host ("##vso[task.logissue type=warning;] Product not found [{0}]" -f $Name)
                }
            }
        }

        $msiexec = 'msiexec.exe'
        $argu = [string[]]@(
            "/x {0:B}"  -f $InstallGuid
            "/qn"
        )
        if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $argu += $Arguments -split ' '
        }

        Write-Host ('msiexec.exe',($argu -join ' ') -join ' ')
        Start-Process -FilePath $msiexec -ArgumentList $argu -NoNewWindow -Wait
    }
}
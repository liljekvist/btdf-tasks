param(
    [Parameter(Mandatory=$true,HelpMessage="Path to the directory where the product is installed. EX: C:\Program Files (x86)")]
	[string]$Destination,

    [Parameter(HelpMessage="msiexec.exe command line arguments")]
    [string]$Arguments,

    [Parameter(Mandatory=$true,HelpMessage="Should this run on the last node? (False = Run on all nodes not running biztalk in the cluster, True = Run on all nodes with a active biztalk service.)")]
	[string]$ShouldRunOnLastNode='false',

	[Parameter(Mandatory=$false,HelpMessage="Name of the cluster controlling bztalk. (Leave empty if target is not in cluster and set ShouldRunOnLastNode to true. This will make it run.)")]
	[string]$ClusterName
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

$path = "$Env:AGENT_RELEASEDIRECTORY";

$files = Get-ChildItem $path;

$staticDest = $Destination
$IsLastNodeVal = IsLastNode;
$ShouldRunOnLastNode2 = [System.Convert]::ToBoolean($ShouldRunOnLastNode);
$IsLastNodeVal2 = [System.Convert]::ToBoolean($IsLastNodeVal);
Write-Host "IsLastNodeVal: " + $IsLastNodeVal2;
Write-Host "ShouldRunOnLastNode: " + $ShouldRunOnLastNode2;

if($IsLastNodeVal2.equals($ShouldRunOnLastNode2)){
    Write-Host "Running on node " + $env:computername;
    foreach ($Name in $files){

        $Destination = $staticDest
        $PathToMsi = "$Env:AGENT_RELEASEDIRECTORY\" + $Name + "\msi\*.msi"

        $MSI = Get-Item -Path $PathToMsi -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Destination)) {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                $Name = [Regex]::Match($MSI.BaseName,'^(\.?[a-zA-Z]+)*').Value
            }
            $Destination = Join-Path $ProgramFiles $Name
        }

        $msiexec = 'msiexec.exe'
        $argu = [string[]]@(
            '/i "{0}"' -f $MSI.FullName
            "/qn"
        )
        $Destination = Join-Path $Destination $Name
        if (-not [string]::IsNullOrWhiteSpace($Destination)) {
            $argu += "INSTALLDIR=""$Destination"""
        }
        if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
            $argu += $Arguments -split ' '
        }
        Write-Host $Version

        Write-Host $Destination

        Write-Host ('msiexec.exe',($argu -join ' ') -join ' ')
        Start-Process -FilePath $msiexec -ArgumentList $argu -NoNewWindow -Wait
    }
}

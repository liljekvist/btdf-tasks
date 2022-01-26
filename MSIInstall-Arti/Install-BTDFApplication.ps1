param(
    [Parameter(Mandatory=$true,HelpMessage="Path to the directory where the product is installed. EX: C:\Program Files (x86)")]
	[string]$Destination,

    [Parameter(HelpMessage="msiexec.exe command line arguments")]
    [string]$Arguments
)
. "$PSScriptRoot\Init-BTDFTasks.ps1"

$path = "$Env:AGENT_RELEASEDIRECTORY";

$files = Get-ChildItem $path;

foreach ($Name in $files){

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
    $Destination = Join-Path $ProgramFiles $Name
    if (-not [string]::IsNullOrWhiteSpace($Destination)) {
        $argu += "INSTALLDIR=""$Destination"""
    }
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        $argu += $Arguments -split ' '
    }

    Write-Host ('msiexec.exe',($argu -join ' ') -join ' ')
    Start-Process -FilePath $msiexec -ArgumentList $argu -NoNewWindow -Wait
}
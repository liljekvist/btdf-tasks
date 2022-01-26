param(
    [Parameter(HelpMessage="Additional msiexec.exe command line arguments")]
    [string]$Arguments
)
. "$PSScriptRoot\Init-BTDFTasks.ps1"
. "$PSScriptRoot\Get-MSIFileInformation.ps1"

$path = "$Env:AGENT_RELEASEDIRECTORY";

$files = Get-ChildItem $path;

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

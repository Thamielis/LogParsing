
[CmdletBinding()]
param (
    [Parameter()]
    [String] $ComputerName = "LP532"
)

Import-Module "$PSScriptRoot\LogParsing.psd1" -Force

if (Test-Path -Path .\variablelibrary.json) {
    $CMLogVars = (Get-Content -Path .\variablelibrary.json -Raw | ConvertFrom-Json -Depth 20).Logs
}

$CMLogResults = [Ordered]@{}
$CMLogErrors = [Ordered]@{}

foreach ($CMLog in $CMLogVars.PSObject.Members | Where-Object MemberType -like 'NoteProperty') {
    $LogName = $CMLog.Name
    $LogFileName = $CMLogVars.$LogName.Filename
    $LogFilePath = $CMLogVars.$LogName.Filepath
    $LogFile = Join-Path -Path "\\$ComputerName\c$" -ChildPath $LogFilePath -AdditionalChildPath $LogFileName

    $LogResults = Get-Log -File $LogFile -AllDetails | Sort-Object -Property DateTime -Descending

    $Errors = [PSCustomObject]$LogResults | Where-Object { $_.severity -eq 'Error' } #| Sort-Object -Property DateTime

    $CMLogResult = [Ordered]@{
        All         = $LogResults #| Sort-Object -Property DateTime -Descending
        Normal      = [PSCustomObject]$LogResults | Where-Object { $_.severity -eq 'normal' } #| Sort-Object -Property DateTime -Descending
        Information = [PSCustomObject]$LogResults | Where-Object { $_.severity -eq 'information' }  #| Sort-Object -Property DateTime -Descending
        Warnings    = [PSCustomObject]$LogResults | Where-Object { $_.severity -eq 'Warning' }  #| Sort-Object -Property DateTime -Descending
        Errors      = $Errors
    }

    if ($null -ne $Errors) {
        $CMLogErrors[$LogName] = $Errors | Sort-Object -Property Message -Unique
    }
    
    $CMLogResults[$LogName] = $CMLogResult #[PSCustomObject]$LogResults
}



Start-Sleep -Seconds 1

###################################################################################

$CMSetupLogPath = "C:\Windows\ccmsetup\Logs"
$CMSetupLogFile = "ccmsetup.log"
$CMEvalLogFile = "ccmsetup-ccmeval.log"

$CMSetupLog = Join-Path -Path $CMSetupLogPath -ChildPath $CMSetupLogFile
$CMEvalLog = Join-Path -Path $CMSetupLogPath -ChildPath $CMEvalLogFile

#if (-not(Get-Module -Name 'LogParsing' -ListAvailable)) {
#    Install-Module -Name 'LogParsing'
#}



$CMSetup = Get-Log -File $CMSetupLog -AllDetails
$CMEval = Get-Log -File $CMEvalLog -AllDetails

$CMSetupResult = [PSCustomObject]@{
    Normal      = $CMSetup | Where-Object { $_.severity -eq 'normal' } | Sort-Object -Property DateTime
    Information = $CMSetup | Where-Object { $_.severity -eq 'information' }  | Sort-Object -Property DateTime
    Errors      = $CMSetup | Where-Object { $_.severity -eq 'Error' }  | Sort-Object -Property DateTime
    Warnings    = $CMSetup | Where-Object { $_.severity -eq 'Warning' }  | Sort-Object -Property DateTime
}

$CMEvalResult = [PSCustomObject]@{
    Normal      = $CMEval | Where-Object { $_.severity -eq 'normal' } | Sort-Object -Property DateTime
    Information = $CMEval | Where-Object { $_.severity -eq 'information' }  | Sort-Object -Property DateTime
    Errors      = $CMEval | Where-Object { $_.severity -eq 'Error' }  | Sort-Object -Property DateTime
    Warnings    = $CMEval | Where-Object { $_.severity -eq 'Warning' }  | Sort-Object -Property DateTime
}

$CMLogs = [PSCustomObject]@{
    CMSetup = $CMSetupResult
    CMEval  = $CMEvalResult
}


Start-Sleep -Seconds 1


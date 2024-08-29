function Get-CMLog {
    <#
.SYNOPSIS
Parses logs for System Center Configuration Manager.
.DESCRIPTION
Accepts a single log file or array of log files and parses them into objects.  Shows both UTC and local time for troubleshooting across time zones.
.PARAMETER Path
Specifies the path to a log file or files.
.INPUTS
Path/FullName.  
.OUTPUTS
PSCustomObject.  
.EXAMPLE
C:\PS> Get-CMLog -Path Sample.log
Converts each log line in Sample.log into objects
UTCTime   : 7/15/2013 3:28:08 PM
LocalTime : 7/15/2013 2:28:08 PM
FileName  : sample.log
Component : TSPxe
Context   : 
Type      : 3
TID       : 1040
Reference : libsmsmessaging.cpp:9281
Message   : content location request failed
.EXAMPLE
C:\PS> Get-ChildItem -Path C:\Windows\CCM\Logs | Select-String -Pattern 'failed' | Select -Unique Path | Get-CMLog
Find all log files in folder, create a unique list of files containing the phrase 'failed, and convert the logs into objects
UTCTime   : 7/15/2013 3:28:08 PM
LocalTime : 7/15/2013 2:28:08 PM
FileName  : sample.log
Component : TSPxe
Context   : 
Type      : 3
TID       : 1040
Reference : libsmsmessaging.cpp:9281
Message   : content location request failed
.LINK
http://blog.richprescott.com
#>
    param(
        [Parameter(Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]
        $Path,
        $tail = 10
    )

    PROCESS {

        if (($Path -isnot [array]) -and (Test-Path -Path $Path -PathType Container) ) {
            $Path = Get-ChildItem "$Path\*.log"
        }
        
        foreach ($File in $Path) {

            if (!( Test-Path -Path $file )) {
                $Path += (Get-ChildItem "$file*.log").fullname
            }

            $FileName = Split-Path -Path $File -Leaf
            
            if ($tail) {
                $lines = Get-Content -Path $File -tail $tail 
            }
            else {
                $lines = Get-Content -path $file
            }
            
            ForEach ($l in $lines ) {
                $l -match '\<\!\[LOG\[(?<Message>.*)?\]LOG\]\!\>\<time=\"(?<Time>.+)(?<TZAdjust>[+|-])(?<TZOffset>\d{2,3})\"\s+date=\"(?<Date>.+)?\"\s+component=\"(?<Component>.+)?\"\s+context="(?<Context>.*)?\"\s+type=\"(?<Type>\d)?\"\s+thread=\"(?<TID>\d+)?\"\s+file=\"(?<Reference>.+)?\"\>' | Out-Null
                
                if ($matches) {
                    $UTCTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)$($matches.TZAdjust)$($matches.TZOffset/60)"), "MM-dd-yyyy HH:mm:ss.fffz", $null, "AdjustToUniversal")
                    $LocalTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)"), "MM-dd-yyyy HH:mm:ss.fff", $null)
                }

                [pscustomobject]@{
                    UTCTime   = $UTCTime
                    LocalTime = $LocalTime
                    FileName  = $FileName
                    Component = $matches.component
                    Context   = $matches.context
                    Type      = $matches.type
                    TID       = $matches.TI
                    Reference = $matches.reference
                    Message   = $matches.message
                }

            }
        }
    }
}

function Get-CCMLog {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        $ComputerName = $ENV:ComputerName,
        [Parameter(Position = 1)]
        $Path = 'C:\Windows\CCM\logs'
    )
    DynamicParam {
        $ParameterName = 'Log'

        if ($Path.ToCharArray() -contains ':') {

            $FilePath = "\\$($ComputerName)\$($path -replace ':','$')"
        }
        else {
            $FilePath = "\\$($ComputerName)\$((Get-Item $path).FullName -replace ':','$')"
        }
        
        $logs = Get-ChildItem "$FilePath\*.log"
        $LogNames = $logs.basename

        $logAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $logAttribute.Position = 2
        $logAttribute.Mandatory = $true
        $logAttribute.HelpMessage = 'Pick A log to parse'                

        #$logCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
        $logCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $logCollection.add($logAttribute)

        #$logValidateSet = New-Object System.Management.Automation.ValidateSetAttribute($LogNames)
        $logValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([String[]]$LogNames)
        #$LogNames | ForEach-Object {$logValidateSet.ValidValues.Add($_)}
        $logCollection.add($logValidateSet)

        #$logParam = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $logCollection)
        $logParam = [System.Management.Automation.RuntimeDefinedParameter]::new($ParameterName, [string], $logCollection)

        #$logDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
        $logDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $logDictionary.Add($ParameterName, $logParam)

        return $logDictionary
        
    }

    begin {
        # Bind the parameter to a friendly variable
        $Log = $PsBoundParameters[$ParameterName]
    }

    process {

        $sb2 = "$((Get-ChildItem function:Get-CMLog).Scriptblock)`r`n"
        $sb1 = [scriptblock]::Create($sb2)
        
        $Results = Invoke-Command -ComputerName $ComputerName -ScriptBlock $sb1 -ArgumentList "$Path\$Log.log"

        [PSCustomObject]@{"$($Log)Log" = $Results }

    }

}

$LogResults = Get-CCMLog -ComputerName 'LP732' -Path 'C:\Windows\CCM\logs'
$LogResults

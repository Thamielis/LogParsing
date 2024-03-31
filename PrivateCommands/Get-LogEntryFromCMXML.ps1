
Function Get-LogEntryFromCMXML { 
<#
.SYNOPSIS
Used to parse one of the Configmgr log file format. THis formate has an XML like attribute tag for each line. 

.DESCRIPTION
This format is specific to the Configmgr log format and pulls the XML like attributes on each line

.PARAMETER LogContent
the -raw log content that you want broken into different entries. 

.PARAMETER AllDetails
This creates a PSCustom object for all of the properties in the XML attributes tag for advanced usage.

.EXAMPLE
$LogSplat = @{
    AllDetails = $AllDetails.IsPresent
    LogContent = $LogContent
}
$logEntries = Get-LogEntryFromCMXML @LogSplat 

.LINK
http://www.JPScripter.com
#>
    param(
        [parameter(Mandatory=$true,ValueFromPipeline)]
        [string] $LogContent,
        [switch] $AllDetails
    )

    Begin{

        #$DateFormat = "ddd, dd MMM yyyy HH:mm:ss 'GMT'"
        $Culture = [System.Globalization.CultureInfo]::InvariantCulture
        $pattern = '<\!\[LOG\[(.*)]LOG]\!><(.*)>'

    }
    
    Process {

        # find new entries
        $LogMatches = [regex]::matches($LogContent,$pattern)
        #$logEntries = new-object -TypeName Collections.arraylist
        $logEntries = [System.Collections.ArrayList]::new()

        foreach($match in $LogMatches){
            $DetailRow = $match.groups[2].value.split(' ')
            $Loghash = @{}

            foreach ($detail in $DetailRow) {

                try {
                    $name = $detail.split('=')[0]
                    $value = $detail.split('=')[1] -replace '"',''

                    if ($name -eq 'date') {
                        $value = [datetime]::Parse($value, $Culture).Date.ToShortDateString()
                    }

                    $Loghash.add($name,$value)
                }
                Catch{
                    Write-warning -Message "$name duplicated for $file"
                }

            }

            #build entry
            #$entry = new-object logEntry
            $entry = [logEntry]::new()

            if ([string]::IsNullOrEmpty($match.groups[1].value)) {
                Continue
            }

            $entry.Message = $match.groups[1].value
            $entry.Component = $Loghash['component']
            $entry.thread = $Loghash['thread']

            $Detailshash = @{}

            if ($AllDetails.IsPresent){
                $DetailsHash += $Loghash
            }

            $DateTimeString = "$($Loghash['date']) $($Loghash['time'].split('.')[0])"
            #$datetime = 0
            #$Null = [datetime]::TryParse($DateTimeString, $Culture, [ref] $datetime)
            $datetime = [DateTime]::ParseExact($DateTimeString, "dd.MM.yyyy HH:mm:ss", $Culture)

            $entry.datetime = $datetime
            
            $entry.severity = Get-LogEntrySeverity -Message $match.groups[1].value

            if ($entry.severity -eq [severity]::Error){
                [int]$errorcode = Get-LogEntryErrorMessage -message $entry.Message

                if ($errorcode -eq 0 ){
                    Try {
                        $ErrorHash = @{
                            Errorcode    = $errorcode
                            ErrorMessage = [System.ComponentModel.Win32Exception]$errorcode
                        }

                        $DetailsHash += $ErrorHash

                    }
                    Catch {
                        Write-verbose -message "Could not convert $errorcode to error message:`n$($entry.Message)"
                    }
                }
            }

            $entry.details = [PSCustomObject]$DetailsHash
            $null = $logEntries.add($entry)
        }
    }
    End {
        $logEntries
    }
}

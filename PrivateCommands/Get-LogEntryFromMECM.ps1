

function Get-LogEntryFromMECM {
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline)]
        [string] $LogContent,
        [switch] $AllDetails
    )

    begin {
        $Pattern = '\<\!\[LOG\[(?<Message>.*)?\]LOG\]\!\>\<time=\"(?<Time>.+)(?<TZAdjust>[+|-])(?<TZOffset>\d{2,3})\"\s+date=\"(?<Date>.+)?\"\s+component=\"(?<Component>.+)?\"\s+context="(?<Context>.*)?\"\s+type=\"(?<Type>\d)?\"\s+thread=\"(?<TID>\d+)?\"\s+file=\"(?<Reference>.+)?\"\>'
        $logEntries = [System.Collections.ArrayList]::new()
    }

    process {

        $LogMatches = [regex]::matches($LogContent, $pattern)

        foreach ($l in $LogMatches) {
            $l.Value -match $Pattern | Out-Null

            if ($matches) {
                $UTCTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)$($matches.TZAdjust)$($matches.TZOffset/60)"), "MM-dd-yyyy HH:mm:ss.fffz", $null, "AdjustToUniversal")
                $LocalTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)"), "MM-dd-yyyy HH:mm:ss.fff", $null)
            }

            $LogHash = [PSCustomObject]@{
                UTCTime   = $UTCTime
                LocalTime = $LocalTime
                FileName  = $FileName
                Component = $matches.component
                Context   = $matches.context
                Type      = $matches.type
                TID       = $matches.TID
                Reference = $matches.reference
                Message   = $matches.message
                Error     = $null
            }

            $entry = [logEntry]::new()

            #$Detailshash = @{}

            if ($AllDetails.IsPresent) {
                $DetailsHash = $Loghash
            }

            $entry.DateTime = $LogHash.LocalTime
            $entry.Message = $LogHash.Message #$match.groups[1].value
            $entry.Component = $Loghash.Component
            $entry.thread = $Loghash.TID

            $entry.severity = Get-LogEntrySeverity -Message $LogHash.Message

            if ($entry.severity -eq [severity]::Error) {
                [int]$errorcode = Get-LogEntryErrorMessage -message $entry.Message

                if ($errorcode -eq 0 ) {
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

        <#
        $LogMatches = [regex]::matches($LogContent, $pattern)

        foreach ($matches in $LogMatches) {

            if ($matches) {
                $UTCTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)$($matches.TZAdjust)$($matches.TZOffset/60)"), "MM-dd-yyyy HH:mm:ss.fffz", $null, "AdjustToUniversal")
                $LocalTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)"), "MM-dd-yyyy HH:mm:ss.fff", $null)
            }

            $LogHash = [PSCustomObject]@{
                UTCTime   = [datetime]::ParseExact($("$($matches.date) $($matches.time)$($matches.TZAdjust)$($matches.TZOffset/60)"), "MM-dd-yyyy HH:mm:ss.fffz", $null, "AdjustToUniversal")
                LocalTime = [datetime]::ParseExact($("$($matches.date) $($matches.time)"), "MM-dd-yyyy HH:mm:ss.fff", $null)
                FileName  = $FileName
                Component = $matches.component
                Context   = $matches.context
                Type      = $matches.type
                TID       = $matches.TID
                Reference = $matches.reference
                Message   = $matches.message
            }

            $entry = [logEntry]::new()

            $Detailshash = @{}

            if ($AllDetails.IsPresent) {
                $DetailsHash += $Loghash
            }

            $entry.Message = $match.groups[1].value
            $entry.Component = $Loghash['component']
            $entry.thread = $Loghash['thread']

            $entry.details = [PSCustomObject]$DetailsHash
            $null = $logEntries.add($entry)

        }
        #>

    }

    end {
        $logEntries
    }

}

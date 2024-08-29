
function Read-HtmlTable {
    [CmdletBinding(DefaultParameterSetName = 'Html')]
    [OutputType([Object[]])] 
    param (
        [Parameter(ParameterSetName = 'Html', ValueFromPipeLine = $True, Mandatory = $True, Position = 0)]
        [String]$InputObject,
        [Parameter(ParameterSetName = 'Uri', ValueFromPipeLine = $True, Mandatory = $True)]
        [Uri]$Uri,
        [Object[]]$Header,
        [Int[]]$TableIndex,
        [String]$Separator = ' ',
        [String]$Delimiter = [System.Environment]::NewLine,
        [Switch]$NoTrim
    )

    Begin {

        function Invoke-ParseHtml {
            [CmdletBinding()]
            param (
                [Parameter()]
                $String
            )

            $Unicode = [System.Text.Encoding]::Unicode.GetBytes($String)
            $Html = New-Object -Com 'HTMLFile'

            if ($Html.PSObject.Methods.Name -Contains 'IHTMLDocument2_Write') { 
                $Html.IHTMLDocument2_Write($Unicode) 
            }
            else { 
                $Html.write($Unicode) 
            }
            
            $Html.Close()
            $Html
        }

        filter GetTopElement([String[]]$TagName) {
            if ($TagName -Contains $_.tagName) { 
                $_ 
            }
            else { 
                @($_.Children).Where{ $_ } | GetTopElement -TagName $TagName 
            }
        }

        function Get-TopElement {
            [CmdletBinding()]
            param (
                [Parameter()]
                [String[]]$TagName
            )

            if ($TagName -Contains $_.tagName) { 
                $_ 
            }
            else { 
                @($_.Children).Where{ $_ } | Get-TopElement -TagName $TagName 
            }
        }

        function Get-Unit {
            [CmdletBinding()]
            param (
                [Parameter()]
                $Data, 
                [int]$x, 
                [int]$y
            )

            if ($x -lt $Data.Count -and $y -lt $Data[$x].Count) { 
                $Data[$x][$y] 
            }
        }

        function Set-Unit {
            [CmdletBinding()]
            param (
                [Parameter()]
                $Data, 
                [int]$x, 
                [int]$y,
                [HashTable]$Unit
            )

            while ($x -ge $Data.Count) { $Data.Add([System.Collections.Generic.List[HashTable]]::new()) }
            while ($y -ge $Data[$x].Count) { $Data[$x].Add($Null) }

            $Data[$x][$y] = $Unit
        }
        
        function Get-Data {
            [CmdletBinding()]
            param (
                [Parameter()]
                [__ComObject[]]$TRs
            )

            $Data = [System.Collections.Generic.List[System.Collections.Generic.List[HashTable]]]::new()
            $y = 0

            foreach ($TR in $TRs) {
                $x = 0

                foreach ($TD in ($TR | GetTopElement 'th', 'td')) {
                    while ($True) {
                        # Skip any row spans
                        $Unit = Get-Unit -Data $Data -x $x -y $y
                        if (!$Unit) { break }
                        $x++
                    }

                    $Text = if ($Null -ne $TD.innerText) { if ($NoTrim) { $TD.innerText } else { $TD.innerText.Trim() } }

                    for ($r = 0; $r -lt $TD.rowspan; $r++) {
                        $y1 = $y + $r

                        for ($c = 0; $c -lt $TD.colspan; $c++) {
                            $x1 = $x + $c
                            $Unit = Get-Unit -Data $Data -x $x1 -y $y1

                            if ($Unit) { 
                                Set-Unit -Data $Data -x $x1 -y $y1 -Unit @{ ColSpan = $True; Text = $Unit.Text, $Text } 
                            } # RowSpan/ColSpan overlap
                            else { 
                                Set-Unit -Data $Data -x $x1 -y $y1 -Unit @{ ColSpan = $c -gt 0; RowSpan = $r -gt 0; Text = $Text } 
                            }
                        }

                    }

                    $x++
                }

                $y++
            }
            , $Data
        }

    }
    Process {

        if (!$Uri -and $InputObject.Length -le 2048 -and ([Uri]$InputObject).AbsoluteUri) { 
            $Uri = [Uri]$InputObject 
        }

        $Response = if ($Uri -is [Uri] -and $Uri.AbsoluteUri) { 
            Try { 
                Invoke-WebRequest $Uri 
            } Catch { 
                Throw $_ 
            } 
        }

        $Html = if ($Response) { 
#            Invoke-ParseHtml $Response.RawContent
            Invoke-ParseHtml $Response.Content
        } else { 
            Invoke-ParseHtml $InputObject 
        }

        $i = 0

        foreach ($Table in ($Html.Body | GetTopElement 'table')) {

            if (!$PSBoundParameters.ContainsKey('TableIndex') -or $i++ -In $TableIndex) {

                $Rows = $Table | GetTopElement 'tr'

                if (!$Rows) { return }

                if ($PSBoundParameters.ContainsKey('Header')) {
                    $HeadRows = @()
                    $Data = Get-Data $Rows
                }
                else {

                    for ($i = 0; $i -lt $Rows.Count; $i++) { $Rows[$i].id = "id_$i" }

                    $THead = $Table | GetTopElement 'thead'

                    $HeadRows = @(
                        if ($THead) { $THead | GetTopElement 'tr' }
                        else { $Rows.Where({ !($_ | GetTopElement 'th') }, 'Until' ) }
                    )

                    if (!$HeadRows -or $HeadRows.Count -eq $Rows.Count) { $HeadRows = $Rows[0] }

                    $Head = Get-Data $HeadRows
                    $Data = Get-Data ($Rows.Where{ $_.id -notin $HeadRows.id })

                    $Header = @(
                        for ($x = 0; $x -lt $Head.Count; $x++) {

                            if ($Head[$x].Where({ !$_.ColSpan }, 'First') ) {
                                , @($Head[$x].Where{ !$_.RowSpan }.ForEach{ $_.Text })
                            }
                            else { $Null } # aka spanned header column

                        }

                        for ($x = $Head.Count; $x -lt $Data.Count; $x++) {
                            if ($Null -ne $Data[$x].Where({ $_ -and !$_.ColSpan }, 'First') ) { '' }
                        }
                    )
                }

                $Header = $Header.ForEach{

                    if ($Null -eq $_) { 
                        $Null 
                    }
                    else {
                        $Name = [String[]]$_
                        $Name = if ($NoTrim) { 
                            $Name -Join $Delimiter 
                        }
                        else { 
                            (($Name.ForEach{ $_.Trim() }) -Join $Delimiter).Trim() 
                        }

                        if ($Name) { 
                            $Name 
                        }
                        else { 
                            '1' 
                        }
                    }
                }

                $Unique = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::InvariantCultureIgnoreCase)

                $Duplicates = @( 
                    for ($i = 0; $i -lt $Header.Count; $i++) { 
                        if ($Null -ne $Header[$i] -and !$Unique.Add($Header[$i])) { 
                            $i 
                        } 
                    } )

                $Duplicates.ForEach{

                    do {
                        $Name, $Number = ([Regex]::Match($Header[$_], '^([\s\S]*?)(\d*)$$')).Groups.Value[1, 2]
                        $Digits = '0' * $Number.Length
                        $Header[$_] = "$Name{0:$Digits}" -f (1 + $Number)

                    } while (!$Unique.Add($Header[$_]))
                }

                for ($y = 0; $y -lt ($Data | ForEach-Object Count | Measure-Object -Maximum).Maximum; $y++) {

                    $Name = $Null # (custom) -Header parameter started with a spanned ($Null) column
                    $Properties = [ordered]@{}

                    for ($x = 0; $x -lt $Header.Count; $x++) {

                        $Unit = Get-Unit -Data $Data -x $x -y $y #-Unit

                        if ($Null -ne $Header[$x]) {
                            $Name = $Header[$x]
                            $Properties[$Name] = if ($Unit) { $Unit.Text } # else $Null (align column overflow)
                        }
                        elseif ($Name -and !$Unit.ColSpan) {
                            $Properties[$Name] = $Properties[$Name], $Unit.Text
                        }
                    }

                    [pscustomobject]$Properties
                }
            }
        }

        $Null = [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Html)
    }
    
}

function Get-LogDescriptionAndCache {
    [CmdletBinding()]
    param (
        [Parameter()]
        #[String] $Uri = "https://github.com/MicrosoftDocs/memdocs/blob/main/memdocs/configmgr/core/plan-design/hierarchy/log-files.md"
        [String] $Uri = "https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/log-files"
    )

    $HtmlAgilityPack = "C:\Program Files\PackageManagement\NuGet\Packages\HtmlAgilityPack.1.11.60\lib\netstandard2.0\HtmlAgilityPack.dll"
    Add-Type -Path $HtmlAgilityPack

    # Fetch the page content
    $Response = Invoke-WebRequest -Uri $Uri

    # Load the web page content into HtmlAgilityPack HTML document
    #$htmlDoc = New-Object HtmlAgilityPack.HtmlDocument
    $htmlDoc = [HtmlAgilityPack.HtmlDocument]::new()
    $htmlDoc.LoadHtml($Response.Content)

    # Query the document
    # Adjusted XPath query to ensure compatibility
    #$TableNames = $htmlDoc.DocumentNode.SelectNodes("//h3")
    $Tables = $htmlDoc.DocumentNode.SelectNodes("//table")

    #$rows = $htmlDoc.DocumentNode.SelectNodes("//table//tr")

    # Assuming each log name and description is in a table row (<tr>), directly within a <td>
    #$rows = $htmlDoc.DocumentNode.SelectNodes('//tr[td]')
    #$script:logDescription = $pageContent.ParsedHtml.getElementsByTagName('table') | ForEach-Object { ConvertFrom-HTMLTable $_ } | Select-Object @{n = 'LogName'; e = { if ($_.'Log Name') { ($_.'Log Name' -split "\s+")[0] } else { ($_.'Log' -split "\s+")[0] } } }, @{n = 'Description'; e = { $_.Description } } | Sort-Object -Unique -Property LogName

    #$columnName = $table.getElementsByTagName("th") | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
    
    $TablesResult = [System.Collections.ArrayList]::new()

    foreach ($Table in $Tables) {
        $TableResult = [System.Collections.ArrayList]::new()
        
        $TableNameH4 = $Table.ParentNode.SelectNodes("h4") | Where-Object { $_.Line -lt $Table.Line } | Select-Object -Last 1 #| ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        $TableNameH3 = $Table.ParentNode.SelectNodes("h3") | Where-Object { $_.Line -lt $Table.Line } | Select-Object -Last 1 #| ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        $Category = $Table.ParentNode.SelectNodes("h2") | Where-Object { $_.Line -lt $Table.Line } | Select-Object -Last 1
        $CategoryDescription = $Table.ParentNode.SelectNodes("p") | Where-Object { $_.Line -lt $Table.Line -and $_.Line -gt $Category.Line } | Select-Object -First 1 | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        $CategoryName = $Category | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }

        $TableName = $TableNameH3 | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        if ($TableNameH4) {
            if ($TableNameH4.Line -gt $TableNameH3.Line) {
                $TableName = $TableNameH4 | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
            }
        }

        $TableDescription = $Table.ParentNode.SelectNodes("p") | Where-Object { $_.Line -lt $Table.Line } | Select-Object -Last 1 | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        $TableHead = $Table.SelectNodes("thead//tr//th") | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }
        $TableBody = $Table.SelectNodes("tbody//tr")
        
        foreach ($TableRow in $TableBody) {
            $Property = [Ordered]@{}
            $i = 0

            $Columns = $TableRow.SelectNodes("td") | ForEach-Object { $_.innerText -replace "^\s*|\s*$" }

            foreach ($Column in $TableHead) {
                $Property.$Column = $Columns[$i]
                ++$i
            }

            #New-Object -TypeName PSObject -Property $Property
            $TableResult += [PSCustomObject]$Property
        }

        #$TablesResult.$TableName = $TableResult

        $TablesResult += [PSCustomObject]@{
            Name        = $TableName
            Description = $TableDescription
            Category    = $CategoryName
            CategoryDescription = $CategoryDescription
            Table       = $TableResult
        }
        
    }

    return $TablesResult

}

$Script:LogFiles = Get-LogDescriptionAndCache #| Sort-Object -Unique -Property LogName
$Script:StateMsgs = Get-LogDescriptionAndCache -Uri "https://learn.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/state-messages"

$Script:LogDescription = $Script:LogFiles | Select-Object -ExpandProperty Table | Sort-Object -Unique -Property 'Log name'
$Script:LogDescription | Export-Clixml -Path $cachedLogDescription -Force

#$Uri = "https://docs.microsoft.com/en-us/mem/configmgr/core/plan-design/hierarchy/log-files"

#$Result = Read-HtmlTable -Uri $Uri -Separator ";" -Delimiter " "
#$Script:LogDescription = $Result | Sort-Object -Unique -Property LogName
#$Script:LogDescription | Export-Clixml -Path $cachedLogDescription -Force

#Start-Sleep -Seconds 1

<#
    .SYNOPSIS
    Get status report entries (LCMv2) from a Pull Server Database.

    .DESCRIPTION
    LCMv2 (WMF5+ / PowerShell 5+) pull clients send reports
    to the Pull Server which stores their data in the StatusReport table.
    This function will return status reports from the StatusReport table
    and allows for multiple types of filtering.

    .PARAMETER AgentId
    Return the reports with the specific AgentId.

    .PARAMETER NodeName
    Return the reports with the specific NodeName.
    Wildcards are supported for SQL and ESE connections but not for MDB connection.

    .PARAMETER JobId
    Return the reports with the specific JobId (Key).

    .PARAMETER FromStartTime
    Return the reports which start from the specific FromStartTime.

    .PARAMETER ToStartTime
    Return the reports which start no later than the specific ToStartTime.

    .PARAMETER All
    Return all reports that correspond to specified filters (overwrites Top parameter).
    SQL Only.

    .PARAMETER Top
    Return number of reports that correspond to specified filters.
    SQL Only.

    .PARAMETER OperationType
    Return the reports which have the specified OperationType.

    .PARAMETER Connection
    Accepts a specific Connection to be passed to target a specific database.
    When not specified, the currently Active Connection from memory will be used
    unless one off the parameters for ad-hoc connections (ESEFilePath, SQLServer)
    is used in which case, an ad-hoc connection is created.

    .PARAMETER ESEFilePath
    Define the EDB file path to use an ad-hoc ESE connection.

    .PARAMETER MDBFilePath
    Define the MDB file path to use an ad-hoc MDB connection.

    .PARAMETER SQLServer
    Define the SQL Instance to use in an ad-hoc SQL connection.

    .PARAMETER Credential
    Define the Credentials to use with an ad-hoc SQL connection.

    .PARAMETER Database
    Define the database to use with an ad-hoc SQL connection.

    .EXAMPLE
    Get-DSCPullServerAdminStatusReport -JobId '80ee20f9-78df-480d-8175-9dd6cb09607a'
#>
function Get-DSCPullServerAdminStatusReport {
    [OutputType([DSCNodeStatusReport])]
    [CmdletBinding(DefaultParameterSetName = 'Connection')]
    param (
        [Parameter()]
        [guid] $AgentId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [SupportsWildcards()]
        [Alias('Name')]
        [string] $NodeName,

        [Parameter()]
        [guid] $JobId,

        [Parameter()]
        [datetime] $FromStartTime,

        [Parameter()]
        [datetime] $ToStartTime,

        [Parameter()]
        [switch] $All,

        [Parameter()]
        [uint16] $Top = 5,

        [Parameter()]
        [ValidateSet('All', 'LocalConfigurationManager', 'Consistency', 'Initial')]
        [string] $OperationType = 'All',

        [Parameter(ParameterSetName = 'Connection')]
        [DSCPullServerConnection] $Connection = (Get-DSCPullServerAdminConnection -OnlyShowActive),

        [Parameter(Mandatory, ParameterSetName = 'ESE')]
        [ValidateScript({$_ | Assert-DSCPullServerDatabaseFilePath -Type 'ESE'})]
        [System.IO.FileInfo] $ESEFilePath,

        [Parameter(Mandatory, ParameterSetName = 'MDB')]
        [ValidateScript({$_ | Assert-DSCPullServerDatabaseFilePath -Type 'MDB'})]
        [System.IO.FileInfo] $MDBFilePath,

        [Parameter(Mandatory, ParameterSetName = 'SQL')]
        [ValidateNotNullOrEmpty()]
        [Alias('SQLInstance')]
        [string] $SQLServer,

        [Parameter(ParameterSetName = 'SQL')]
        [pscredential] $Credential,

        [Parameter(ParameterSetName = 'SQL')]
        [ValidateNotNullOrEmpty()]
        [string] $Database
    )

    begin {
        if ($null -ne $Connection -and -not $PSBoundParameters.ContainsKey('Connection')) {
            [void] $PSBoundParameters.Add('Connection', $Connection)
        }
        $Connection = PreProc -ParameterSetName $PSCmdlet.ParameterSetName @PSBoundParameters
        if ($null -eq $Connection) {
            break
        } else {
            $script:GetConnection = $Connection
        }
    }
    process {
        switch ($Connection.Type) {
            ESE {
                $eseParams = @{
                    Connection = $Connection
                    OperationType = $OperationType
                    Table = 'StatusReport'
                }
                if ($PSBoundParameters.ContainsKey('AgentId')) {
                    $eseParams.Add('AgentId', $AgentId)
                }
                if ($PSBoundParameters.ContainsKey('NodeName')) {
                    $eseParams.Add('NodeName', $NodeName)
                }
                if ($PSBoundParameters.ContainsKey('FromStartTime')) {
                    $eseParams.Add('FromStartTime', $FromStartTime)
                }
                if ($PSBoundParameters.ContainsKey('ToStartTime')) {
                    $eseParams.Add('ToStartTime', $ToStartTime)
                }
                if ($PSBoundParameters.ContainsKey('JobId')) {
                    $eseParams.Add('JobId', $JobId)
                }
                if (-not ($PSBoundParameters.ContainsKey('All')) -and ($PSBoundParameters.ContainsKey('Top'))) {
                    $eseParams.Add('Top', $Top)
                }

                Get-DSCPullServerESERecord @eseParams
            }
            SQL {
                if ($PSBoundParameters.ContainsKey('All')) {
                    $tsqlScript = 'SELECT * FROM StatusReport'
                } else {
                    $tsqlScript = 'SELECT TOP({0}) * FROM StatusReport' -f $Top
                }
                $filters = [System.Collections.ArrayList]::new()
                if ($PSBoundParameters.ContainsKey('AgentId')) {
                    [void] $filters.Add(("Id = '{0}'" -f $AgentId))
                }
                if ($PSBoundParameters.ContainsKey("NodeName")) {
                    [void] $filters.Add(("NodeName like '{0}'" -f $NodeName.Replace('*', '%').Replace('?', '_')))
                }
                if ($PSBoundParameters.ContainsKey("FromStartTime")) {
                    [void] $filters.Add(("StartTime >= '{0}'" -f (Get-Date $FromStartTime -f s)))
                }
                if ($PSBoundParameters.ContainsKey("ToStartTime")) {
                    [void] $filters.Add(("StartTime <= '{0}'" -f (Get-Date $ToStartTime -f s)))
                }
                if ($PSBoundParameters.ContainsKey("JobId")) {
                    [void] $filters.Add(("JobId = '{0}'" -f $JobId))
                }

                if ($OperationType -ne 'All') {
                    [void] $filters.Add("OperationType = '{0}'" -f $OperationType)
                }

                if ($filters.Count -ge 1) {
                    $tsqlScript += " WHERE {0}" -f ($filters -join ' AND ')
                }

                Invoke-DSCPullServerSQLCommand -Connection $Connection -Script $tsqlScript | ForEach-Object {
                    try {
                        [DSCNodeStatusReport]::New($_)
                    } catch {
                        Write-Error -ErrorRecord $_ -ErrorAction Continue
                    }
                }
            }
            MDB {
                if ($PSBoundParameters.ContainsKey('All')) {
                    $tsqlScript = 'SELECT * FROM StatusReport'
                } else {
                    $tsqlScript = 'SELECT TOP {0} * FROM StatusReport' -f $Top
                }
                $filters = [System.Collections.ArrayList]::new()
                if ($PSBoundParameters.ContainsKey('AgentId')) {
                    [void] $filters.Add(("Id = '{0}'" -f $AgentId))
                }
                if ($PSBoundParameters.ContainsKey("NodeName")) {
                    if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($NodeName)) {
                        Write-Error -Message "MDB connection does not support wildcards for NodeName" -ErrorAction Stop
                    } else {
                        [void] $filters.Add(("NodeName = '{0}'" -f $NodeName))
                    }
                }
                if ($PSBoundParameters.ContainsKey("FromStartTime")) {
                    [void] $filters.Add(("StartTime >= '{0}'" -f (Get-Date $FromStartTime -f s)))
                }
                if ($PSBoundParameters.ContainsKey("ToStartTime")) {
                    [void] $filters.Add(("StartTime <= '{0}'" -f (Get-Date $ToStartTime -f s)))
                }
                if ($PSBoundParameters.ContainsKey("JobId")) {
                    [void] $filters.Add(("JobId = '{0}'" -f $JobId))
                }

                if ($OperationType -ne 'All') {
                    [void] $filters.Add("OperationType = '{0}'" -f $OperationType)
                }

                if ($filters.Count -ge 1) {
                    $tsqlScript += " WHERE {0}" -f ($filters -join ' AND ')
                }

                Invoke-DSCPullServerMDBCommand -Connection $Connection -Script $tsqlScript | ForEach-Object {
                    try {
                        [DSCNodeStatusReport]::New($_)
                    } catch {
                        Write-Error -ErrorRecord $_ -ErrorAction Continue
                    }
                }
            }
        }
    }
    end {
        $script:GetConnection = $null
    }
}

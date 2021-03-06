function Get-DSCPullServerESERecord {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingEmptyCatchBlock', '')]
    param (
        [Parameter(Mandatory)]
        [DSCPullServerESEConnection] $Connection,

        [Parameter(Mandatory)]
        [ValidateSet('Devices', 'RegistrationData', 'StatusReport')]
        [string] $Table,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $TargetName,

        [Parameter()]
        [guid] $ConfigurationID,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $NodeName,

        [Parameter()]
        [guid] $AgentId,

        [Parameter()]
        [datetime] $FromStartTime,

        [Parameter()]
        [datetime] $ToStartTime,

        [Parameter()]
        [guid] $JobId,

        [Parameter()]
        [ValidateSet('All', 'LocalConfigurationManager', 'Consistency', 'Initial')]
        [string] $OperationType = 'All',

        [Parameter()]
        [uint16] $Top
    )
    begin {
        $boolColumns = @(
            'NodeCompliant',
            'Dirty'
        )

        $datetimeColumns = @(
            'LastComplianceTime',
            'LastHeartbeatTime',
            'StartTime',
            'EndTime',
            'LastModifiedTime'
        )

        $deserializeColumns = @(
            'Errors',
            'StatusData',
            'ConfigurationNames'
        )

        $convertFromJsonColumns = @(
            'AdditionalData'
        )

        $intColumns = @(
            'StatusCode'
        )

        try {
            Mount-DSCPullServerESEDatabase -Connection $Connection -Mode None
            Open-DSCPullServerTable -Connection $Connection -Table $Table
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        }
    }
    process {
        try {
            $recordCount = 0
            $FirstMove = $true

            while (Move-DSCPullServerESERecordPosition -Connection $Connection -Table $Table -FirstMove $FirstMove) {
                $FirstMove = $false
                if ($PSBoundParameters.ContainsKey('Top') -and $Top -eq $recordCount) {
                    break
                }

                switch ($Table) {
                    Devices {
                        $result = [DSCDevice]::new()
                    }
                    RegistrationData {
                        $result = [DSCNodeRegistration]::new()
                    }
                    StatusReport {
                        $result = [DSCNodeStatusReport]::new()
                    }
                }
                foreach ($column in ([Microsoft.Isam.Esent.Interop.Api]::GetTableColumns($Connection.SessionId, $Connection.TableId))) {
                    if ($column.Name -eq 'IPAddress') {
                        $ipAddress = ([Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsString(
                                $Connection.SessionId,
                                $Connection.TableId,
                                $column.Columnid,
                                [System.Text.Encoding]::Unicode
                            ) -split ';' -split ',')
                        $result."$($column.Name)" = $ipAddress.ForEach{
                            # potential for invalid ip address like empty string
                            try {
                                [void][ipaddress]::Parse($_)
                                $_
                            } catch {}
                        }
                    } elseif ($column.Name -in $boolColumns) {
                        $result."$($column.Name)" = [Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsBoolean(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid
                        )
                    } elseif ($column.Name -in $datetimeColumns) {
                        $result."$($column.Name)" = [Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsDateTime(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid
                        )
                    } elseif ($column.Name -in $intColumns) {
                        $result."$($column.Name)" = [Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsInt32(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid
                        )
                    } elseif ($column.Name -in $deserializeColumns) {
                        $data = [Microsoft.Isam.Esent.Interop.Api]::DeserializeObjectFromColumn(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid
                        )
                        if ($column.Name -eq 'StatusData') {
                            $result."$($column.Name)" = $data | ConvertFrom-Json -ErrorAction SilentlyContinue
                        } else {
                            $result."$($column.Name)" = $data
                        }
                    } elseif ($column.Name -in $convertFromJsonColumns) {
                        $result."$($column.Name)" = [Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsString(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid,
                            [System.Text.Encoding]::Unicode
                        ) | ConvertFrom-Json -ErrorAction SilentlyContinue
                    } else {
                        $result."$($column.Name)" = [Microsoft.Isam.Esent.Interop.Api]::RetrieveColumnAsString(
                            $Connection.SessionId,
                            $Connection.TableId,
                            $column.Columnid,
                            [System.Text.Encoding]::Unicode
                        )
                    }
                }

                if ($Table -eq 'Devices') {
                    if ($PSBoundParameters.ContainsKey('TargetName') -and $result.TargetName -notlike $TargetName) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('ConfigurationID') -and $result.ConfigurationID -notlike $ConfigurationID) {
                        continue
                    }
                    $result
                } elseif ($Table -eq 'RegistrationData') {
                    if ($PSBoundParameters.ContainsKey('NodeName') -and $result.NodeName -notlike $NodeName) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('AgentId') -and $result.AgentId -ne $AgentId) {
                        continue
                    }
                    $result
                } elseif ($Table -eq 'StatusReport') {
                    if ($PSBoundParameters.ContainsKey('AgentId') -and $result.Id -ne $AgentId) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('NodeName') -and $result.NodeName -notlike $NodeName) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('FromStartTime') -and $result.StartTime -lt $FromStartTime) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('ToStartTime') -and $result.StartTime -gt $ToStartTime) {
                        continue
                    }
                    if ($PSBoundParameters.ContainsKey('JobId') -and $result.JobId -ne $JobId) {
                        continue
                    }
                    if ($OperationType -ne 'All' -and $result.OperationType -ne $OperationType) {
                        continue
                    }
                    [void] $recordCount++
                    $result
                }
            }
        } catch {
            Write-Error -ErrorRecord $_ -ErrorAction Stop
        } finally {
            Dismount-DSCPullServerESEDatabase -Connection $Connection
        }
    }
    end {
        if ($null -ne $Connection.Instance) {
            Dismount-DSCPullServerESEDatabase -Connection $Connection
        }
    }
}

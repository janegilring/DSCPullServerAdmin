$here = $PSScriptRoot

$modulePath = "$here\..\..\.."
$moduleName = Split-Path -Path $modulePath -Leaf

InModuleScope $moduleName {
    Describe New-DSCPullServerAdminConnection {
        $tempEDBFile = New-Item -Path TestDrive: -Name pull.edb -ItemType File -Force
        $tempMDBFile = New-Item -Path TestDrive: -Name pull.mdb -ItemType File -Force

        BeforeEach {
            $script:DSCPullServerConnections = $null
        }

        It 'Should assign index 0 when no previous connecions are in module var DSCPullServerConnections' {
            Mock -CommandName Get-DSCPullServerAdminConnection
            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }
            Mock -CommandName Assert-DSCPullServerESEPreReq

            $null = New-Item -Path TestDrive: -Name pull.edb -ItemType File -Force
            $result = New-DSCPullServerAdminConnection -ESEFilePath $tempEDBFile.FullName
            $result.Index | Should -Be 0
            $result.Type | SHould -Be 'ESE'
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty

            Assert-MockCalled -CommandName Assert-DSCPullServerESEPreReq -Times 1 -Exactly -Scope it
        }

        It 'Should assign index 1 when previous connections are in module var DSCPullServerConnections' {
            Mock -CommandName Get-DSCPullServerAdminConnection -MockWith {
                $sqlConnection = [DSCPullServerSQLConnection]::new()
                $sqlConnection.Active = $true
                $sqlConnection.Index = 0
                $sqlConnection
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }

            Mock -CommandName Assert-DSCPullServerESEPreReq

            $result = New-DSCPullServerAdminConnection -ESEFilePath $tempEDBFile.FullName
            $result.Index | Should -Be 1
            $result.Type | SHould -Be 'ESE'
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty
        }

        It 'Should not add to module var DSCPullServerConnections when DontStore is specified' {
            Mock -CommandName Get-DSCPullServerAdminConnection
            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }
            Mock -CommandName Assert-DSCPullServerMDBPreReq

            $null = New-DSCPullServerAdminConnection -MDBFilePath $tempMDBFile.FullName -DontStore
            $script:DSCPullServerConnections | Should -BeNullOrEmpty

            Assert-MockCalled -CommandName Assert-DSCPullServerMDBPreReq -Times 1 -Exactly -Scope it
        }

        It 'Should create a SQL Connection when no Credentials are specified and database is specified and connection is validated true' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $true
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }

            Mock -CommandName Assert-DSCPullServerESEPreReq
            Mock -CommandName Assert-DSCPullServerMDBPreReq

            $result = New-DSCPullServerAdminConnection -SQLServer 'Server\Instance' -Database 'DSCDB'
            $result.Index | Should -Be 0
            $result.Type | Should -Be 'SQL'
            $result.SQLServer | Should -Be 'Server\Instance'
            $result.Credential | Should -BeNullOrEmpty
            $result.Database | Should -Be 'DSCDB'
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty

            Assert-MockCalled -CommandName Assert-DSCPullServerESEPreReq -Times 0 -Exactly -Scope it
            Assert-MockCalled -CommandName Assert-DSCPullServerMDBPreReq -Times 0 -Exactly -Scope it
        }

        It 'Should create a SQL Connection when Credential is specified and database is specified and connection is validated true' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $true
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }

            $result = New-DSCPullServerAdminConnection -SQLServer 'Server\Instance' -Database 'DSCDB' -Credential ([pscredential]::new('sa', [securestring]::new()))
            $result.Index | Should -Be 0
            $result.Type | Should -Be 'SQL'
            $result.SQLServer | Should -Be 'Server\Instance'
            $result.Credential | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be 'DSCDB'
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty
        }

        It 'Should create a SQL Connection when Credential is specified and no database is specified and connection is validated true' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $true
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }

            $result = New-DSCPullServerAdminConnection -SQLServer 'Server\Instance' -Credential ([pscredential]::new('sa', [securestring]::new()))
            $result.Index | Should -Be 0
            $result.Type | Should -Be 'SQL'
            $result.SQLServer | Should -Be 'Server\Instance'
            $result.Credential | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be 'DSC'
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty
        }

        It 'Should create a SQL Connection when only SQLServer is specified and connection validated true' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $true
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $true
            }

            $result = New-DSCPullServerAdminConnection -SQLServer 'Server\Instance'
            $result.Index | Should -Be 0
            $result.Type | Should -Be 'SQL'
            $result.SQLServer | Should -Be 'Server\Instance'
            $result.Credential | Should -BeNullOrEmpty
            $result.Database | Should -BeNullOrEmpty
            $script:DSCPullServerConnections | Should -Not -BeNullOrEmpty
        }

        It 'Should throw when connection validated false (SQL)' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $false
            }

            { New-DSCPullServerAdminConnection -SQLServer 'Server\Instance' } |
                Should -Throw

            $script:DSCPullServerConnections | Should -BeNullOrEmpty
        }

        It 'Should throw when expected tables are not found (SQL)' {
            Mock -CommandName Get-DSCPullServerAdminConnection

            Mock -CommandName Test-DSCPullServerDatabaseExist -MockWith {
                $true
            }

            Mock -CommandName Test-DSCPullServerDatabase -MockWith {
                $false
            }

            { New-DSCPullServerAdminConnection -SQLServer 'Server\Instance' } |
                Should -Throw

            $script:DSCPullServerConnections | Should -BeNullOrEmpty
        }
    }
}

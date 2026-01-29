# xyOps MSSQL Query Plugin - PowerShell Version
# Reads JSON input from STDIN and executes SQL queries using dbatools

function Write-Output-JSON {
    param($Object)
    $json = $Object | ConvertTo-Json -Compress -Depth 100
    Write-Output $json
}

function Send-Progress {
    param([double]$Value)
    Write-Output-JSON @{ xy = 1; progress = $Value }
}

function Send-Data {
    param($Data)
    # Pre-serialize the data payload separately to avoid depth issues
    $dataJson = $Data | ConvertTo-Json -Compress -Depth 100 -WarningAction SilentlyContinue
    # Manually construct the wrapper JSON to avoid double-encoding
    $output = '{"xy":1,"output":{"data":' + $dataJson + '}}'
    Write-Output $output
}

function Send-CSV {
    param($Recordset)
    
    if ($null -eq $Recordset -or $Recordset.Count -eq 0) { return }
    
    # Convert to CSV format using PowerShell's built-in Export-CSV logic
    $csv = $Recordset | ConvertTo-Csv -NoTypeInformation
    
    # Send as text output
    Write-Output-JSON @{
        xy = 1
        output = @{
            text = ($csv -join "`n")
        }
    }
}

function Send-Success {
    param([string]$Description = "Query completed successfully")
    Write-Output-JSON @{ xy = 1; code = 0; description = $Description }
}

function Send-Error {
    param([int]$Code, [string]$Description)
    Write-Output-JSON @{ xy = 1; code = $Code; description = $Description }
}

# Read input from STDIN
$inputJson = [Console]::In.ReadToEnd()

try {
    $jobData = $inputJson | ConvertFrom-Json
}
catch {
    Send-Error -Code 1 -Description "Failed to parse input JSON: $($_.Exception.Message)"
    exit 1
}

# Extract parameters
$params = $jobData.params
$server = $params.server
$database = $params.database
$username = $params.username
$password = $params.password
$query = $params.query
$maxRows = $params.maxRows
$exportFormat = if ([string]::IsNullOrWhiteSpace($params.exportFormat)) { "CSV" } else { $params.exportFormat.ToUpper() }
$encrypt = if ($params.encrypt -eq $true -or $params.encrypt -eq "true") { $true } else { $false }
$trustServerCertificate = if ($params.trustServerCertificate -eq $true -or $params.trustServerCertificate -eq "true") { $true } else { $false }

# Validate required parameters
$required = @('server', 'database', 'username', 'password', 'query')
$missing = @()
foreach ($field in $required) {
    if ([string]::IsNullOrWhiteSpace($params.$field)) {
        $missing += $field
    }
}

if ($missing.Count -gt 0) {
    Send-Error -Code 2 -Description "Missing required parameters: $($missing -join ', ')"
    exit 1
}

try {
    # Check if dbatools module is installed
    Send-Progress -Value 0.1
    
    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        try {
            Write-Error "dbatools module not found, attempting to install..."
            Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-Error "dbatools module installed successfully"
        }
        catch {
            Send-Error -Code 3 -Description "Failed to install required dbatools module. Please install it manually by running: Install-Module -Name dbatools -Force (Install error: $($_.Exception.Message))"
            exit 1
        }
    }
    
    # Import dbatools module
    Send-Progress -Value 0.2
    Import-Module dbatools -ErrorAction Stop
    
    # Build connection parameters
    Send-Progress -Value 0.3
    
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    
    $connectParams = @{
        SqlInstance = $server
        Database = $database
        SqlCredential = $credential
    }
    
    if ($encrypt) {
        $connectParams['EncryptConnection'] = $true
    }
    
    if ($trustServerCertificate) {
        $connectParams['TrustServerCertificate'] = $true
    }
    
    # Apply SQL-level row limit if maxRows is specified and greater than 0
    # If maxRows is 0, no limit is applied (return all rows)
    if ($maxRows -and $maxRows -gt 0) {
        # Check if query already has TOP clause (with or without parentheses)
        if ($query -match '(?i)^\s*SELECT\s+TOP\s*\(?\d+\)?') {
            # Replace existing TOP with our value
            $query = [regex]::Replace($query, '^(\s*SELECT\s+)TOP\s*\(?\d+\)?', "`$1TOP $maxRows ", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Write-Error "Query TOP clause replaced with limit of $maxRows rows"
        } else {
            # Inject TOP clause after SELECT
            $query = [regex]::Replace($query, '^(\s*SELECT\s+)', "`$1TOP $maxRows ", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            Write-Error "Query limited to $maxRows rows"
        }
    } elseif ($maxRows -eq 0) {
        Write-Error "maxRows is 0 - no row limit applied, returning all results"
    }
    
    # Execute query
    Send-Progress -Value 0.5
    
    try {
        # Capture warnings as errors
        $WarningPreference = 'Stop'
        $result = Invoke-DbaQuery @connectParams -Query $query -As PSObject -ErrorAction Stop -EnableException
        Send-Progress -Value 0.9
        
        # Convert result to hashtable array
        $processedResult = @()
        if ($result) {
            foreach ($row in $result) {
                $processedRow = @{}
                foreach ($prop in $row.PSObject.Properties) {
                    $processedRow[$prop.Name] = $prop.Value
                }
                $processedResult += $processedRow
            }
        }
        
        # Export results based on selected format
        $rowCount = $processedResult.Count
        
        if ($processedResult.Count -gt 0) {
            # Generate unique filename with timestamp, milliseconds, and short GUID
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
            $shortGuid = [guid]::NewGuid().ToString().Substring(0, 8)
            
            if ($exportFormat -eq "JSON") {
                # Export as JSON
                $jsonFileName = "query_results_${timestamp}_${shortGuid}.json"
                $jsonFilePath = Join-Path $env:PWD $jsonFileName
                $processedResult | ConvertTo-Json -Depth 100 | Out-File -FilePath $jsonFilePath -Encoding UTF8
                Write-Error "JSON file written to: $jsonFilePath"
                
                # Upload the file as job output
                Write-Output-JSON @{ xy = 1; files = @($jsonFilePath) }
                
                # Send data output with file information
                $dataPayload = @{
                    server = $server
                    database = $database
                    rowCount = $rowCount
                    format = "json"
                    fileName = $jsonFileName
                    filePath = $jsonFilePath
                }
                Write-Output-JSON @{ xy = 1; data = $dataPayload }
                
                # Send success status (must be LAST - job completes after this)
                Send-Success -Description "Query executed successfully. $rowCount row(s) returned. Results saved to $jsonFileName"
            } else {
                # Export as CSV (default)
                $csvData = $processedResult | ForEach-Object { [PSCustomObject]$_ }
                $csvFileName = "query_results_${timestamp}_${shortGuid}.csv"
                $csvFilePath = Join-Path $env:PWD $csvFileName
                $csvData | Export-Csv -Path $csvFilePath -NoTypeInformation -Encoding UTF8
                Write-Error "CSV file written to: $csvFilePath"
                
                # Upload the file as job output
                Write-Output-JSON @{ xy = 1; files = @($csvFilePath) }
                
                # Send data output with file information
                $dataPayload = @{
                    server = $server
                    database = $database
                    rowCount = $rowCount
                    format = "csv"
                    fileName = $csvFileName
                    filePath = $csvFilePath
                }
                Write-Output-JSON @{ xy = 1; data = $dataPayload }
                
                # Send success status (must be LAST - job completes after this)
                Send-Success -Description "Query executed successfully. $rowCount row(s) returned. Results saved to $csvFileName"
            }
        } else {
            # Send success for empty results
            Send-Success -Description "Query executed successfully. 0 rows returned."
        }
    }
    catch {
        Send-Error -Code 4 -Description "Database query failed: $($_.Exception.Message)"
        exit 1
    }
}
catch {
    Send-Error -Code 5 -Description $_.Exception.Message
    exit 1
}

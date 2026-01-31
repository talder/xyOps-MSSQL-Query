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
    $jobData = $inputJson | ConvertFrom-Json -AsHashtable
}
catch {
    Send-Error -Code 1 -Description "Failed to parse input JSON: $($_.Exception.Message)"
    exit 1
}

# Extract parameters - using PSObject properties to handle case variations
$params = $jobData.params

# Helper function to get parameter value case-insensitively
function Get-ParamValue {
    param($ParamsObject, [string]$ParamName)
    # Handle both hashtable and PSObject
    if ($ParamsObject -is [hashtable]) {
        # For hashtables, find key case-insensitively
        foreach ($key in $ParamsObject.Keys) {
            if ($key -ieq $ParamName) {
                return $ParamsObject[$key]
            }
        }
        return $null
    } else {
        # For PSObject
        $prop = $ParamsObject.PSObject.Properties | Where-Object { $_.Name -ieq $ParamName } | Select-Object -First 1
        if ($prop) { return $prop.Value }
        return $null
    }
}

# Check if debug mode is enabled
$debugRaw = Get-ParamValue -ParamsObject $params -ParamName 'debug'
$debug = if ($debugRaw -eq $true -or $debugRaw -eq "true") { $true } else { $false }

# If debug is enabled, output the incoming JSON
if ($debug) {
    Write-Error "=== DEBUG: Incoming JSON ==="
    # Create a copy without the script parameter
    $debugData = @{}
    if ($jobData -is [hashtable]) {
        foreach ($key in $jobData.Keys) {
            if ($key -ne 'script') {
                $debugData[$key] = $jobData[$key]
            }
        }
    } else {
        foreach ($prop in $jobData.PSObject.Properties) {
            if ($prop.Name -ne 'script') {
                $debugData[$prop.Name] = $prop.Value
            }
        }
    }
    $formattedJson = $debugData | ConvertTo-Json -Depth 10
    Write-Error $formattedJson
    Write-Error "=== END DEBUG ==="
}

$server = Get-ParamValue -ParamsObject $params -ParamName 'server'
$database = Get-ParamValue -ParamsObject $params -ParamName 'database'
$username = Get-ParamValue -ParamsObject $params -ParamName 'username'
$password = Get-ParamValue -ParamsObject $params -ParamName 'password'
$query = Get-ParamValue -ParamsObject $params -ParamName 'query'
$maxRows = Get-ParamValue -ParamsObject $params -ParamName 'maxRows'
$exportFormatRaw = Get-ParamValue -ParamsObject $params -ParamName 'exportFormat'
$exportFormat = if ([string]::IsNullOrWhiteSpace($exportFormatRaw)) { "CSV" } else { $exportFormatRaw.ToUpper() }
$useencryptionRaw = Get-ParamValue -ParamsObject $params -ParamName 'useencryption'
$trustcertRaw = Get-ParamValue -ParamsObject $params -ParamName 'trustcert'


# Validate required parameters
$required = @('server', 'database', 'username', 'password', 'query')
$missing = @()
foreach ($field in $required) {
    $value = Get-ParamValue -ParamsObject $params -ParamName $field
    if ([string]::IsNullOrWhiteSpace($value)) {
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
    
    # Extract and convert encryption parameters
    $useencryptionRaw = Get-ParamValue -ParamsObject $params -ParamName 'useencryption'
    $trustcertRaw = Get-ParamValue -ParamsObject $params -ParamName 'trustcert'
    
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    
    # Build Connect-DbaInstance parameters with encryption settings
    $connectParams = @{
        SqlInstance = $server
        Database = $database
        SqlCredential = $credential
    }
    
    # Add encryption parameter if enabled
    if ($useencryptionRaw -eq $true -or $useencryptionRaw -eq "true" -or $useencryptionRaw -eq "True") {
        $connectParams['EncryptConnection'] = $true
        Write-Error "Encryption enabled"
    }
    
    # Add TrustServerCertificate parameter if enabled
    if ($trustcertRaw -eq $true -or $trustcertRaw -eq "true" -or $trustcertRaw -eq "True") {
        $connectParams['TrustServerCertificate'] = $true
        Write-Error "TrustServerCertificate enabled"
    }
    
    # Create connection using Connect-DbaInstance
    Write-Error "Connecting to $server with encryption=$useencryptionRaw, trustcert=$trustcertRaw"
    $serverConnection = Connect-DbaInstance @connectParams
    
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
        # When trustcert is enabled, suppress warnings to prevent certificate validation warnings from becoming errors
        if ($trustcertRaw -eq $true -or $trustcertRaw -eq "true" -or $trustcertRaw -eq "True") {
            $WarningPreference = 'SilentlyContinue'
        } else {
            $WarningPreference = 'Stop'
        }
        
        # Use the connection object created by Connect-DbaInstance
        $result = Invoke-DbaQuery -SqlInstance $serverConnection -Query $query -As PSObject -ErrorAction Stop -EnableException
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

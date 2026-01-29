# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This repository contains a xyOps plugin for executing MSSQL queries via PowerShell. The plugin implements a STDIN/STDOUT JSON protocol to communicate with the xyOps event system.

**Note:** There are two nearly identical PowerShell scripts in this repository:
- `xyOps_MSSQL_Query.ps1` (root directory) - Has `maxRows` parameter support with automatic TOP clause injection
- `xyOps-MSSQL-Query/xyOps-MSSQL-Query.ps1` (subdirectory) - Identical functionality

The subdirectory also contains its own `.git` folder, suggesting it may be a submodule or separate repository.

## Architecture

### xyOps Plugin Protocol

The plugin follows a specific JSON communication protocol:

**Input Format (STDIN):**
```json
{
  "params": {
    "server": "sql.example.com",
    "database": "mydb",
    "username": "user",
    "password": "pass",
    "query": "SELECT * FROM table",
    "maxRows": 1000,
    "encrypt": true|false,
    "trustServerCertificate": true|false
  }
}
```

**Output Messages (STDOUT):**
All output messages must be valid JSON with `xy: 1` property:

1. **Progress:** `{ "xy": 1, "progress": 0.5 }`
2. **Data:** `{ "xy": 1, "data": { ... } }`
3. **Files:** `{ "xy": 1, "files": ["path/to/file"] }`
4. **Success:** `{ "xy": 1, "code": 0, "description": "..." }`
5. **Error:** `{ "xy": 1, "code": <non-zero>, "description": "..." }`

**Critical Ordering:** Data and file outputs must come BEFORE the success message. The success message terminates the job.

### Core Functions

The plugin defines helper functions for protocol compliance:

- `Write-Output-JSON` - Serializes objects to JSON
- `Send-Progress` - Sends progress updates (0.0 to 1.0)
- `Send-Data` - Sends structured data payload
- `Send-CSV` - Sends CSV formatted output
- `Send-Success` - Sends success status (terminates job)
- `Send-Error` - Sends error status (terminates job)

### Database Access

Uses the **dbatools** PowerShell module for SQL Server connectivity:
- Auto-installs if missing using `Install-Module -Name dbatools -Scope CurrentUser`
- Uses `Invoke-DbaQuery` for query execution
- Supports SQL authentication with encrypted connections
- Automatically injects `TOP` clause when `maxRows` parameter is provided

### Result Handling

Query results are returned in two ways:

1. **CSV File Output:** Always written to `query_results.csv` in `$env:PWD`
2. **Inline Data:** Included in data payload if under 1MB, otherwise file-only

The data payload includes:
- `server`, `database` - Connection metadata
- `rowCount` - Number of rows returned
- `format` - Always "csv"
- `csv` - CSV text (if under 1MB)
- `message` - Info message (if over 1MB)

## Development Commands

### Testing the Plugin

To manually test the plugin with sample input:

```powershell
# Create test input
$testInput = @{
  params = @{
    server = "localhost"
    database = "testdb"
    username = "sa"
    password = "YourPassword"
    query = "SELECT TOP 10 * FROM sys.tables"
    encrypt = $false
    trustServerCertificate = $true
  }
} | ConvertTo-Json -Depth 10

# Execute the plugin
$testInput | .\xyOps_MSSQL_Query.ps1
```

### Installing Dependencies

```powershell
Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser
```

### Validating JSON Output

When modifying output functions, ensure all JSON contains the `xy: 1` property and is properly formatted. Use PowerShell's `ConvertFrom-Json` to validate:

```powershell
$output | ConvertFrom-Json  # Should not throw errors
```

## Code Modification Guidelines

### When Adding New Parameters

1. Add parameter definition to `xyops.json` in the `params` array
2. Extract parameter in the script: `$newParam = $params.newParam`
3. Add validation if required
4. Update the embedded script in `xyops.json` (line 13) - it contains the entire PowerShell script as an escaped string

### When Modifying Output Format

- Maintain the `xy: 1` property in all JSON outputs
- Keep success/error messages as the final output
- Data and file outputs must precede status messages
- Use `Write-Error` for diagnostic messages (goes to stderr, not captured in xyOps output)

### Query Manipulation

The script automatically modifies queries when `maxRows` is set:
- Detects existing `TOP` clauses (with or without parentheses)
- Replaces or injects `TOP N` after SELECT keyword
- Uses regex with `IgnoreCase` for SQL keyword matching

When modifying query manipulation logic, test with these scenarios:
- `SELECT * FROM table`
- `SELECT TOP 100 * FROM table`
- `SELECT TOP(50) * FROM table`
- `  SELECT  * FROM table` (extra whitespace)

### Error Handling

Error codes are standardized:
- Code 1: JSON parsing failure
- Code 2: Missing required parameters
- Code 3: Module installation failure
- Code 4: Database query failure
- Code 5: General exception

When adding new failure modes, use appropriate error codes and descriptive messages.

## Important Notes

- The `xyops.json` file contains the entire PowerShell script as an escaped string on line 13. Updates to `xyOps_MSSQL_Query.ps1` must be manually synced to this embedded version.
- The plugin uses `Write-Error` for diagnostic logging since stderr is not captured by xyOps as job output.
- Password parameters are converted to `SecureString` for dbatools compatibility.
- CSV size is checked against 1MB threshold to determine inline vs file-only output.
- The `$WarningPreference = 'Stop'` setting converts dbatools warnings into catchable errors.

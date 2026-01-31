# xyOps MSSQL Query Plugin

Execute SQL queries against Microsoft SQL Server databases using PowerShell and [dbatools](https://dbatools.io). This plugin provides a simple interface to run queries, export results to CSV or JSON file, and manage connection security settings.

## Features

- Execute SQL queries against any MSSQL database
- Export results in CSV or JSON file format that can be used in xyOps (bucket or in workflow)
- Configurable encryption and certificate validation
- Row limiting with automatic TOP clause injection
- Auto-installs dbatools PowerShell module if missing
- Unique timestamped output files to prevent overwrites
- Works on Windows, MacOS (Should work on Linux to, not tested yet)

### CLI Requirements

- **PowerShell Core (pwsh)** - Version 7.0 or later recommended
  - On macOS: `brew install powershell`
  - On Linux: [Install instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux)
  - On Windows: Comes pre-installed or [download](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.5)

### Module Requirements

- **dbatools** - Automatically installed by the plugin if not present
  - The plugin will attempt to install dbatools using `Install-Module -Name dbatools -Scope CurrentUser`
  - Requires internet connection for first-time installation

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `server` | text | Yes | SQL Server address (hostname or IP) |
| `database` | text | Yes | Database name to query |
| `username` | text | Yes | SQL Server username for authentication |
| `password` | text | Yes | SQL Server password |
| `query` | textarea | Yes | SQL query to execute |
| `maxRows` | number | No | Maximum rows to return (0 = unlimited) |
| `exportFormat` | select | No | Output format: CSV (default) or JSON |
| `useencryption` | checkbox | No | Enable encrypted connection |
| `trustcert` | checkbox | No | Trust server certificate (bypass validation) |
| `debug` | checkbox | No | Enable debug output |

## Usage Examples

### Simple SELECT Query

Query all records from the `Employees` table:

```sql
SELECT * FROM Employees
```

### Query with TOP Clause

Get the top 5 highest-priced products:

```sql
SELECT TOP 5 * FROM Products ORDER BY Price DESC
```

### Join Query

Retrieve orders with employee information:

```sql
SELECT 
    o.OrderID,
    e.FirstName + ' ' + e.LastName AS EmployeeName,
    o.OrderDate,
    o.TotalAmount,
    o.Status
FROM Orders o
INNER JOIN Employees e ON o.EmployeeID = e.EmployeeID
ORDER BY o.OrderDate DESC
```

### Aggregate Query

Calculate employee statistics by department:

```sql
SELECT 
    Department,
    COUNT(*) AS EmployeeCount,
    AVG(Salary) AS AvgSalary,
    MAX(Salary) AS MaxSalary
FROM Employees
GROUP BY Department
ORDER BY AvgSalary DESC
```

### Date Filtering

Find completed orders from a specific date range:

```sql
SELECT * FROM Orders 
WHERE OrderDate >= '2024-01-15' 
AND Status = 'Completed'
```

## Row Limiting

The `maxRows` parameter provides flexible control over query results:

- **maxRows > 0**: Automatically injects or replaces `TOP N` clause in SELECT queries
- **maxRows = 0**: Returns all rows (no limit)
- **Not set**: Returns all rows (no limit)

### Examples

**Setting maxRows to 100:**
```sql
SELECT * FROM LargeTable
```
Becomes:
```sql
SELECT TOP 100 * FROM LargeTable
```

**maxRows with existing TOP clause:**
If your query already has `TOP 50` and you set `maxRows=100`, it will be replaced with `TOP 100`.

## Export Formats

### CSV (Default)

Results are exported to a CSV file with headers. File naming pattern:
```
query_results_20260131_143052_187_a3b5c7d9.csv
```

Format: `query_results_{YYYYMMDD}_{HHmmss}_{milliseconds}_{GUID}.csv`

### JSON

Results are exported as a JSON array of objects. File naming pattern:
```
query_results_20260131_143052_187_a3b5c7d9.json
```

Example output:
```json
[
  {
    "EmployeeID": 1,
    "FirstName": "John",
    "LastName": "Doe",
    "Department": "IT",
    "Salary": 75000.00
  },
  {
    "EmployeeID": 2,
    "FirstName": "Jane",
    "LastName": "Smith",
    "Department": "HR",
    "Salary": 65000.00
  }
]
```

## Connection Security

### Encryption

Enable the `Use Encryption` checkbox to force encrypted connections. This is recommended when connecting over untrusted networks.

**Note**: Your SQL Server must be configured to support encryption, or you must enable `Trust Certificate` to bypass certificate validation.

### Certificate Validation

The `Trust Certificate` checkbox allows you to bypass SSL/TLS certificate validation. Use this when:

- Connecting to servers with self-signed certificates
- Working in development/testing environments
- Dealing with certificate name mismatches

**Security Warning**: Only use `Trust Certificate` in trusted environments. In production, properly configure SSL certificates on your SQL Server.

## Debug Mode

Enable the `Enable debug mode` checkbox to see detailed execution information including:

- Input parameter values
- Connection settings
- dbatools configuration
- Query modifications (TOP clause injection)
- File paths and sizes

Debug output appears in the job logs (stderr).

## Error Codes

| Code | Description |
|------|-------------|
| 1 | Failed to parse input JSON |
| 2 | Missing required parameters |
| 3 | Failed to install dbatools module |
| 4 | Database query execution failed |
| 5 | General exception |

## Test Database Setup

Here's a SQL Query to create a test database with sample data:

```sql
-- Create test database
CREATE DATABASE TestDB;
GO

USE TestDB;
GO

-- Create Employees table
CREATE TABLE Employees (
    EmployeeID INT PRIMARY KEY IDENTITY(1,1),
    FirstName NVARCHAR(50) NOT NULL,
    LastName NVARCHAR(50) NOT NULL,
    Email NVARCHAR(100),
    Department NVARCHAR(50),
    Salary DECIMAL(10,2),
    HireDate DATE
);

-- Create Products table
CREATE TABLE Products (
    ProductID INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50),
    Price DECIMAL(10,2),
    Stock INT,
    LastUpdated DATETIME DEFAULT GETDATE()
);

-- Create Orders table
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    EmployeeID INT FOREIGN KEY REFERENCES Employees(EmployeeID),
    OrderDate DATETIME DEFAULT GETDATE(),
    TotalAmount DECIMAL(10,2),
    Status NVARCHAR(20)
);

-- Insert sample employees
INSERT INTO Employees (FirstName, LastName, Email, Department, Salary, HireDate) VALUES
('John', 'Doe', 'john.doe@company.com', 'IT', 75000.00, '2020-01-15'),
('Jane', 'Smith', 'jane.smith@company.com', 'HR', 65000.00, '2019-03-20'),
('Bob', 'Johnson', 'bob.johnson@company.com', 'Sales', 70000.00, '2021-06-10'),
('Alice', 'Williams', 'alice.williams@company.com', 'IT', 80000.00, '2018-11-05'),
('Charlie', 'Brown', 'charlie.brown@company.com', 'Finance', 72000.00, '2020-09-12');

-- Insert sample products
INSERT INTO Products (ProductName, Category, Price, Stock) VALUES
('Laptop Pro 15', 'Electronics', 1299.99, 45),
('Wireless Mouse', 'Accessories', 29.99, 150),
('Monitor 27"', 'Electronics', 399.99, 60),
('Office Chair', 'Furniture', 249.99, 35),
('Standing Desk', 'Furniture', 499.99, 20);

-- Insert sample orders
INSERT INTO Orders (EmployeeID, OrderDate, TotalAmount, Status) VALUES
(1, '2024-01-10', 1329.98, 'Completed'),
(3, '2024-01-12', 429.98, 'Completed'),
(2, '2024-01-15', 89.99, 'Pending'),
(4, '2024-01-18', 1749.97, 'Shipped');
GO
```

## Troubleshooting

### dbatools Installation Fails

If automatic installation fails, manually install dbatools:

```powershell
Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser
```

### Connection Fails with Certificate Error

Enable the `Trust certificate` checkbox to bypass certificate validation, or properly configure SSL on your SQL Server.

### Permission Denied

Ensure the SQL Server user has appropriate permissions to:
- Connect to the database
- Execute SELECT queries on target tables
- Read system metadata (if querying system tables)

## Data Collection

This plugin does not collect any user data or metrics. All query execution and data processing happens locally within the xyOps environment.

## Links

- [dbatools Documentation](https://dbatools.io)
- [dbatools GitHub](https://github.com/dataplat/dbatools)
- [PowerShell Installation](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- [SQL Server Documentation](https://learn.microsoft.com/en-us/sql/)

## License

MIT License - See [LICENSE.md](LICENSE.md) for details.

## Author

Tim Alderweireldt

## Version

1.0.0

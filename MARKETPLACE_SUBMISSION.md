# Marketplace Submission Checklist

## Required Files Status

- [x] README.md - Comprehensive documentation created
- [x] LICENSE.md - MIT License created
- [ ] xyops.json - **ACTION REQUIRED**: Export from xyOps UI
- [ ] logo.png - **ACTION REQUIRED**: Create 128x128px logo

## Export xyops.json from xyOps

1. Open xyOps application
2. Navigate to your MSSQL Query plugin
3. Click the "**Export...**" button
4. Save the file as `xyops.json` in `/Users/tim/Documents/GitHub/xyOps-MSSQL-Query/xyOps-MSSQL-Query/`

## Create logo.png

Requirements:
- Size: At least 128x128 pixels (square, 1:1 aspect ratio)
- Format: PNG with alpha transparency
- Style: Light/dark theme friendly
- Location: `/Users/tim/Documents/GitHub/xyOps-MSSQL-Query/xyOps-MSSQL-Query/logo.png`

Suggestion: Use a database icon or SQL-related graphic

## GitHub Repository Setup

1. Ensure repository is public on GitHub
2. Create and push version tag:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

## Marketplace Submission Data

When ready to submit to https://github.com/pixlcore/xyops-marketplace, add this entry to `marketplace.json`:

```json
{
  "id": "talder/xyOps-MSSQL-Query",
  "title": "MSSQL Query",
  "author": "Tim Alderweireldt",
  "description": "Execute SQL queries against Microsoft SQL Server databases using PowerShell and dbatools. Supports encrypted connections, certificate validation, CSV/JSON export, and automatic row limiting.",
  "versions": ["v1.0.0"],
  "type": "plugin",
  "plugin_type": "event",
  "license": "MIT",
  "tags": ["MSSQL", "SQL Server", "Database", "Query", "PowerShell", "dbatools"],
  "requires": ["pwsh"],
  "created": "2026-01-31",
  "modified": "2026-01-31"
}
```

## Launch Command

Since this is a PowerShell script, users will need to execute it directly. The `xyops.json` file should contain the actual PowerShell script in the `command` or `script` field as exported from xyOps.

Example command format in xyops.json:
```
"command": "powershell.exe"
```

The script content should be embedded in the `script` field.

## Pre-Submission Checklist

- [ ] All required files present (README.md, LICENSE.md, xyops.json, logo.png)
- [ ] Repository is public on GitHub at https://github.com/talder/xyOps-MSSQL-Query
- [ ] Version tag v1.0.0 created and pushed
- [ ] README.md is comprehensive and accurate
- [ ] logo.png meets requirements
- [ ] xyops.json properly exported from xyOps
- [ ] Tested plugin works correctly
- [ ] No sensitive data in repository

## Submission Steps

1. Fork https://github.com/pixlcore/xyops-marketplace
2. Add entry to `marketplace.json` (see template above)
3. Create pull request with clear description
4. Wait for review (may take several days)
5. Address any feedback from reviewers

## Notes

- Plugin must be free to use (no cost to install)
- Must be fully open source with OSI-approved license (MIT ✓)
- Must be family-friendly
- Must not violate any laws or ToS
- PixlCore reserves right to reject submissions

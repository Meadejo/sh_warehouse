# Pipeline Error Code Reference

## Overview

The pipeline uses a standardized error object structure to track issues during execution. This document defines error severities, code structure, and catalogs all defined error codes.

## Incident Severity Levels

| Severity | Value | Description | Pipeline Behavior | When to Use |
|----------|-------|-------------|-------------------|-------------|
| **Debug** | 0 | Debugging information | Execution continues, no intervention needed | Troubleshooting or testing pipeline behavior |
| **Info** | 1 | Informational message | Execution continues, no intervention needed | Expected conditions, optional data missing |
| **Warning** | 2 | Potential issue requiring attention | Execution continues, may need review | Data quality concerns, non-critical validation failures |
| **Error** | 3 | Stage failure | Current stage fails, pipeline continues to next stage | Critical validation failures, required data missing |
| **Fatal** | 4 | Pipeline failure | Entire pipeline stops immediately | Database connectivity lost, configuration invalid, critical system failure |

## Error Code Structure

Error codes follow the pattern: `STNNN`

- **S** (Stage): Single character identifying the source
  - `0` = Orchestration
  - `1` = Stage 10 (Discovery)
  - `2` = Stage 20 (Transformation)
  - `3` = Stage 30 (Processing)
  - `4` = Stage 40 (Post-Processing)
  - `5` = Stage 50 (Warehousing)
  - `6` = Stage 60 (Data Quality)
  - `7` = Stage 70 (Outputs)
  - `8` = Stage 80 (Automation)
  - `9` = Stage 90 (Reporting)
  - `A` = Core/Utility modules

- **T** (Type): Issue category
  - `1` = Input/Source issues
  - `2` = Processing/Logic issues
  - `3` = Output/Export issues
  - `4` = Validation issues
  - `5` = Connection/Infrastructure issues
  - `9` = Other/Miscellaneous

- **NNN** (Number): Sequential identifier (001-999)

### Examples
- `A501` = Core utilities, Connection issue #1
- `1101` = Stage 10, Input issue #1
- `3401` = Stage 30, Validation issue #1

## Error Object Structure

```powershell
[PSCustomObject]@{
    Timestamp       = "2025-01-19 14:30:45"
    ExecutionID     = "guid-here"
    Stage           = "10-Discovery"
    Severity        = "Warning"
    ErrorCode       = "1101"
    Message         = "Source file not found in expected location"
    TechnicalDetail = "FileNotFoundException: C:\Input\data.csv"
    RecordContext   = @{
        FileName = "data.csv"
        ExpectedPath = "C:\Input"
    }
    Recommendation  = "Verify input file path in configuration or check Stage 10 manifest"
}
```

## Defined Error Codes

Refer to ErrorCodes.json for individual defined error codes

## Adding New Error Codes

When implementing new error handling:

1. **Choose appropriate severity** based on impact
2. **Assign next sequential code** in the appropriate S-T category
3. **Document in this file** with clear description and recommendation
4. **Use `New-PipelineError`** function for consistency
5. **Update examples** in code comments if introducing new patterns

## Usage Examples

```powershell
# Creating an error
$error = New-PipelineError `
    -Context $Context `
    -Severity "Warning" `
    -ErrorCode "1101" `
    -Message "Expected source file not found: data.csv" `
    -TechnicalDetail $_.Exception.Message `
    -RecordContext @{ FileName = "data.csv"; ExpectedPath = $inputPath } `
    -Recommendation "Check input directory and file naming conventions"

# Adding to context
$Context.Errors += $error

# Checking for critical errors
$criticalErrors = $Context.Errors | Where-Object { $_.Severity -in @('Error', 'Fatal') }
if ($criticalErrors.Count -gt 0) {
    # Handle appropriately
}
```

---

**Note**: Error codes should never be reused or changed once deployed to production.
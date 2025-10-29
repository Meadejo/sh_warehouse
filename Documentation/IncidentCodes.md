# Pipeline Incident Code Reference

## Overview

The pipeline uses a standardized incident object structure to track issues during execution. This document defines severities, code structure, and principles.
All defined incident codes are found in IncidentCodes.json

## Incident Severity Levels

| Severity | Value | Description | Pipeline Behavior | When to Use |
|----------|-------|-------------|-------------------|-------------|
| **Debug** | 0 | Debugging information | Execution continues, no intervention needed | Troubleshooting or testing behavior |
| **Info** | 1 | Informational message | Execution continues, no intervention needed | Expected conditions, optional data missing |
| **Warning** | 2 | Potential issue requiring attention | Execution continues, may need review | Data quality concerns, non-critical validation failures |
| **Error** | 3 | Stage failure | Current stage fails, pipeline continues to next stage | Critical validation failures, required data missing |
| **Fatal** | 4 | Pipeline failure | Entire pipeline stops immediately | Configuration invalid, critical system failure |

## Incident Code Structure

Incident codes follow the pattern: `LST_NNN`

- **L** (Level): Level of Severity
  - `D` = Debug
  - `I` = Info
  - `W` = Warning
  - `E` = Error
  - `F` = Fatal
  
- **S** (Stage): Single character identifying the source
  - `0` = Orchestration
  - `1` = Discovery
  - `2` = Transformation
  - `3` = Data Processing
  - `4` = Post-Processing
  - `5` = Warehousing
  - `6` = Data Quality
  - `8` = Automation
  - `9` = Reporting
  - `U` = Utility

- **T** (Type): Issue category
  - `C` = Configuration issues
  - `S` = Staging/Sequencing issues
  - `F` = File I/O issues
  - `I` = Infrastructure/Connection issues
  - `P` = Processing/Logic issues
  - `D` = Database/SQL issues
  - `O` = Data Object issues (Validation, Typing, etc.)
  - `M` = Miscellaneous/Other


- **NNN** (Number): Sequential identifier (001-999)

### Examples
- `F0S_001` = Fatal Orchestration Staging issue #1
- `E1F_001` = Error in Discovery (Stage 10) File I/O; issue #1
- `I3P_001` = Info re: Data Processing (Stage 30); item #1

## Incident Object Structure

```powershell
[PSCustomObject]@{
    Timestamp       = "2025-01-19 14:30:45"
    ExecutionID     = "guid-here"
    Stage           = "10-Discovery"
    Severity        = "Warning"
    IncidentCode    = "1101"
    Message         = "Source file not found in expected location"
    TechnicalDetail = "FileNotFoundException: C:\Input\data.csv"
    RecordContext   = @{
        FileName = "data.csv"
        ExpectedPath = "C:\Input"
    }
    Recommendation  = "Verify input file path in configuration or check Stage 10 manifest"
}
```

## Defined Incident Codes

Refer to IncidentCodes.json for individual defined incident codes

## Adding New Incident Codes

When implementing new incident handling:

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

**Note**: Incident codes should never be reused or changed once deployed to production.
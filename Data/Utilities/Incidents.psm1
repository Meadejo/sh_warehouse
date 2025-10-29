<#
.SYNOPSIS
    TODOC Brief module description
.DESCRIPTION
    TODOC Detailed module description
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: October 17, 2025
    Updated: October 25, 2025
    Module: Incidents.psm1
#>

#region Script Parameters
$Script:CurrentLogFile = $null
$script:SeverityLevels = @{
    'Debug'   = 0
    'Info'    = 1
    'Warning' = 2
    'Error'   = 3
    'Fatal'   = 4
}
#endregion Script Parameters


#region Initialization
function Initialize-Logging {
    <#
    .SYNOPSIS
        TODOC Brief function description
    .DESCRIPTION
        TODOC Detailed description
    .PARAMETER ParameterName
        TODOC Parameter description
    .EXAMPLE
        TODOC Verb-Noun -ParameterName "Value"
    .OUTPUTS
        TODOC [PSCustomObject] with properties: Property1, Property2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ScriptName,
        [Parameter(Mandatory=$true)]
        [PSObject]$Config,
        [string]$LogDirectory
    )
    
    if (-not $LogDirectory) {
        $LogDirectory = $Config.Directories.Logs
    }
    
    # Set the current log file
    $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $LogFile = "$ScriptName`_$Timestamp.log"

    $Script:CurrentLogFile = Join-Path $LogDirectory $LogFile
        
    return $Script:CurrentLogFile
}
#endregion Initialization

#region Primitives
function New-ErrorObj {
    <#
    .SYNOPSIS
        TODOC Brief function description
    .DESCRIPTION
        TODOC Detailed description
    .PARAMETER ParameterName
        TODOC Parameter description
    .EXAMPLE
        TODOC Verb-Noun -ParameterName "Value"
    .OUTPUTS
        TODOC [PSCustomObject] with properties: Property1, Property2
    #>
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context,
        [Parameter(Mandatory=$true)]
        [string]$ErrorCode,
        [string]$Message            = "",
        [string]$Detail             = "",
        [string]$Recommendation     = "",
        [hashtable]$RecordContext   = @{}
    )
    
    # Lookup error definition
    $Definition = $Context.IncidentCodes[$ErrorCode]
    
    if (-not $Definition) {
        Write-Warning "Unknown error code: $ErrorCode - using defaults"
        $Definition = @{
            Level = "Error"
            Message = "Unknown error"
            Recommendation = "Check error code definition"
        }
    }
    
    # Use provided values or fall back to definitions
    $FinalMessage = if ($Message) { $Message } else { $Definition.Message }
    $FinalRecommendation = if ($Recommendation) { $Recommendation } else { $Definition.Recommendation }
    
    return [PSCustomObject]@{
        PSTypeName      = 'Error'
        Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ExecutionID     = $Context.ExecutionID
        Stage           = $Context.StageName
        Severity        = $Definition.Level
        Code            = $ErrorCode
        Message         = $FinalMessage
        Detail          = $Detail
        Recommendation  = $FinalRecommendation
        Context         = $RecordContext
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a formatted log entry to the pipeline log file
    .DESCRIPTION
        Writes timestamped, structured log entries with consistent formatting.
        Optionally writes to console based on context settings.
    .PARAMETER Context
        Pipeline context object containing log file path and settings
    .PARAMETER Level
        Log level (Debug, Info, Warning, Error, Fatal)
    .PARAMETER Message
        Primary log message
    .PARAMETER Detail
        Optional technical details or additional context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context,    
        [ValidateSet('Debug','Info','Warning','Error','Fatal')]
        [string]$Level = 'Info',  
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$Detail = "",
        [string]$Recommendation = ""
    )
    
    try {
        # Format timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Build log entry
        $logEntry = "[$timestamp] [$Level] [$($Context.StageName)] $Message"
        
        # Add detail if provided
        if ($Detail) {
            $logEntry += "`n    Detail: $Detail"
        }
        # Add recommendation if provided
        if ($Recommendation) {
            $logEntry += "`n    Recommendation: $Recommendation"
        }
        
        # Write to log file
        Add-Content -Path $Context.Logging.LogFile -Value $logEntry -ErrorAction SilentlyContinue
        
        # Write to console if configured
        if ($Context.Logging.WriteToConsole) {
            switch ($Level) {
                'Debug'   { Write-Host $logEntry -ForegroundColor Gray }
                'Info'    { Write-Host $logEntry -ForegroundColor Cyan }
                'Warning' { Write-Warning $logEntry }
                'Error'   { Write-Host $logEntry -ForegroundColor Red }
                'Fatal'   { Write-Host $logEntry -ForegroundColor Red -BackgroundColor Yellow }
            }
        }

        # # Add to Context Metrics
        # if (-not $Context.Metrics.ContainsKey($Context.StageName)) {
        #     $Context.Metrics[$Context.StageName] = @{
        #         "Warning"  = 0
        #         "Error"    = 0
        #     }
        # }
        # if ($Level -in @('Warning', 'Error')) {
        #     $Context.Metrics[$Context.StageName][$Level] += 1
        # }

    }
    catch {
        # Write to console as fallback
        Write-Warning "Failed to write to log: $_"
        Write-Host $Message -ForegroundColor Yellow
    }
}
#endregion Primitives

#region Wrappers
function Register-Incident {
    <#
    .SYNOPSIS
        TODOC Brief function description
    .DESCRIPTION
        TODOC Detailed description
    .PARAMETER ParameterName
        TODOC Parameter description
    .EXAMPLE
        TODOC Verb-Noun -ParameterName "Value"
    .OUTPUTS
        TODOC [PSCustomObject] with properties: Property1, Property2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context,
        [ValidateSet('Debug','Info','Warning','Error','Fatal')]
        [string]$Level = 'Info',
        [Parameter(Mandatory=$true)]
        [string]$Code,
        [string]$Message,
        [string]$Detail,
        [hashtable]$RecordContext = @{},
        [string]$Recommendation
    )

    $Levels = $script:SeverityLevels
    $Default = @{
        Level   = $Level
        Message = 'Unknown Incident'
        Code    = 'CCW_000'
        Recommendation = $null
    }

    # Create Incident object
    try {
        # If an incident code is provided, use the lookup. Otherwise, use defaults.
        if ($Code) {
            $Definition = $Context.IncidentCodes[$Code]

            # Manage Unknown Codes
            if (-not $Definition) {
                $UnknownMessage = "Unknown incident code provided"
                $UnknownDetail = "Code provided: $Code"

                Write-Log -Context $Context -Level "Warning" -Message $UnknownMessage `
                    -Detail $UnknownDetail

                $Definition = $Default
            }
        }
        else {
            # BUG Really should validate and handle if there's no Code AND no Message.
            $Definition = $Default
        }

        # Set final fields for Incident object
        $FinalCode =  if ($Code) { $Code } else { $Definition.Code }
        $FinalMessage = if ($Message) { $Message } else { $Definition.Message }
        $FinalDetail = if ($Detail) { $Detail } else { $null }
        $FinalRecommendation = if ($Recommendation) { $Recommendation } else { $Definition.Recommendation }

        $Incident = [PSCustomObject]@{
            PSTypeName      = 'Incident'
            Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ExecutionID     = $Context.ExecutionID
            Stage           = $Context.StageName
            Level           = $Definition.Level
            Code            = $FinalCode
            Message         = $FinalMessage
            Detail          = $FinalDetail
            Recommendation  = $FinalRecommendation
            Context         = $RecordContext
        }
        
        # Ignore items below Configured IncidentLevel
        if ($Levels[$Incident.Level] -lt $Levels[$Context.Config.IncidentLevel]) {
            return
        }

        # Handle Error/Fatal items as necessary
        if ($Incident.Level -in @('Error', 'Fatal')) {
            $ErrorObj = New-ErrorObj -Context $Context -ErrorCode $Code `
                -Message $Message -Detail $Detail `
                -Recommendation $Recommendation -RecordContext $RecordContext

            $Context.Errors += $errorObj
            $Context.HasErrors = $true
            if ($Incident.Level -eq 'Fatal') {
                $Context.HasFatalErrors = $true
            }
        }
    }
    catch {
        # If object creation and error handling fails, write a warning and bail
        Write-Warning "Failed to create incident object: $_"
        $Context.HasErrors = $true
        $Context.HasFatalError = $true
        throw
    }    

    # Track the Incident object
    try {
        # Add to context collection
        if (-not $Context.Incidents.ContainsKey($Context.StageName)) {
            $Context.Incidents[$Context.StageName] = @{
                'Info'      = @()
                'Warning'   = @()
                'Error'     = @()
                'Fatal'     = @()
            }
        }
        if (-not $Context.Metrics.ContainsKey($Context.StageName)) {
            $Context.Metrics[$Context.StageName] = @{
                'Info'      = 0
                'Warning'   = 0
                'Error'     = 0
                'Fatal'     = 0
            }
        }

        if ($Definition.Level -ne 'Debug') {
            $Context.Incidents[$Context.StageName][$Definition.Level] += $Incident
            $Context.Metrics[$Context.StageName][$Definition.Level] += 1
        }
    }
    catch {
        Write-Warning "Failed to track incident: $_"
        return
    }
        
    # Perform required logging
    if ($Levels[$Incident.Level] -ge $Levels[$Context.Config.LogLevel]) {
        Write-Log -Context $Context -Level $Incident.Level -Message $Incident.Message `
            -Detail $Incident.Detail -Recommendation $Incident.Recommendation
    }
}

function Write-StageSummaryReport {
    <#
    .SYNOPSIS
        Writes a formatted stage summary report to the log
    .DESCRIPTION
        Iterates through $Context.StageSummary items and writes them to the log
        with formatted status indicators. Provides a clean summary of stage actions.
    .PARAMETER Context
        Pipeline context object containing StageSummary array
    .EXAMPLE
        Write-StageSummaryReport -Context $Context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context
    )

    try {
        if (-not $Context.StageSummary -or $Context.StageSummary.Count -eq 0) {
            Write-Verbose "No stage summary items to report"
            return
        }

        Write-Log -Context $Context -Level "Info" -Message "=== Stage Summary Report ==="

        foreach ($item in $Context.StageSummary) {
            # Determine status symbol
            $statusSymbol = switch ($item.Status) {
                "Success" { "[✓]" }
                "Warning" { "[!]" }
                "Failed"  { "[✗]" }
                "Skipped" { "[-]" }
                default   { "[ ]" }
            }

            # Write summary item
            Write-Log -Context $Context -Level "Info" `
                -Message "$statusSymbol $($item.Action)" `
                -Detail $item.Detail
        }

        Write-Log -Context $Context -Level "Info" -Message "=== End Stage Summary ==="
    }
    catch {
        Write-Warning "Failed to write stage summary report: $_"
    }
}
#endregion Wrappers

Export-ModuleMember -Function *

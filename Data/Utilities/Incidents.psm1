<#
.SYNOPSIS
    TODOC Brief module description
.DESCRIPTION
    TODOC Detailed module description
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: October 17, 2025
    Updated: October 20, 2025
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
        [PSCustomObject]$Context,
        [string]$ErrorCode,
        [string]$Message = "",  # Now optional - can use default from definition
        [string]$Detail = "",
        [hashtable]$RecordContext = @{},
        [string]$Recommendation = ""  # Also optional
    )
    
    # Lookup error definition
    $Definition = $Context.ErrorCodes[$ErrorCode]
    
    if (-not $Definition) {
        Write-Warning "Unknown error code: $ErrorCode - using defaults"
        $Definition = @{
            Severity = "Error"
            DefaultMessage = "Unknown error"
            DefaultRecommendation = "Check error code definition"
        }
    }
    
    # Use provided values or fall back to definitions
    $FinalMessage = if ($Message) { $Message } else { $Definition.DefaultMessage }
    $FinalRecommendation = if ($Recommendation) { $Recommendation } else { $Definition.DefaultRecommendation }

    # Immediately throw for all fatal errors.
    if ($Definition.Severity -eq 'Fatal') {
        $Context.HasCriticalErrors = $true
        Write-Log -Context $Context -Level $Level -Message $FinalMessage
        throw "Fatal error: $FinalMessage"
    }
    
    return [PSCustomObject]@{
        Timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ExecutionID     = $Context.ExecutionID
        Stage           = $Context.StageName
        Severity        = $Definition.Severity
        ErrorCode       = $ErrorCode
        Message         = $FinalMessage
        Detail          = $Detail
        RecordContext   = $RecordContext
        Recommendation  = $FinalRecommendation
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
        Log level (Info, Warning, Error, Fatal)
    .PARAMETER Message
        Primary log message
    .PARAMETER Detail
        Optional technical details or additional context
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context,        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Debug','Info','Warning','Error','Fatal')]
        [string]$Level = 'Info',  
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$Detail = "",
        [Parameter(Mandatory=$false)]
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

        # Add to Context Metrics
        if (-not $Context.Metrics.ContainsKey($Context.StageName)) {
            $Context.Metrics[$Context.StageName] = @{
                "Warning"  = 0
                "Error"    = 0
            }
        }
        if ($Level -in @('Warning', 'Error')) {
            $Context.Metrics[$Context.StageName][$Level] += 1
        }

    }
    catch {
        # Write to console as fallback
        Write-Warning "Failed to write to log: $_"
        Write-Host $Message -ForegroundColor Yellow
    }
}
#endregion Primitives

#region Wrappers
function Trace-Incident {
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
        [string]$Level = "Info",
        [string]$Message,
        [string]$ErrorCode,
        [string]$Detail,
        [hashtable]$RecordContext = @{},
        [string]$Recommendation
    )

    # Immediately throw for all fatal errors.
    if ($Level -eq 'Fatal') {
        $Context.HasCriticalErrors = $true
        Write-Log -Context $Context -Level $Level -Message $Message
        throw "Fatal error: $Message"
    }

    # Error handling
    if ($ErrorCode) {
        try {
            # Create error object
            # BUG Incident Level and Error Severity can conflict.
            $ErrorObj = New-ErrorObj -Context $Context -ErrorCode $ErrorCode `
                -Message $Message -Detail $Detail `
                -Recommendation $Recommendation -RecordContext $RecordContext
            
            if ($ErrorObj.Severity -ne 'Error') {
                $Level = $ErrorObj.Severity
            }
            
            # Add to context error collection
            if (-not $Context.Incidents.ContainsKey($Context.StageName)) {
                $Context.Incidents[$Context.StageName] = @{
                    'Warning'   = 0
                    'Error'     = 0
                }
            }
            if ($Level -in @('Warning', 'Error')) {
                $Context.Metrics[$Context.StageName][$Level] += 1
            }
            $Context.Errors += $errorObj

            # Adjust termination flags
            if ($Level -in @('Error', 'Fatal')) {
                $Context.HasCriticalErrors = $true
            }

            # If there was no Message provided, use the error DefaultMessage
            if (-not $Message) {
                $Message = $ErrorObj.Message
            }

            # If there was no Recommendation provided, use the error DefaultRecommendation
            if (-not $Recommendation) {
                $Recommendation = $ErrorObj.Recommendation
            }
        }
        catch {
            # If error handling itself fails, write a warning and throw
            Write-Warning "Failed to create error object: $_"
            throw
        }
    }
    
    #Perform necessary logging
    if ($script:SeverityLevels[$Level] -ge $script:SeverityLevels[$Context.Config.LogLevel]) {
        Write-Log -Context $Context -Level $Level -Message $Message -Detail $TechnicalDetail `
            -Recommendation $Recommendation
    }

    # Return error object for tracking
    return $ErrorObj
}
#endregion Wrappers

Export-ModuleMember -Function *

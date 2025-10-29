<#
.SYNOPSIS
    TODOC Brief module description
.DESCRIPTION
    TODOC Detailed module description
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: [Date]
    Updated: [Date]
    Script: [ScriptName].ps1

    All Stage scripts (10-90) return a standardized object with [Success], [Data], and [Errors] properties.
    Primary error handling is managed from Stage scripts.
    Any Main Stage script (ending in 0) can function as the start point for the pipeline.
#>

#Requires -Version 5.1


#region Script Parameters
[CmdletBinding()]
param(
    [PSCustomObject]$Context,
    [string]$ConfigPath
)

# TODO - Correct Stage Number
$StageNumber = "00"
$ReturnObject = [PSCustomObject]@{
    Success = $false
    Data = $null
    Errors = @()
}
#endregion Script Parameters


#region Functions
function Step-Work {
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

    )

    try {
        # Do Stuff
    }
    catch {
        # Manage Failures
    }
}
#endregion Functions


#region Stage Start

# Confirm that the orchestration context exists
# NOTE Error management for bootstrap functions are managed in-line.
try {
    if (-not $Context) {
        Import-Module "$PSScriptRoot\Data\Utilities\Staging.psm1" -Force
        $Context = Initialize-Pipeline -OriginStageNumber $StageNumber -ConfigPath $ConfigPath

        if (-not $Context) {
            throw
        }
    }
}
catch {
    return $ReturnObject
}

# Perform basic validations and start the Stage
try {
    # Import Required Modules
    $IncidentModule = $Context.Config.Utilities.Incidents
    Import-Module $IncidentModule

    # Confirm Stage Number matches expected stage before start
    if ($StageNumber -ne $Context.NextStageNumber) {
        # TODO
    }

    # Start the Stage
    $StartStage = Start-Stage -Context $Context -StageNumber $StageNumber
    if (-not $StartStage) {
        # TODO 
        throw "ErrorCode"
    }    
}
catch {
    # Log and report failure details
    Register-Incident -Context $Context -ErrorCode $_.Exception.Message `
        -Detail $_.ScriptStackTrace -Message $Message -Record $Record
    
    return [PSCustomObject]@{
        Success = $false
        Data = $null
        Errors = $Errors
    }
}
#endregion Stage Start


#region Process & Logic
try {
    # Function logic here
    if ($FunctionError) {
        $Message = "Message details here"
        $Record = "[Data Object]"
        throw "CC-TEST"
    }

    # Return standardized object
    return [PSCustomObject]@{
        Success = $true
        Data = $result
        Errors = $Errors
    }
}
catch {
    # Log and report failure details
    Register-Incident -Context $Context -ErrorCode $_.Exception.Message `
        -Detail $_.ScriptStackTrace -Message $Message -Record $Record
    
    return [PSCustomObject]@{
        Success = $false
        Data = $null
        Errors = $Errors
    }
}
#endregion Process & Logic


#region Stage Stop
Stop-Stage -Context $Context
#endregion Stage Stop

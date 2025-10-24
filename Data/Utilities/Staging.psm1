<#
.SYNOPSIS
    TODOC Brief module description
.DESCRIPTION
    TODOC Detailed module description
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: October 14, 2025
    Updated: October 21, 2025
    Version: 1.0
    Module: Staging.psm1
#>

#Requires -Version 5.1

#region Init Items
function Initialize-Pipeline {
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

    # NOTE This module has non-standard error management.

    [CmdletBinding()]
    param(
        [string]$OriginStageNumber = "00",
        [string]$ConfigPath
    )
    function Get-PipelineConfig {
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
        $ConfigPaths = @()
    
        try {
            if ($ConfigPath) { $ConfigPaths += $ConfigPath }
            $ConfigPaths += @(
                "E:\Data_Pipeline\Data\Config.psd1",
                "$PSScriptRoot\Data\Config.psd1"
            )

            foreach ($Path in $ConfigPaths) {
                if ($Path -and (Test-Path $Path)) {
                    $Config = Import-PowerShellDataFile $Path
                    Write-Verbose "Loaded config from: $Path"
                    break
                }
            }

            if (-not $Config) {
                Write-Error "FATAL: No valid configuration file found. Searched: $($ConfigPaths -join ', ')"
                throw
            }

            return $Config

        }
        catch {
            Write-Error "FATAL: Unable to load configuration. $_" -ErrorAction Stop
            throw
        }
    }

    # Pull Configuration data
    $Config = Get-PipelineConfig
    $IncidentsModule = $Config.Utilities.Incidents
    Import-Module $IncidentsModule -Force

    # Set the logging path
    try {
        $StageName = $Config.Stages[$OriginStageNumber].Name
        $LogFile = Initialize-Logging -ScriptName $StageName -Config $Config

        if (-not $LogFile) {
            Write-Error "FATAL: Unable to establish logging path"
            throw
        }
    }
    catch {
        Write-Error "FATAL: Error initializing logging $_" -ErrorAction Stop
        throw
    }    

    # Create the context object
    try {
        $Context = Initialize-PipelineContext -LogFile $LogFile -Config $Config `
            -StageNumber $OriginStageNumber
            
        if (-not $Context) {
            Write-Error "FATAL: Unable to establish pipeline context"
            throw
        }
    }
    catch {
        Write-Error "FATAL: Error initializing pipeline context $_" -ErrorAction Stop
        throw
    }

    Add-StaticData -Context $Context

    Trace-Incident -Context $Context -Message "Pipeline context initialized. Beginning stages." | Out-Null

    return $Context
}

function Initialize-PipelineContext {
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
        [string]$StageNumber = "00",
        [PSObject]$Config,
        [string]$LogFile,

        [switch]$Skip10,
        [switch]$Skip20,
        [switch]$Skip30,
        [switch]$Skip40,
        [switch]$Skip50,
        [switch]$Skip60,
        [switch]$Skip70,
        [switch]$Skip80,
        [switch]$Skip90
    )

    # Confirm that Config has settings for the stage
    try {
        $OriginStage = $Config.Stages[$StageNumber]
        $NextStageNumber = $OriginStage.NextStageNumber
        $Stage = $Config.Stages["00"]
        $StageName = $Stage.Name
    }
    catch {
        Write-Error "FATAL: No definition for Pipeline Stage $StageNumber" -ErrorAction Stop
        throw
    }

    # Create and return the context object
    try {
        # Extract skipped stages from bound parameters
        $SkipStages = $PSBoundParameters.Keys | 
                Where-Object { $_ -match '^Skip\d+$' -and $PSBoundParameters[$_] } |
                ForEach-Object { $_ -replace 'Skip', '' }

        $Context = [PSCustomObject]@{
            # Execution Metadata
            StartTime = (Get-Date)
            ExecutionID = [guid]::NewGuid().ToString()  # Unique run identifier for correlation

            # Stage Data
            OriginStage = $OriginStage
            Stage = $Stage
            StageName = $StageName # For convenience
            StageStartTime = $null
            NextStageNumber = $NextStageNumber
            SkipStages = $SkipStages
            
            # Static Data
            Config = $Config
            ErrorCodes = $null
            ProjectDetails = $null
            HUDSchema = $null
            
            # Incident Management
            Logging = @{
                LogFile = $LogFile
                LogLevel = $Config.LogLevel  # Ignore logging for items below a given level
                WriteToConsole = $Config.WriteToConsole
            }
            Errors = @()  # Collection of error objects
            Incidents = @{}  # Counts of warnings and errors by stage
            HasCriticalErrors = $false
            StageSummary = @()
            
            # Database
            # Database = @{
            #     Connection = $null  # Will hold connection object when needed
            #     Server = $Config.Database.Server
            #     Name = $Config.Database.Name
            #     IsConnected = $false
            # }

            # Manifest Memory
            ManifestIn = $null
            ManifestOut = $null
            Manifests = @{}
                        
            # Results/Metrics (for orchestration to track)
            Metrics = @{
                # RecordsProcessed = 0
                # RecordsSkipped = 0
                # RecordsCreated = 0
                # etc. - stages can add to this
            }
        }

        return $Context

    }
    catch {
        return $null
    }    
}

function Add-StaticData {
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
        [ValidateNotNullOrEmpty()]
        [PSObject]$Context
    )
    function Get-ProjectDetails {
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

        if (-not (Test-Path $Context.Config.Static_Data.Project_Details)) {
            Trace-Incident -Context $Context -Level "Warning" -ErrorCode "A102" `
                -Detail $Context.Config.Static_Data.Project_Details
        }
        $ProjectDetails = Import-Csv $Config.Static_Data.Project_Details
        $Lookup = @{}

        foreach ($Project in $ProjectDetails) {
            if (-not [string]::IsNullOrWhiteSpace($Project.ProjectID)) {
                $Lookup[$Project.ProjectID] = @{
                    CommonName      = $Project.CommonName
                    ReportName      = $Project.ReportName
                    HUDType         = $Project.HUDType
                    OperationStart  = $Project.OperationStart
                    System          = $Project.System
                    SourceID        = $Project.SourceID
                    ProjectName     = $Project.ProjectName
                    EnrollmentGroup = $Project.EnrollmentGroup
                    ReportingGroups = $Project.ReportingGroups
                }
            }
        }

        return $Lookup
    }

    # Add Error Codes
    $FailMessage = "Unable to load error lookups."
    try {
        $ErrorCodeFile = $Config.Static_Data.Error_Codes
        $ErrorCodes = Get-Content $ErrorCodeFile | ConvertFrom-Json -AsHashtable

        if (-not $ErrorCodes) {
            Trace-Incident -Context $Context -Level "Warning" -Message $FailMessage `
                -Detail $ErrorCodeFile
        } else {
            $Context.ErrorCodes = $ErrorCodes
        }
    }
    catch {
        Trace-Incident -Context $Context -Level "Warning" -Message $FailMessage -Detail $ErrorCodeFile
    }

    # Add HUD Schema
    try {
        $HUD_SchemaFile = $Config.Static_Data.HUD_Schema
        $HUD_Schema = Get-Content $HUD_SchemaFile | ConvertFrom-Json -AsHashtable

        if (-not $HUD_Schema) {
            Trace-Incident -Context $Context -Level "Warning" -ErrorCode "A101" `
                -Detail $HUD_SchemaFile
        } else {
            $Context.HUDSchema = $HUD_Schema
        }
    }
    catch {
        Trace-Incident -Context $Context -Level "Warning" -ErrorCode "A101" -Detail $HUD_SchemaFile
    }

    # Add Project Data
    try {
        $ProjectDetails = Get-ProjectDetails

        if (-not $ProjectDetails) {
            Trace-Incident -Context $Context -Level "Warning" -ErrorCode "A102"
        } else {
            $Context.ProjectDetails = $ProjectDetails
        }
    }
    catch {
        Trace-Incident -Context $Context -Level "Warning" -ErrorCode "A102"
    }
}
#endregion Init Items

#region Stage Items
function Start-Stage {
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
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context,
        [PSCustomObject]$StageNumber
    )
    $Incidents = @()

    try {
        # Adjust Context
        $Stage = $Context.Config.Stages[$StageNumber]
        $Context.StageSummary = @()

        # Check and skip stage if necessary
        if ($StageNumber -in $Context.SkipStages) {
            $Incident = Trace-Incident -Context $Context -Level "Warning" `
                -Message "Skipping stage $StageNumber`, per Pipeline configuration."
            if ($Incident) {$Incidents += $Incident}

            return [PSCustomObject]@{
                Success = $false
                Data = $null
                Incidents = $Incidents
            }
        }

        # Log Stage Start
        $StartMessage = "=== Starting Stage: $($Stage.Name) ==="
        Trace-Incident -Context $Context -Message $StartMessage
        $Context.Stage = $Stage
        $Context.StageName = $Stage.Name
        $Context.StageStartTime = (Get-Date)
    }
    catch {
        # Log incident details
        $Incident = Trace-Incident -Context $Context -ErrorCode "0201" `
            -RecordContext $Context
        if ($Incident) {$Incidents += $Incident}
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }

    # Pull the ManifestIn
    if ($Stage.InputFrom) {
        Get-Manifest -Context $Context
    }

    # Create the ManifestOut
    if ($Stage.HasManifest) {
        $ManifestOut = New-Manifest -Context $Context
        if ($ManifestOut.Success) {
            $Context.ManifestOut = $ManifestOut.Data
        }
    }

    # Return standardized object
    return [PSCustomObject]@{
        Success = $true
        Data = $null
        Incidents = $Incidents
    }
}

function Stop-Stage {
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
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context
    )
    $Incidents = @()
    
    try {
        # Capture stage data before reset
        $StageName = $Context.Stage.Name
        $NextStageNumber = $Context.Stage.NextStageNumber
        $ControlStage = $Context.Config.Stages["00"]

        # Change Stage to Orchestration
        $Context.Stage = $ControlStage
        $Context.StageName = $ControlStage.Name
        if ($NextStageNumber) {
            $Context.NextStageNumber = $NextStageNumber
        }
        else {
            $Context.NextStageNumber = $null
        }

        # Log Stage End
        $CompleteMessage = "=== Completed Stage: $StageName ==="
        $DurationMessage = "Duration: $($((Get-Date) - $Context.StageStartTime).ToString('hh\:mm\:ss'))"
        Trace-Incident -Context $Context -Message $CompleteMessage
        Trace-Incident -Context $Context -Message $DurationMessage

        # Manage manifests
        if ($Context.ManifestIn) {
            $Context.ManifestIn = $null
        }
        if ($Context.ManifestOut) {
            Save-Manifest -Context $Context -StageName $StageName | Out-Null
            if ($Context.Manifests.ContainsKey($StageName)) {
                Trace-Incident -Context $Context -ErrorCode "0205"
            }
            $Context.Manifests[$StageName] = $Context.ManifestOut
            $Context.ManifestOut = $null
        }

        # Count Warnings
        if ($Context.Incidents.$StageName.Warning -gt 0) {
            $WarnMessage = "Warnings reported during stage: $($Context.Incidents.$StageName.Warning) `
                /n    Review logs for details"
            Trace-Incident -Context $Context -Message $WarnMessage -Level "Warning"
        }
        # Count Errors
        if ($Context.Incidents.$StageName.Error -gt 0) {
            $WarnMessage = "Errors reported during stage `
                /n    Stage may not have completed successfully `
                /n    Review logs for details"
            Trace-Incident -Context $Context -Message $WarnMessage -Level "Warning"
        }

        # WriteOut StageSummary
        if ($($Context.StageSummary).Count -gt 0) {
            foreach ($line in $Context.StageSummary) {
                Trace-Incident -Context $Context -Message $line
            }
        }

        # Return standardized object
        return [PSCustomObject]@{
            Success = $true
            Data = $null
            Incidents = $Incidents
        }
    }
    catch {
        # Log incident details
        $Incident = Trace-Incident -Context $Context -ErrorCode "0201" `
            -RecordContext $Context
        if ($Incident) {$Incidents += $Incident}
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }
}

function Stop-Pipeline {

}
#endregion Stage Items

#region Support Items
function Get-Manifest {<#
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
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context,

        [string]$ExplicitPath
    )
    $Incidents = @()
    
    try {
        # If this stage is expecting an input Manifest and it's in memory, set it as ManifestIn
        if ($Context.Stage.InputFrom -and $Context.Manifests.ContainsKey($Context.Stage.InputFrom)) {
            $Context.ManifestIn = $Context.Manifests[$Context.Stage.InputFrom]
            Trace-Incident -Context $Context -Message "Using $($Context.Stage.InputFrom) manifest from pipeline"

            return [PSCustomObject]@{
                Success = $true
                Data = $Manifest
                Incidents = $Incidents
            }
        }

        # Attempt to load explicit file
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path $ExplicitPath)) {
            $Manifest = Get-Content $ExplicitPath | ConvertFrom-Json -AsHashtable
            $Manifest = New-Manifest -JsonItem $Manifest
            if($Manifest.Success -and $Manifest.Data.Type -eq $Context.Stage.InputFrom) {
                $Context.ManifestIn = $Manifest.Data
                Trace-Incident -Context $Context -Message "Using provided manifest file: $ExplicitPath"

                return [PSCustomObject]@{
                    Success = $true
                    Data = $Manifest.Data
                    Incidents = $Incidents
                }
            } else {
                Trace-Incident -Context $Context -ErrorCode "0203"
                Trace-Incident -Context $Context -Message "Attempting fallback to latest $($Context.Stage.InputFrom) manifest..."
                if ($Incident) {$Incidents += $Incident}
            }
        } else {
            Trace-Incident -Context $Context -Message "No valid manifest file provided, searching for latest $($Context.Stage.InputFrom) manifest..."
        }

        # Failing a valid explicit filepath, search for all recent files of appropriate type
        $ManifestDirectory = $Context.Config.Directories.Manifests
        $MaxAge = $Context.Config.Housekeeping.Max_Manifest_Age_Used

        # If the Manifest directory is invalid, Error
        if (-not (Test-Path $ManifestDirectory)) {
            $Incident = Trace-Incident -Context $Context -ErrorCode "0101"
            if ($Incident) {$Incidents += $Incident}
            
            return [PSCustomObject]@{
                Success = $false
                Data = $null
                Incidents = $Incidents
            }
        }

        # Assuming the directory is good, we look for an appropriate manifest
        $SearchPattern = "$($Context.Stage.InputFrom)`_*.json"
        $ManifestFiles = Get-ChildItem -Path $ManifestDirectory -Filter $SearchPattern | Sort-Object LastWriteTime -Descending
        if ($ManifestFiles.Count -eq 0) {
            $Incident = Trace-Incident -Context $Context -ErrorCode "0102" -Detail $SearchPattern
            if ($Incident) {$Incidents += $Incident}
            
            return [PSCustomObject]@{
                Success = $false
                Data = $null
                Incidents = $Incidents
            }
        }

        $CutoffTime = (Get-Date).AddHours(-$MaxAge)
        $RecentManifests = $ManifestFiles | Where-Object { $_.LastWriteTime -gt $CutoffTime }
        if ($RecentManifests.Count -eq 0) {
            $Incident = Trace-Incident -Context $Context -ErrorCode "0103" `
                -Detail "Newest available file: $($ManifestFiles[0].Name) created $($ManifestFiles[0].LastWriteTime)"
            if ($Incident) {$Incidents += $Incident}
            
            return [PSCustomObject]@{
                Success = $false
                Data = $null
                Incidents = $Incidents
            }
        }

        # Starting from newest, attempt to load each discovered fallback file
        foreach ($File in $RecentManifests) {
            try {
                $Manifest = Get-Content $File | ConvertFrom-Json -AsHashtable
                $Manifest = New-Manifest -JsonItem $Manifest
                if($Manifest.Success -and $Manifest.Data.Type -eq $Context.Stage.InputFrom) {
                    $Context.ManifestIn = $Manifest.Data
                    $Incident = Trace-Incident -Context $Context -Message "Using fallback manifest: $File"

                    return [PSCustomObject]@{
                        Success = $true
                        Data = $Manifest.Data
                        Incidents = $Incidents
                    }
                }
            } catch {
                $Incident = Trace-Incident -Context $Context -ErrorCode "0104" -Detail $File
                if ($Incident) {$Incidents += $Incident}
            }
        }

        # If no suitable file is found, return null
        $Incident = Trace-Incident -Context $Context -Message "No suitable $Context.Stage.InputFrom manifest found for fallback"
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }
    catch {
        # Log incident details
        $Incident = Trace-Incident -Context $Context -ErrorCode "0105"
        if ($Incident) {$Incidents += $Incident}
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }
}

function New-Manifest {
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
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context,
        [hashtable]$JsonItem = $null
    )
    $Incidents = @()
    
    try {
        # To restore completely from json (Restore Input Manifest)
        if ($JsonItem) {
            $Type               = $JsonItem.Type
            $DateGenerated      = [datetime]$JsonItem.DateGenerated
            $InputManifest      = $JsonItem.InputManifest
            $SavePath           = $JsonItem.SavePath
            $SaveName           = $JsonItem.SaveName
            $Data               = $JsonItem.Data
            $Metrics            = $JsonItem.Metrics
        }

        # To create from scratch (Create Output Manifest)
        else {
            $Stage              = $Context.Stage

            $Type               = $Stage.Name
            $DateGenerated      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $SavePath           = $Context.Directories.Manifests
            $SaveName           = $null

            switch ($Stage.Number) {
                '10' {
                    $Data = @{
                        Files = @()
                    }
                    $Metrics = @{
                        Regions = @{}
                        FileTypes = @{}
                        TotalFiles = 0
                        ValidFiles = 0
                        InvalidFiles = 0
                    }
                }
                Default {}
            }

            if ($Context.ManifestIn) {
                $InputManifest  = $Context.ManifestIn.SaveName
            }
            else {
                $InputManifest  = $null
            }
        }

        $Manifest = [PSCustomObject]@{
            PSTypeName          = 'Manifest'
            Type                = $Type
            DateGenerated       = $DateGenerated
            InputManifest       = $InputManifest
            SavePath            = $SavePath
            SaveName            = $SaveName
            Data                = $Data
            Metrics             = $Metrics
        }

        # Return standardized object
        return [PSCustomObject]@{
            Success = $true
            Data = $Manifest
            Incidents = $Incidents
        }
    }
    catch {
        # Log incident details
        $Incident = Trace-Incident -Context $Context -ErrorCode "0105"
        if ($Incident) {$Incidents += $Incident}
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }
}

function  Save-Manifest {
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
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context,
        [string]$StageName
    )
    $Incidents = @()
    
    try {
        $Manifest = $Context.ManifestOut
        $Config = $Context.Config
        if (-not $StageName) {
            $StageName = $Context.StageName
        }

        # Confirm if the ManifestOut Path was specified in the Stage properties
        $ManifestPath = $Manifest.SavePath
        if (-not $ManifestPath) {
            $ManifestPath = $Config.Directories.Manifests
            $Manifest.SavePath = $ManifestPath
        }

        # Timestamp the file and note the filename to be logged.
        $Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $ManifestFile = "$StageName`_$Timestamp.json"
        $Manifest.SaveName = $ManifestFile
        $ManifestFilePath = Join-Path $ManifestPath $ManifestFile
        Trace-Incident -Context $Context -Message "Manifest save path: $ManifestFilePath" -Level "Debug"

        # Break any Client or Project embeddings in Enrollments
        if ("Enrollments" -in $Manifest.Data.Keys) {
            foreach ($Enrollment in $Manifest.Data.Enrollments.Values) {
                if ($Enrollment -is [hashtable]) {
                    if ($Enrollment.ContainsKey("Client")) {
                        $Enrollment.Client = $null
                    }
                    if ($Enrollment.ContainsKey("Project")) {
                        $Enrollment.Project = $null
                    }
                } else {
                    $Enrollment.Client = $null
                    $Enrollment.Project = $null
                }
            }
        }

        # Actually save the file
        $Manifest | ConvertTo-Json -Depth $Config.Housekeeping.Max_Json_Depth | Out-File `
            -FilePath $ManifestFilePath -Encoding UTF8

        # Return standardized object
        return [PSCustomObject]@{
            Success = $true
            Data = $null
            Incidents = $Incidents
        }
    }
    catch {
        # Log incident details
        $Incident = Trace-Incident -Context $Context -ErrorCode "0206"
        if ($Incident) {$Incidents += $Incident}
        
        return [PSCustomObject]@{
            Success = $false
            Data = $null
            Incidents = $Incidents
        }
    }
}
#endregion Support Items

Export-ModuleMember -Function *

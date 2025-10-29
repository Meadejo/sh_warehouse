<#
.SYNOPSIS
    TODOC Brief module description
.DESCRIPTION
    TODOC Detailed module description
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: 10/27/2025
    Updated: 10/28/2025
    Module: run_pipeline.psm1
#>

#Requires -Version 5.1

#region Parameters
param(
    [ValidateSet(1,2,3,4,5,6,7,8,9)]
    [int]$StartStage,
    [ValidateSet(1,2,3,4,5,6,7,8,9)]
    [int]$StopStage,
    [switch]$Skip1,
    [switch]$Skip2,
    [switch]$Skip3,
    [switch]$Skip4,
    [switch]$Skip5,
    [switch]$Skip6,
    [switch]$Skip7,
    [switch]$Skip8,
    [switch]$Skip9
)
$AllStages = @(10, 20, 30, 40, 50, 60, 70, 80, 90)
#endregion Parameters

#region Functions
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
        [string]$ConfigPath,
        [int[]]$SkipStages  = @(),
        [int]$StartStage    = 10,
        [int]$StopStage     = 90
    )

    # Build list of stages to run
    try {
        # Filter AllStages by Start:Stop and SkipStages to create RunStages
        $RunStages = $AllStages | Where-Object {
            $withinStart = if ($StartStage) { $_ -ge $StartStage } else { $true }
            $withinStop = if ($StopStage) { $_ -le $StopStage } else { $true }
            $withinStart -and $withinStop
        }
        $RunStages = $RunStages | Where-Object { $_ -notin $SkipStages }
    }
    catch {
        throw "Error initializing staging sequence"
    }

    # Pull Configuration data and set the logging path
    try {
        $Config = Get-PipelineConfig -ConfigPath $ConfigPath

        if (-not $Config) {
            throw
        }

        $IncidentsModule = $Config.Utilities.Incidents
        Import-Module $IncidentsModule -Force

        $StageName = $Config.Stages["00"].Name
        $LogFile = Initialize-Logging -ScriptName $StageName -Config $Config

        if (-not $LogFile) {
            throw
        }
    }
    catch {
        throw "Error importing configuration and incident management"
    }    

    # Create the context object
    try {
        $Context = New-PipelineContext -LogFile $LogFile -Config $Config `
            -RunStages $RunStages
            
        if (-not $Context) {
            throw
        }
    }
    catch {
        throw "Error initializing pipeline context"
    }

    # Add Static Data
    Add-StaticData -Context $Context

    return $Context
}

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
    param(
        [string]$ConfigPath
    )
    # NOTE Atypical error handling, due to expected execution sequence
    
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
            Write-Error "No valid configuration file found. Searched: $($ConfigPaths -join ', ')"
        }

        return $Config

    }
    catch {
        Write-Error "Unable to load configuration. $_" -ErrorAction Stop
    }
}

function New-PipelineContext {
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
        [PSObject]$Config,
        [string]$LogFile,
        [int[]]$RunStages
    )

    # Confirm that Config has settings
    try {
        $Stage = $Config.Stages["00"]
        $NextStageNumber = $Stage.NextStageNumber
        $StageName = $Stage.Name
        $IncidentCodeFile = $Config.Static_Data.Incident_Codes
    }
    catch {
        Write-Warning "Pipeline configuration settings missing definitions"
        return $null
    }

    # Create and return the context object
    try {
        $Context = [PSCustomObject]@{
            # Execution Metadata
            StartTime = (Get-Date)
            ExecutionID = [guid]::NewGuid().ToString()  # Unique run identifier for correlation

            # Static Data
            Config = $Config
            IncidentCodes = Import-PowerShellDataFile $IncidentCodeFile
            ProjectDetails = $null
            HUDSchema = $null

            # Stage Data
            Stage = $Stage
            StageName = $StageName
            StageStartTime = $null
            NextStageNumber = $NextStageNumber
            RunStages = $RunStages
            StageResults = @{}
            
            # Incident Management
            Logging = @{
                LogFile = $LogFile
                LogLevel = $Config.LogLevel  # Ignore logging for items below a given level
                WriteToConsole = $Config.WriteToConsole
            }
            Errors = @()  # Collection of all error objects
            Incidents = @{}  # Collections of Incidents by stage
            HasErrors = $false
            HasFatalErrors = $false
            
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
                        
            # Results/Metrics (Collections of tracked Metrics by Stage)
            Metrics = @{}
            StageSummary = @()
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
            Register-Incident -Context $Context -Code "W0C_001" `
                -Detail $Context.Config.Static_Data.Project_Details
            throw
        }
        $ProjectDetails = Import-Csv $Context.Config.Static_Data.Project_Details
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

    # Add HUD Schema
    try {
        $HUD_SchemaFile = $Config.Static_Data.HUD_Schema
        $HUD_Schema = Get-Content $HUD_SchemaFile | ConvertFrom-Json -AsHashtable

        if (-not $HUD_Schema) {
            throw
        } else {
            $Context.HUDSchema = $HUD_Schema
        }
    }
    catch {
        Register-Incident -Context $Context -Code "W0C_002" -Detail $HUD_SchemaFile
    }

    # Add Project Data
    try {
        $ProjectDetails = Get-ProjectDetails

        if (-not $ProjectDetails) {
            throw
        } else {
            $Context.ProjectDetails = $ProjectDetails
        }
    }
    catch {
        Register-Incident -Context $Context -Code "W0C_003"
    }
}

function Get-Manifest {
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

        [string]$ExplicitPath
    )
    
    try {
        # If this stage is expecting an input Manifest and it's in memory, set it as ManifestIn
        if ($Context.Stage.InputFrom -and $Context.Manifests.ContainsKey($Context.Stage.InputFrom)) {
            $Manifest = $Context.Manifests[$Context.Stage.InputFrom]
            Register-Incident -Context $Context -Code 'I0S_002' `
                -Detail "Using $($Context.Stage.InputFrom) manifest from pipeline"
            return $Manifest
        }

        # Attempt to load explicit file
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path $ExplicitPath)) {
            $Manifest = Get-Content $ExplicitPath | ConvertFrom-Json -AsHashtable
            $Manifest = New-Manifest -JsonItem $Manifest

            if($Manifest.Type -eq $Context.Stage.InputFrom) {
                Register-Incident -Context $Context -Code '' `
                    -Detail "Using provided manifest file: $ExplicitPath"

                return $Manifest

            } else {
                Register-Incident -Context $Context -Code "I0S_002" `
                    -Detail "Using manifest from file: $ExplicitPath"
                Register-Incident -Context $Context -Code "W0F_001"
                    -Detail "Searching for manifest type: $($Context.Stage.InputFrom)"
            }
        } else {
            Register-Incident -Context $Context -Code "I0S_003"
                -Detail "Searching for manifest type: $($Context.Stage.InputFrom)"
        }

        # Failing a valid explicit filepath, search for all recent files of appropriate type
        $ManifestDirectory = $Context.Config.Directories.Manifests
        $MaxAge = $Context.Config.Housekeeping.Max_Manifest_Age_Used

        # If the Manifest directory is invalid, Error
        if (-not (Test-Path $ManifestDirectory)) {
            # Register-Incident -Context $Context -Code "E0C_001" -Detail "Manifest Directory: $ManifestDirectory"
            
            throw "Unable to locate manifest directory: $ManifestDirectory"
        }

        # Assuming the directory is good, we look for an appropriate manifest
        $SearchPattern = "$($Context.Stage.InputFrom)`_*.json"
        $ManifestFiles = Get-ChildItem -Path $ManifestDirectory -Filter $SearchPattern | Sort-Object LastWriteTime -Descending
        if ($ManifestFiles.Count -eq 0) {
            # Register-Incident -Context $Context -Code "E0F_001" -Detail $SearchPattern
            
            throw "Unable to locate files of pattern $SearchPattern in directory $ManifestDirectory"
        }

        $CutoffTime = (Get-Date).AddHours(-$MaxAge)
        $RecentManifests = $ManifestFiles | Where-Object { $_.LastWriteTime -gt $CutoffTime }
        if ($RecentManifests.Count -eq 0) {
            # Register-Incident -Context $Context -Code "E0F_002" `
            #     -Detail "Newest available file: $($ManifestFiles[0].Name) created $($ManifestFiles[0].LastWriteTime)"
            
            throw "No manifest files within cutoff age - Newest available file: $($ManifestFiles[0].Name) created $($ManifestFiles[0].LastWriteTime)"
        }

        # Starting from newest, attempt to load each discovered fallback file
        foreach ($File in $RecentManifests) {
            try {
                $Manifest = Get-Content $File | ConvertFrom-Json -AsHashtable
                $Manifest = New-Manifest -JsonItem $Manifest
                if($Manifest.Success -and $Manifest.Type -eq $Context.Stage.InputFrom) {
                    Register-Incident -Context $Context -Code "I0S_002" -Detail "Fallback manifest file: $File"

                    return $Manifest
                }
            } catch {
                Register-Incident -Context $Context -Code "W0F_001" -Detail "File: $File"
            }
        }

        # If no suitable file is found, throw to report it
        throw "No suitable $($Context.Stage.InputFrom) manifest found for fallback"
    }
    catch {
        # Log incident details
        Register-Incident -Context $Context -Code "W0S_005" -Detail $($_.Exception.Message)
        return $null
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
        [int]$StageNumber,
        [hashtable]$JsonItem = $null
    )
    
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
            # $Stage              = $Context.Stage
            # $Type               = $Stage.Name
            $DateGenerated      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $SavePath           = $Context.Directories.Manifests
            $SaveName           = $null

            if (-not $StageNumber) {
                throw 'Stage number not provided to create new manifest object'
            }
            switch ([string]$StageNumber) {
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
                Default {
                    throw 'New-Manifest does not have settings for the stage number provided: $StageNumber'
                }
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

        return $Manifest
    }
    catch {
        # Log incident details
        Register-Incident -Context $Context -ErrorCode "W0S_004" -Detail $($_.Exception.Message)

        return $null
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
        Register-Incident -Context $Context -Code 'D0F_001' -Detail "Save path: $ManifestFilePath"

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
    }
    catch {
        # Log incident details
        Register-Incident -Context $Context -Code "W0S_006" -Detail $($_.Exception.Message)
    }
}

function Invoke-Stage {
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
        [Parameter(Mandatory=$true)]
        [int]$Stage
    )
    function Start-Stage {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Context,
            [Parameter(Mandatory=$true)]
            [int]$Stage
        )
        try {
            # Confirm that the provided stage matches the next expected stage
            $NextStage = [int]$Context.NextStageNumber
            if ($NextStage -ne $Stage) {
                Register-Incident -Context $Context -Code 'W0S_002'
            }

            # Check and skip stage if necessary
            if ($Stage -notin $Context.RunStages) {
                Register-Incident -Context $Context -Code 'W0S_003'
                    -Detail "Skipped stage: $StageNumber"
                $Context.StageResults[$Stage.Name] = @{
                    Success = $false
                    Skipped = $true
                }
            }

            # If not skipping, prepare to launch the stage script
            else {
                $StageInfo = $Context.Config.Stages[[string]$Stage]
                $StartMessage = "=== Starting Stage: $($StageInfo.Name) ==="
                Register-Incident -Context $Context -Message $StartMessage -Code 'I0S_004'

                $Context.Metrics[$StageInfo.Name] = @{
                    'Info'      = 0
                    'Warning'   = 0
                    'Error'     = 0
                    'Fatal'     = 0
                }

                $Context.Incidents[$StageInfo.Name] = @{
                    'Info'      = @()
                    'Warning'   = @()
                    'Error'     = @()
                    'Fatal'     = @()
                }

                if ($StageInfo.InputFrom) {
                    $ManifestIn = Get-Manifest -Context $Context
                    if (-not $ManifestIn) {
                        throw "Stage input data (manifest) could not be loaded"
                    }
                    else {
                        $Context.ManifestIn = $ManifestIn
                    }
                }

                if ($StageInfo.HasManifest) {
                    $ManifestOut = New-Manifest -Context $Context -Stage $StageInfo.Number
                    if (-not $ManifestOut) {
                        throw "Stage output data (manifest) could not be prepared"
                    }
                    else {
                        $Context.ManifestOut = $ManifestOut
                    }
                }

                $Context.Stage = $StageInfo
                $Context.StageName = $StageInfo.Name
                $Context.StageStartTime = (Get-Date)
            }
        }
        catch {
            Register-Incident -Context $Context -Code 'E0S_001' -Detail $($_.Exception.Message)

            throw
        }
    }
    function Stop-Stage {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Context,
            [Parameter(Mandatory=$true)]
            [int]$Stage
        )
        try {
            # Record the name of the stage being ended
            $StageName = $Context.Stage.Name
            $NextStageNumber = $Context.Stage.NextStageNumber
            $ControlStage = $Context.Config.Stages['00']

            # Switch the context to Orchestration, so that incidents are handled properly
            $Context.Stage = $ControlStage
            $Context.StageName = $ControlStage.Name

            # Set next stage number for sequence verification
            if ($NextStageNumber) {
                $Context.NextStageNumber = $NextStageNumber
            }
            else {
                $Context.NextStageNumber = $null
            }

            # Clear working manifests
            if ($Context.ManifestIn) {
                $Context.ManifestIn = $null
            }
            if ($Context.ManifestOut) {
                Save-Manifest -Context $Context -StageName $StageName
                $Context.Manifests[$StageName] = $Context.ManifestOut
                $Context.ManifestOut = $null
            }

            # Log stage complete and generate summary report
            # TODO Write-StageSummaryReport
            $Context.StageSummary = @()

            # Reset the error flag so that future stages can run
            if ($Context.HasErrors) {
                $Context.HasErrors = $false
            }
        }
        catch {
            Register-Incident -Context $Context -Code $'F0S_002' -Detail $($_.Exception.Message)
        }
    }

    try {
        # Perform stage preparation
        Start-Stage -Context $Context -Stage $Stage

        if (-not $Context.HasErrors) {
            # Launch the stage script
            $ScriptFilePath = Join-Path $Config.Directories.Scripts $Context.Stage.Filename
            $Result = . $ScriptFilePath

            $Context.StageResults[$Stage.Name] = @{
                Success = $Result.Success
                Skipped = $false
            }
        }
    }
    catch {
        Register-Incident -Context $Context -Code 'F0S_001' -Detail $($_.Exception.Message)
    }

    # Perform stage wrap-up
    Stop-Stage -Context $Context -Stage $Stage
}

function Stop-Pipeline {
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

    try {
    }
    catch {
    }
}
#endregion Functions

#region Logic

# Initialization; Throw Fatal if not successful
try {
    # Build list of SkipStages
    $SkipStages = $PSBoundParameters.Keys | 
        Where-Object { $_ -match '^Skip\d+$' -and $PSBoundParameters[$_] } |
        ForEach-Object { $_ -replace 'Skip', '' } | ForEach-Object { [int]$_ * 10 }

    # Build the Context object
    $Context = Initialize-Pipeline -StartStage $($StartStage*10) -StopStage $($StopStage*10) `
        -SkipStages $SkipStages

    # Load required modules
    $IncidentModule = $Context.Config.Utilities.Incidents
    Import-Module $IncidentModule

    # Register successful initialization
    Register-Incident -Context $Context -Code 'I0S_001' -Detail "Start time: $($Context.StartTime)"
}
catch {
    Write-Error "FATAL Error initializing pipeline: $_" -ErrorAction Stop
    throw
}

# Invoke stages; Register Fatal if not successful
try {
    foreach ($Stage in $AllStages) {
        Invoke-Stage -Context $Context -Stage $Stage
        if ($Context.HasFatalErrors) {break}
    }
}
catch {
    Register-Incident -Context $Context -Code 'F0S_001'
}

# Perform wrap-up; Register Warning if not successful
try {
    Stop-Pipeline -Context $Context
}
catch {
    Register-Incident -Context $Context -Code 'W0S_001'
}

#endregion Logic

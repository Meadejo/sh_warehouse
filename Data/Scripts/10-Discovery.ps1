<#
.SYNOPSIS
    Stage 10 - Discovery: Identifies and catalogs available data sources
.DESCRIPTION
    Downloads ZIP files from SharePoint, extracts CSV files, validates structure,
    and creates a manifest of all discovered data files for downstream processing.

    Currently handles:
    - Hashed APR (Annual Performance Report) files from HMIS systems

    Future expansion will include:
    - Client tracker spreadsheets
    - Other data sources
.NOTES
    Author: Joshua Meade
    Created: October 29, 2025
    Updated: October 29, 2025
    Script: 10-Discovery.ps1
#>

#Requires -Version 5.1

#region Script Parameters
[CmdletBinding()]
param(
    [PSCustomObject]$Context
)

$StageNumber = "10"
$ReturnObject = [PSCustomObject]@{
    Success = $false
    Data = $null
    Errors = @()
}
#endregion Script Parameters


#region Functions

function Get-RegionFromPath {
    <#
    .SYNOPSIS
        Extracts region identifier from folder path structure
    .DESCRIPTION
        Parses folder path to identify region. Handles various naming patterns
        like "Region1", "Database_Region2", "Export_RegionName", etc.
    .PARAMETER FilePath
        Full file path to parse
    .EXAMPLE
        Get-RegionFromPath -FilePath "C:\Temp\Input\Region1\Client.csv"
        Returns: "Region1"
    .OUTPUTS
        [string] Region identifier
    #>
    param([string]$FilePath)

    # Extract region identifier from folder structure
    $PathParts = $FilePath.Split([IO.Path]::DirectorySeparatorChar)

    # Look for common parent folder patterns
    foreach ($part in $PathParts) {
        # Match common region naming patterns
        if ($part -match '^(Region|Database|Export|HMIS)[_\s-]?(.+)$') {
            return $matches[2]
        }
        # Or just "Region1", "Region2", etc.
        if ($part -match '^Region\d+$') {
            return $part
        }
    }

    # Check if ZIP file name contains region info
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    if ($fileName -match '(Region|Database|Export)[_\s-]?(\w+)') {
        return $matches[2]
    }

    return "Unknown"
}

function Get-FileTypeFromName {
    <#
    .SYNOPSIS
        Identifies HUD HMIS file type from filename
    .DESCRIPTION
        Matches CSV filename against known HUD HMIS export file patterns
    .PARAMETER FileName
        Name of the CSV file
    .EXAMPLE
        Get-FileTypeFromName -FileName "Client.csv"
        Returns: "Client"
    .OUTPUTS
        [string] File type identifier or "Unknown"
    #>
    param([string]$FileName)

    # Standard HUD CSV file patterns
    $FileTypes = @{
        'Client\.csv$' = 'Client'
        'Project\.csv$' = 'Project'
        'Enrollment\.csv$' = 'Enrollment'
        'Exit\.csv$' = 'Exit'
        'Export\.csv$' = 'Export'
        'Organization\.csv$' = 'Organization'
        'Funder\.csv$' = 'Funder'
        'ProjectCoC\.csv$' = 'ProjectCoC'
        'Inventory\.csv$' = 'Inventory'
        'Affiliation\.csv$' = 'Affiliation'
        'User\.csv$' = 'User'
        'IncomeBenefits\.csv$' = 'IncomeBenefits'
        'HealthAndDV\.csv$' = 'HealthAndDV'
        'EmploymentEducation\.csv$' = 'EmploymentEducation'
        'Disabilities\.csv$' = 'Disabilities'
        'Services\.csv$' = 'Services'
        'CurrentLivingSituation\.csv$' = 'CurrentLivingSituation'
        'Assessment\.csv$' = 'Assessment'
        'AssessmentQuestions\.csv$' = 'AssessmentQuestions'
        'AssessmentResults\.csv$' = 'AssessmentResults'
        'Event\.csv$' = 'Event'
        'YouthEducationStatus\.csv$' = 'YouthEducationStatus'
        'CEParticipation\.csv$' = 'CEParticipation'
        'CEAssessment\.csv$' = 'CEAssessment'
        'CEEvent\.csv$' = 'CEEvent'
        'HMISParticipation\.csv$' = 'HMISParticipation'
    }

    foreach ($Pattern in $FileTypes.Keys) {
        if ($FileName -match $Pattern) {
            return $FileTypes[$Pattern]
        }
    }

    return "Unknown"
}

function Test-CSVStructure {
    <#
    .SYNOPSIS
        Validates CSV file structure
    .DESCRIPTION
        Performs basic validation on CSV file:
        - File exists and is readable
        - Has valid headers
        - Has at least one data row
    .PARAMETER FilePath
        Path to CSV file
    .PARAMETER FileType
        Expected file type (for future schema validation)
    .EXAMPLE
        Test-CSVStructure -FilePath "C:\Data\Client.csv" -FileType "Client"
    .OUTPUTS
        [PSCustomObject] with IsValid (bool), HeaderCount (int), RowCount (int), Reason (string)
    #>
    param(
        [string]$FilePath,
        [string]$FileType
    )

    $result = [PSCustomObject]@{
        IsValid = $false
        HeaderCount = 0
        RowCount = 0
        Reason = ""
    }

    try {
        # Check file exists and is readable
        if (-not (Test-Path $FilePath)) {
            $result.Reason = "File not found"
            return $result
        }

        # Try to import and count headers/rows
        $csv = Import-Csv -Path $FilePath -ErrorAction Stop

        if (-not $csv) {
            $result.Reason = "Empty file or invalid CSV format"
            return $result
        }

        # Get header count
        $headers = ($csv | Get-Member -MemberType NoteProperty).Name
        $result.HeaderCount = $headers.Count
        $result.RowCount = @($csv).Count

        if ($result.HeaderCount -eq 0) {
            $result.Reason = "No headers found"
            return $result
        }

        # File is valid
        $result.IsValid = $true
        $result.Reason = "Valid"

        return $result
    }
    catch {
        $result.Reason = "Error reading file: $($_.Exception.Message)"
        return $result
    }
}

function Get-HashedAPRZipFiles {
    <#
    .SYNOPSIS
        Downloads and processes Hashed APR ZIP files from SharePoint
    .DESCRIPTION
        Connects to SharePoint, downloads ZIP files, extracts CSVs,
        validates file structure, and builds discovery manifest.
    .PARAMETER Context
        Pipeline context object
    .EXAMPLE
        Get-HashedAPRZipFiles -Context $Context
    .OUTPUTS
        [PSCustomObject] with Success, FilesProcessed, etc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Context
    )

    try {
        Register-Incident -Context $Context -Code 'I1S_001'

        # Setup temp directory for extraction
        $tempBase = [System.IO.Path]::GetTempPath()
        $tempFolder = Join-Path $tempBase "SH_Pipeline_Discovery_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

        # Track temp folder for cleanup
        if (-not $Context.PSObject.Properties['TempFiles']) {
            $Context | Add-Member -NotePropertyName 'TempFiles' -NotePropertyValue @()
        }
        $Context.TempFiles += $tempFolder

        Register-Incident -Context $Context -Code 'D1F_001' -Detail "Temp folder: $tempFolder"

        # Import SharePoint module
        $SharePointModule = $Context.Config.Utilities.SharePoint
        Import-Module $SharePointModule -Force

        # Connect to SharePoint
        $spConfig = $Context.Config.SharePoint
        $connectionResult = Connect-SharePoint -SiteUrl $spConfig.SiteUrl -AuthMode $spConfig.AuthMode

        if (-not $connectionResult.Success) {
            Register-Incident -Context $Context -Code 'E1SP_001' -Detail $connectionResult.Error
            throw "SharePoint connection failed"
        }

        $Context.StageSummary += [PSCustomObject]@{
            Action = "Connected to SharePoint"
            Detail = "Site: $($spConfig.SiteUrl)"
            Status = "Success"
        }

        # Download ZIP files from SharePoint
        $inputFolder = $spConfig.Paths.InputFolder
        $downloadPath = Join-Path $tempFolder "Downloads"

        $downloadResult = Get-SharePointFile -ServerRelativeUrl $inputFolder `
            -LocalPath $downloadPath -Filter "*.zip"

        if (-not $downloadResult.Success) {
            Register-Incident -Context $Context -Code 'E1F_001' -Detail $downloadResult.Error
            throw "Failed to download ZIP files"
        }

        Register-Incident -Context $Context -Code 'I1F_001' `
            -Detail "Downloaded $($downloadResult.Count) ZIP file(s)"

        $Context.StageSummary += [PSCustomObject]@{
            Action = "Downloaded ZIP files"
            Detail = "$($downloadResult.Count) file(s) from $inputFolder"
            Status = "Success"
        }

        # Extract ZIP files
        $extractPath = Join-Path $tempFolder "Extracted"
        $extractedCount = 0
        $extractErrors = 0

        foreach ($zipFile in $downloadResult.FilesDownloaded) {
            try {
                $zipName = [System.IO.Path]::GetFileNameWithoutExtension($zipFile.FileName)
                $extractFolder = Join-Path $extractPath $zipName

                Expand-Archive -Path $zipFile.LocalPath -DestinationPath $extractFolder -Force
                $extractedCount++

                Register-Incident -Context $Context -Code 'I1F_002' -Detail "Extracted: $($zipFile.FileName)"
            }
            catch {
                $extractErrors++
                Register-Incident -Context $Context -Code 'E1F_002' `
                    -Detail "Failed to extract $($zipFile.FileName): $($_.Exception.Message)"
            }
        }

        $summaryStatus = if ($extractErrors -eq 0) { "Success" } else { "Warning" }
        $Context.StageSummary += [PSCustomObject]@{
            Action = "Extracted ZIP archives"
            Detail = "$extractedCount extracted, $extractErrors failed"
            Status = $summaryStatus
        }

        # Discover and process CSV files
        $CSVFiles = Get-ChildItem -Path $extractPath -Filter "*.csv" -Recurse

        Register-Incident -Context $Context -Code 'D1F_001' -Detail "Found $($CSVFiles.Count) CSV files"

        # Initialize manifest data
        $Context.ManifestOut.Type = "Discovery"
        $Context.ManifestOut.Data.Files = @()
        $Context.ManifestOut.Metrics.Regions = @{}
        $Context.ManifestOut.Metrics.FileTypes = @{}
        $Context.ManifestOut.Metrics.TotalFiles = 0
        $Context.ManifestOut.Metrics.ValidFiles = 0
        $Context.ManifestOut.Metrics.InvalidFiles = 0

        # Process each CSV file
        foreach ($File in $CSVFiles) {
            $Context.ManifestOut.Metrics.TotalFiles++

            Register-Incident -Context $Context -Code 'D1F_001' -Detail "Processing: $($File.Name)"

            $Region = Get-RegionFromPath -FilePath $File.FullName
            $FileType = Get-FileTypeFromName -FileName $File.Name
            $Structure = Test-CSVStructure -FilePath $File.FullName -FileType $FileType

            $FileInfo = @{
                FileName = $File.Name
                FullPath = $File.FullName
                RelativePath = $File.FullName.Replace($extractPath, "").TrimStart('\', '/')
                Region = $Region
                FileType = $FileType
                LastModified = $File.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                SizeKB = [math]::Round($File.Length / 1KB, 2)
                IsValid = $Structure.IsValid
                HeaderCount = $Structure.HeaderCount
                RowCount = $Structure.RowCount
                ValidationReason = $Structure.Reason
            }

            # Track by region
            if (-not $Context.ManifestOut.Metrics.Regions.ContainsKey($Region)) {
                $Context.ManifestOut.Metrics.Regions[$Region] = @{
                    FileCount = 0
                    ValidFiles = 0
                    FileTypes = @{}
                }
            }
            $Context.ManifestOut.Metrics.Regions[$Region].FileCount++

            if ($Structure.IsValid) {
                $Context.ManifestOut.Metrics.ValidFiles++
                $Context.ManifestOut.Metrics.Regions[$Region].ValidFiles++

                Register-Incident -Context $Context -Code 'D1F_001' `
                    -Detail "Valid: $($File.Name) (Type: $FileType, Region: $Region, Rows: $($Structure.RowCount))"
            }
            else {
                $Context.ManifestOut.Metrics.InvalidFiles++
                Register-Incident -Context $Context -Code 'W1F_001' `
                    -Detail "Invalid: $($File.Name) - $($Structure.Reason)"
            }

            # Track file types by region
            if (-not $Context.ManifestOut.Metrics.Regions[$Region].FileTypes.ContainsKey($FileType)) {
                $Context.ManifestOut.Metrics.Regions[$Region].FileTypes[$FileType] = 0
            }
            $Context.ManifestOut.Metrics.Regions[$Region].FileTypes[$FileType]++

            # Track overall file type summary
            if (-not $Context.ManifestOut.Metrics.FileTypes.ContainsKey($FileType)) {
                $Context.ManifestOut.Metrics.FileTypes[$FileType] = 0
            }
            $Context.ManifestOut.Metrics.FileTypes[$FileType]++

            $Context.ManifestOut.Data.Files += $FileInfo
        }

        # Add summary items
        $Context.StageSummary += [PSCustomObject]@{
            Action = "Processed CSV files"
            Detail = "Total: $($Context.ManifestOut.Metrics.TotalFiles), Valid: $($Context.ManifestOut.Metrics.ValidFiles), Invalid: $($Context.ManifestOut.Metrics.InvalidFiles)"
            Status = if ($Context.ManifestOut.Metrics.InvalidFiles -eq 0) { "Success" } else { "Warning" }
        }

        # Add region summary
        foreach ($Region in $Context.ManifestOut.Metrics.Regions.Keys) {
            $regionData = $Context.ManifestOut.Metrics.Regions[$Region]
            $Context.StageSummary += [PSCustomObject]@{
                Action = "Region: $Region"
                Detail = "$($regionData.ValidFiles)/$($regionData.FileCount) valid files"
                Status = if ($regionData.ValidFiles -eq $regionData.FileCount) { "Success" } else { "Warning" }
            }
        }

        # Disconnect SharePoint
        Disconnect-SharePoint | Out-Null

        return [PSCustomObject]@{
            Success = $true
            FilesProcessed = $Context.ManifestOut.Metrics.TotalFiles
            ValidFiles = $Context.ManifestOut.Metrics.ValidFiles
        }
    }
    catch {
        Register-Incident -Context $Context -Code 'E1F_001' -Detail $_.Exception.Message

        return [PSCustomObject]@{
            Success = $false
            FilesProcessed = 0
            ValidFiles = 0
            Error = $_.Exception.Message
        }
    }
}

#endregion Functions


#region Main Execution

try {
    # Verify context exists
    if (-not $Context) {
        throw "Context object not provided"
    }

    # Import required modules
    $IncidentModule = $Context.Config.Utilities.Incidents
    Import-Module $IncidentModule -Force

    # Execute discovery
    $result = Get-HashedAPRZipFiles -Context $Context

    if ($result.Success) {
        $ReturnObject.Success = $true
        $ReturnObject.Data = $result

        Register-Incident -Context $Context -Code 'I1S_001' `
            -Detail "Discovery completed: $($result.ValidFiles) valid files found"
    }
    else {
        $ReturnObject.Success = $false
        $ReturnObject.Errors += $result.Error
    }

    return $ReturnObject
}
catch {
    Register-Incident -Context $Context -Code 'E1F_001' -Detail $_.Exception.Message

    $ReturnObject.Success = $false
    $ReturnObject.Errors += $_.Exception.Message

    return $ReturnObject
}

#endregion Main Execution
<#
.SYNOPSIS
    SharePoint file operations module using PnP.PowerShell
.DESCRIPTION
    Provides connection management and file transfer operations for SharePoint Online.
    Context-agnostic design allows reuse across different projects.
    Supports both interactive (Development) and certificate-based (Production) authentication.
.NOTES
    NOTE: Update the 'Updated' date!
    Author: Joshua Meade
    Created: October 17, 2025
    Updated: October 29, 2025
    Module: SharePoint.psm1
    Dependencies: PnP.PowerShell module
#>

#Requires -Version 5.1

#region Script Parameters
$Script:SharePointConnection = $null
#endregion Script Parameters


#region Connection Management

function Connect-SharePoint {
    <#
    .SYNOPSIS
        Establishes connection to SharePoint Online site
    .DESCRIPTION
        Connects to SharePoint using either interactive authentication (Development)
        or certificate-based authentication (Production). Stores connection in script scope.
    .PARAMETER SiteUrl
        SharePoint site URL (e.g., "https://tenant.sharepoint.com/sites/SiteName")
    .PARAMETER AuthMode
        Authentication mode: "Development" (interactive) or "Production" (certificate)
    .PARAMETER ClientId
        Azure AD Application (Client) ID - required for Production mode
    .PARAMETER TenantId
        Azure AD Tenant ID - required for Production mode
    .PARAMETER CertificatePath
        Path to certificate file (.pfx) - required for Production mode
    .PARAMETER CertificatePassword
        Password for certificate file - required for Production mode
    .PARAMETER Credential
        PSCredential object for interactive auth - optional for Development mode
    .EXAMPLE
        Connect-SharePoint -SiteUrl "https://contoso.sharepoint.com/sites/Data" -AuthMode "Development"
    .EXAMPLE
        Connect-SharePoint -SiteUrl $url -AuthMode "Production" -ClientId $id -TenantId $tenant -CertificatePath $cert
    .OUTPUTS
        [PSCustomObject] with Success (bool), Connection (object), and Error (string) properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteUrl,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Development", "Production")]
        [string]$AuthMode,

        [string]$ClientId,
        [string]$TenantId,
        [string]$CertificatePath,
        [SecureString]$CertificatePassword,
        [PSCredential]$Credential
    )

    try {
        # Check if PnP.PowerShell module is available
        if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
            throw "PnP.PowerShell module not found. Install with: Install-Module PnP.PowerShell -Scope CurrentUser"
        }

        # Import module if not already loaded
        if (-not (Get-Module -Name PnP.PowerShell)) {
            Import-Module PnP.PowerShell -ErrorAction Stop
        }

        # Disconnect existing connection if present
        if ($Script:SharePointConnection) {
            Disconnect-PnPOnline -ErrorAction SilentlyContinue
            $Script:SharePointConnection = $null
        }

        # Connect based on auth mode
        switch ($AuthMode) {
            "Development" {
                Write-Verbose "Connecting to SharePoint using interactive authentication..."
                if ($Credential) {
                    Connect-PnPOnline -Url $SiteUrl -Credentials $Credential -ErrorAction Stop
                }
                else {
                    Connect-PnPOnline -Url $SiteUrl -Interactive -ErrorAction Stop
                }
            }

            "Production" {
                Write-Verbose "Connecting to SharePoint using certificate authentication..."

                # Validate required parameters
                if ([string]::IsNullOrWhiteSpace($ClientId)) {
                    throw "ClientId is required for Production mode"
                }
                if ([string]::IsNullOrWhiteSpace($TenantId)) {
                    throw "TenantId is required for Production mode"
                }
                if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
                    throw "CertificatePath is required for Production mode"
                }
                if (-not (Test-Path $CertificatePath)) {
                    throw "Certificate file not found: $CertificatePath"
                }

                # Connect with certificate
                if ($CertificatePassword) {
                    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Tenant $TenantId `
                        -CertificatePath $CertificatePath -CertificatePassword $CertificatePassword `
                        -ErrorAction Stop
                }
                else {
                    Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId -Tenant $TenantId `
                        -CertificatePath $CertificatePath -ErrorAction Stop
                }
            }
        }

        # Store connection reference
        $Script:SharePointConnection = Get-PnPConnection

        Write-Verbose "Successfully connected to SharePoint: $SiteUrl"

        return [PSCustomObject]@{
            Success = $true
            Connection = $Script:SharePointConnection
            Error = $null
        }
    }
    catch {
        Write-Warning "Failed to connect to SharePoint: $($_.Exception.Message)"

        return [PSCustomObject]@{
            Success = $false
            Connection = $null
            Error = $_.Exception.Message
        }
    }
}

function Disconnect-SharePoint {
    <#
    .SYNOPSIS
        Disconnects from SharePoint Online
    .DESCRIPTION
        Cleanly disconnects the current SharePoint session and clears the script-level connection variable
    .EXAMPLE
        Disconnect-SharePoint
    .OUTPUTS
        [PSCustomObject] with Success (bool) and Error (string) properties
    #>
    [CmdletBinding()]
    param()

    try {
        if ($Script:SharePointConnection) {
            Disconnect-PnPOnline -ErrorAction Stop
            $Script:SharePointConnection = $null
            Write-Verbose "Disconnected from SharePoint"
        }
        else {
            Write-Verbose "No active SharePoint connection to disconnect"
        }

        return [PSCustomObject]@{
            Success = $true
            Error = $null
        }
    }
    catch {
        Write-Warning "Error disconnecting from SharePoint: $($_.Exception.Message)"

        return [PSCustomObject]@{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Test-SharePointConnection {
    <#
    .SYNOPSIS
        Tests if SharePoint connection is active and valid
    .DESCRIPTION
        Checks if a SharePoint connection exists and attempts a simple query to validate it
    .EXAMPLE
        $isConnected = Test-SharePointConnection
        if ($isConnected.Success) { ... }
    .OUTPUTS
        [PSCustomObject] with Success (bool), IsConnected (bool), SiteUrl (string), and Error (string) properties
    #>
    [CmdletBinding()]
    param()

    try {
        if (-not $Script:SharePointConnection) {
            return [PSCustomObject]@{
                Success = $true
                IsConnected = $false
                SiteUrl = $null
                Error = "No connection established"
            }
        }

        # Test connection by getting web properties
        $web = Get-PnPWeb -ErrorAction Stop

        return [PSCustomObject]@{
            Success = $true
            IsConnected = $true
            SiteUrl = $web.Url
            Error = $null
        }
    }
    catch {
        # Connection exists but is invalid
        $Script:SharePointConnection = $null

        return [PSCustomObject]@{
            Success = $true
            IsConnected = $false
            SiteUrl = $null
            Error = $_.Exception.Message
        }
    }
}

#endregion Connection Management


#region File Operations

function Get-SharePointFile {
    <#
    .SYNOPSIS
        Downloads file(s) from SharePoint
    .DESCRIPTION
        Downloads individual files or all files from a folder in SharePoint to local filesystem.
        Supports recursive folder downloads and file filtering.
    .PARAMETER ServerRelativeUrl
        Server-relative URL of file or folder (e.g., "/sites/SiteName/Shared Documents/Folder/file.csv")
    .PARAMETER LocalPath
        Local filesystem path where file(s) will be saved
    .PARAMETER AsFile
        When downloading a folder, treat it as a single file download (won't recurse)
    .PARAMETER Force
        Overwrite existing local files without prompting
    .PARAMETER Recursive
        When downloading a folder, include all subfolders
    .PARAMETER Filter
        File name pattern filter (e.g., "*.csv", "Report_*.xlsx")
    .EXAMPLE
        Get-SharePointFile -ServerRelativeUrl "/sites/Data/Shared Documents/input/data.csv" -LocalPath "C:\Downloads"
    .EXAMPLE
        Get-SharePointFile -ServerRelativeUrl "/sites/Data/Shared Documents/input" -LocalPath "C:\Downloads" -Recursive -Filter "*.csv"
    .OUTPUTS
        [PSCustomObject] with Success (bool), FilesDownloaded (array), Count (int), and Error (string) properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerRelativeUrl,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalPath,

        [switch]$AsFile,
        [switch]$Force,
        [switch]$Recursive,
        [string]$Filter
    )

    try {
        # Verify connection
        $connectionTest = Test-SharePointConnection
        if (-not $connectionTest.IsConnected) {
            throw "Not connected to SharePoint. Connection error: $($connectionTest.Error)"
        }

        # Ensure local path exists
        if (-not (Test-Path $LocalPath)) {
            New-Item -Path $LocalPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created directory: $LocalPath"
        }

        $downloadedFiles = @()

        # Check if target is a file or folder
        $isFile = $false
        try {
            $file = Get-PnPFile -Url $ServerRelativeUrl -AsListItem -ErrorAction Stop
            $isFile = $true
        }
        catch {
            # Not a file, might be a folder
            $isFile = $false
        }

        if ($isFile -or $AsFile) {
            # Download single file
            Write-Verbose "Downloading file: $ServerRelativeUrl"

            $fileName = Split-Path $ServerRelativeUrl -Leaf
            $localFilePath = Join-Path $LocalPath $fileName

            Get-PnPFile -Url $ServerRelativeUrl -Path $LocalPath -FileName $fileName -AsFile -Force:$Force -ErrorAction Stop

            $downloadedFiles += [PSCustomObject]@{
                FileName = $fileName
                LocalPath = $localFilePath
                ServerRelativeUrl = $ServerRelativeUrl
            }

            Write-Verbose "Downloaded: $fileName to $localFilePath"
        }
        else {
            # Download folder contents
            Write-Verbose "Downloading folder contents: $ServerRelativeUrl"

            # Get folder
            $folder = Get-PnPFolder -Url $ServerRelativeUrl -Includes Files, Folders -ErrorAction Stop

            # Download files in current folder
            foreach ($file in $folder.Files) {
                # Apply filter if specified
                if ($Filter -and ($file.Name -notlike $Filter)) {
                    Write-Verbose "Skipping file (filter): $($file.Name)"
                    continue
                }

                $fileUrl = $file.ServerRelativeUrl
                $localFilePath = Join-Path $LocalPath $file.Name

                Write-Verbose "Downloading: $($file.Name)"
                Get-PnPFile -Url $fileUrl -Path $LocalPath -FileName $file.Name -AsFile -Force:$Force -ErrorAction Stop

                $downloadedFiles += [PSCustomObject]@{
                    FileName = $file.Name
                    LocalPath = $localFilePath
                    ServerRelativeUrl = $fileUrl
                }
            }

            # Process subfolders if recursive
            if ($Recursive) {
                foreach ($subfolder in $folder.Folders) {
                    # Skip system folders
                    if ($subfolder.Name -in @('Forms', '_cts', '_w')) {
                        continue
                    }

                    $subfolderLocalPath = Join-Path $LocalPath $subfolder.Name
                    $subfolderUrl = $subfolder.ServerRelativeUrl

                    Write-Verbose "Processing subfolder: $($subfolder.Name)"

                    # Recursive call
                    $subResult = Get-SharePointFile -ServerRelativeUrl $subfolderUrl -LocalPath $subfolderLocalPath `
                        -Recursive -Force:$Force -Filter $Filter

                    if ($subResult.Success) {
                        $downloadedFiles += $subResult.FilesDownloaded
                    }
                }
            }
        }

        return [PSCustomObject]@{
            Success = $true
            FilesDownloaded = $downloadedFiles
            Count = $downloadedFiles.Count
            Error = $null
        }
    }
    catch {
        Write-Warning "Failed to download from SharePoint: $($_.Exception.Message)"

        return [PSCustomObject]@{
            Success = $false
            FilesDownloaded = @()
            Count = 0
            Error = $_.Exception.Message
        }
    }
}

function Send-SharePointFiles {
    <#
    .SYNOPSIS
        Uploads file(s) to SharePoint
    .DESCRIPTION
        Uploads one or more files from local filesystem to a SharePoint folder.
        Supports bulk uploads and overwrite options.
    .PARAMETER LocalPath
        Path to local file or folder to upload
    .PARAMETER ServerRelativeUrl
        Server-relative URL of destination folder in SharePoint (e.g., "/sites/SiteName/Shared Documents/Reports")
    .PARAMETER Overwrite
        Overwrite existing files in SharePoint
    .PARAMETER Recursive
        Upload entire folder structure recursively
    .PARAMETER Filter
        File name pattern filter for folder uploads (e.g., "*.pdf", "Report_*.xlsx")
    .EXAMPLE
        Send-SharePointFiles -LocalPath "C:\Reports\monthly.pdf" -ServerRelativeUrl "/sites/Data/Shared Documents/Reports"
    .EXAMPLE
        Send-SharePointFiles -LocalPath "C:\Reports" -ServerRelativeUrl "/sites/Data/Shared Documents/Reports" -Recursive -Filter "*.pdf"
    .OUTPUTS
        [PSCustomObject] with Success (bool), FilesUploaded (array), Count (int), and Error (string) properties
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$LocalPath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerRelativeUrl,

        [switch]$Overwrite,
        [switch]$Recursive,
        [string]$Filter
    )

    try {
        # Verify connection
        $connectionTest = Test-SharePointConnection
        if (-not $connectionTest.IsConnected) {
            throw "Not connected to SharePoint. Connection error: $($connectionTest.Error)"
        }

        # Verify local path exists
        if (-not (Test-Path $LocalPath)) {
            throw "Local path not found: $LocalPath"
        }

        $uploadedFiles = @()

        # Check if local path is file or folder
        $item = Get-Item $LocalPath

        if ($item.PSIsContainer) {
            # Upload folder contents
            Write-Verbose "Uploading folder contents from: $LocalPath"

            # Get files to upload
            $files = Get-ChildItem -Path $LocalPath -File

            foreach ($file in $files) {
                # Apply filter if specified
                if ($Filter -and ($file.Name -notlike $Filter)) {
                    Write-Verbose "Skipping file (filter): $($file.Name)"
                    continue
                }

                Write-Verbose "Uploading: $($file.Name)"

                $uploadResult = Add-PnPFile -Path $file.FullName -Folder $ServerRelativeUrl -ErrorAction Stop

                if ($Overwrite -and (Get-PnPFile -Url "$ServerRelativeUrl/$($file.Name)" -ErrorAction SilentlyContinue)) {
                    # File exists, overwrite
                    $uploadResult = Set-PnPFileCheckedOut -Url "$ServerRelativeUrl/$($file.Name)" -ErrorAction SilentlyContinue
                    $uploadResult = Add-PnPFile -Path $file.FullName -Folder $ServerRelativeUrl -ErrorAction Stop
                    $uploadResult = Set-PnPFileCheckedIn -Url "$ServerRelativeUrl/$($file.Name)" -ErrorAction SilentlyContinue
                }

                $uploadedFiles += [PSCustomObject]@{
                    FileName = $file.Name
                    LocalPath = $file.FullName
                    ServerRelativeUrl = "$ServerRelativeUrl/$($file.Name)"
                }
            }

            # Process subfolders if recursive
            if ($Recursive) {
                $subfolders = Get-ChildItem -Path $LocalPath -Directory

                foreach ($subfolder in $subfolders) {
                    $subfolderUrl = "$ServerRelativeUrl/$($subfolder.Name)"

                    Write-Verbose "Processing subfolder: $($subfolder.Name)"

                    # Ensure subfolder exists in SharePoint
                    try {
                        $null = Get-PnPFolder -Url $subfolderUrl -ErrorAction Stop
                    }
                    catch {
                        # Folder doesn't exist, create it
                        Write-Verbose "Creating folder: $subfolderUrl"
                        $null = Add-PnPFolder -Name $subfolder.Name -Folder $ServerRelativeUrl -ErrorAction Stop
                    }

                    # Recursive call
                    $subResult = Send-SharePointFiles -LocalPath $subfolder.FullName -ServerRelativeUrl $subfolderUrl `
                        -Recursive -Overwrite:$Overwrite -Filter $Filter

                    if ($subResult.Success) {
                        $uploadedFiles += $subResult.FilesUploaded
                    }
                }
            }
        }
        else {
            # Upload single file
            Write-Verbose "Uploading file: $($item.Name)"

            if ($Overwrite -and (Get-PnPFile -Url "$ServerRelativeUrl/$($item.Name)" -ErrorAction SilentlyContinue)) {
                # File exists, check out and overwrite
                $null = Set-PnPFileCheckedOut -Url "$ServerRelativeUrl/$($item.Name)" -ErrorAction SilentlyContinue
                $uploadResult = Add-PnPFile -Path $item.FullName -Folder $ServerRelativeUrl -ErrorAction Stop
                $null = Set-PnPFileCheckedIn -Url "$ServerRelativeUrl/$($item.Name)" -ErrorAction SilentlyContinue
            }
            else {
                $uploadResult = Add-PnPFile -Path $item.FullName -Folder $ServerRelativeUrl -ErrorAction Stop
            }

            $uploadedFiles += [PSCustomObject]@{
                FileName = $item.Name
                LocalPath = $item.FullName
                ServerRelativeUrl = "$ServerRelativeUrl/$($item.Name)"
            }
        }

        return [PSCustomObject]@{
            Success = $true
            FilesUploaded = $uploadedFiles
            Count = $uploadedFiles.Count
            Error = $null
        }
    }
    catch {
        Write-Warning "Failed to upload to SharePoint: $($_.Exception.Message)"

        return [PSCustomObject]@{
            Success = $false
            FilesUploaded = @()
            Count = 0
            Error = $_.Exception.Message
        }
    }
}

#endregion File Operations


Export-ModuleMember -Function Connect-SharePoint, Disconnect-SharePoint, Test-SharePointConnection, Get-SharePointFile, Send-SharePointFiles
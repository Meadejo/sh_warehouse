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
    Module: [ModuleName].psm1
#>

#Requires -Version 5.1

#region Module Parameters

#endregion Module Parameters

#region Template
function Verb-Noun {
    # Suppress PSScriptAnalyzer warning for unapproved verb (template placeholder only)
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]

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
    $ThrowCode = "Generic_Code"
    
    try {
        # Function logic here
        Invoke-Function

        # If issue is encountered
        $ThrowCode = "Specific_Code"
        throw "Issue Details"
        
        # Return expected output
        return $Result
    }
    catch {
        # Log incident details
        Register-Incident -Context $Context -Code $ThrowCode `
            -Detail $($_.Exception.Message)
    }
}
#endregion Template

Export-ModuleMember -Function *

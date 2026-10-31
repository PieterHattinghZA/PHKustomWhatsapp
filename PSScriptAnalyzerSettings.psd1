<#
.SYNOPSIS
    Configure static analysis rules for the WhatsApp project.
#>


@{
    Severity = @('Error','Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidGlobalVars',
        'PSUseSingularNouns'
    )
}

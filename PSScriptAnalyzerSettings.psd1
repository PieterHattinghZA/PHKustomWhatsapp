@{
    Severity = @('Error','Warning')
    IncludeDefaultRules = $true
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseShouldProcessForStateChangingFunctions'
    )
}

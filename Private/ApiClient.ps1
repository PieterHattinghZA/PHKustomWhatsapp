<#
.SYNOPSIS
Private Green API HTTP client with URL encoding, bounded retries and logging.
#>

function ConvertTo-WhatsappQueryString {
    [CmdletBinding()]
    [OutputType([string])]
    param([hashtable]$QueryParams)

    if (-not $QueryParams -or $QueryParams.Count -eq 0) { return '' }

    $pairs = foreach ($key in ($QueryParams.Keys | Sort-Object)) {
        $encodedKey = [Uri]::EscapeDataString([string]$key)
        $encodedValue = [Uri]::EscapeDataString([string]$QueryParams[$key])
        '{0}={1}' -f $encodedKey, $encodedValue
    }
    return ($pairs -join '&')
}

function Get-WhatsappRetryDelay {
    [OutputType([double])]
    param(
        [int]$Attempt,
        [object]$Response
    )

    if ($Response -and $Response.Headers -and $Response.Headers['Retry-After']) {
        $retryAfter = 0
        if ([int]::TryParse([string]$Response.Headers['Retry-After'], [ref]$retryAfter)) {
            return [Math]::Min(60, [Math]::Max(1, $retryAfter))
        }
    }
    return [Math]::Pow(2, ($Attempt - 1))
}

function Test-WhatsappTransientFailure {
    [OutputType([bool])]
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($ErrorRecord.Exception -is [Net.WebException]) {
        $status = $ErrorRecord.Exception.Status
        if ($status -in @(
            [Net.WebExceptionStatus]::NameResolutionFailure,
            [Net.WebExceptionStatus]::ConnectFailure,
            [Net.WebExceptionStatus]::Timeout,
            [Net.WebExceptionStatus]::ConnectionClosed,
            [Net.WebExceptionStatus]::ReceiveFailure,
            [Net.WebExceptionStatus]::SendFailure
        )) { return $true }
    }

    $response = $ErrorRecord.Exception.Response
    if ($response) {
        $statusCode = [int]$response.StatusCode
        if ($statusCode -eq 429 -or $statusCode -ge 500) { return $true }
    }
    return $false
}

function Invoke-WhatsappApi {
    [CmdletBinding()]
    [OutputType([PSObject], [bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [ValidateSet('GET','POST','PUT','DELETE')][string]$Method = 'POST',
        [object]$Body,
        [hashtable]$QueryParams,
        [string]$OutFile,
        [ValidateRange(1, 5)][int]$MaximumAttempts = 3
    )

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        throw 'API credentials are not loaded. Run Get-WhatsappConfig.'
    }

    if ($Endpoint -match '^deleteNotification/(.+)$') {
        $receipt = [Uri]::EscapeDataString([string]$Matches[1])
        $url = '{0}/deleteNotification/{1}/{2}' -f $global:BaseUrl.TrimEnd('/'), $global:Token, $receipt
    }
    else {
        $safeEndpoint = $Endpoint.TrimStart('/')
        $url = '{0}/{1}/{2}' -f $global:BaseUrl.TrimEnd('/'), $safeEndpoint, $global:Token
    }

    $queryString = ConvertTo-WhatsappQueryString -QueryParams $QueryParams
    if ($queryString) { $url += '?' + $queryString }

    $parameters = @{
        Uri         = $url
        Method      = $Method
        Headers     = @{ Accept = 'application/json' }
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $parameters.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        $parameters.ContentType = 'application/json'
    }
    if ($OutFile) { $parameters.OutFile = $OutFile }

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $response = Invoke-RestMethod @parameters
            if ($OutFile) { return $true }
            return $response
        }
        catch {
            $transient = Test-WhatsappTransientFailure -ErrorRecord $_
            $safeMessage = 'Green API call {0} failed on attempt {1}/{2}: {3}' -f $Endpoint, $attempt, $MaximumAttempts, $_.Exception.Message
            Write-WhatsappLog -Level $(if ($transient) { 'WARN' } else { 'ERROR' }) -Message $safeMessage

            if (-not $transient -or $attempt -ge $MaximumAttempts) {
                throw
            }

            $delay = Get-WhatsappRetryDelay -Attempt $attempt -Response $_.Exception.Response
            Start-Sleep -Seconds $delay
        }
    }
}

<#
.SYNOPSIS
Private configuration, credential-protection and local-data security helpers.
#>

function Write-WhatsappLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) {
            New-Item -Path $script:LogDir -ItemType Directory -Force | Out-Null
        }
        $logFile = Join-Path $script:LogDir ('module_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    catch {
        Write-Verbose ('Logging failed: {0}' -f $_.Exception.Message)
    }
}

function Protect-WhatsappPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $sid = $identity.User
        $item = Get-Item -LiteralPath $Path -Force

        if ($item.PSIsContainer) {
            $security = New-Object Security.AccessControl.DirectorySecurity
            $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                $inheritance,
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow
            )
        }
        else {
            $security = New-Object Security.AccessControl.FileSecurity
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )
        }

        $security.SetOwner($sid)
        $security.SetAccessRuleProtection($true, $false)
        $security.AddAccessRule($rule)
        Set-Acl -LiteralPath $Path -AclObject $security
    }
    catch {
        Write-WhatsappLog -Level ERROR -Message ('Failed to secure path {0}: {1}' -f $Path, $_.Exception.Message)
        throw
    }
}

function Initialize-WhatsappDataDirectory {
    foreach ($directory in @($script:ConfigDir, $script:LogDir)) {
        if (-not (Test-Path -LiteralPath $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
    }
    Protect-WhatsappPath -Path $script:ConfigDir
}

function ConvertTo-WhatsappSecureString {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PlainText)

    $secureString = New-Object Security.SecureString
    foreach ($character in $PlainText.ToCharArray()) {
        $secureString.AppendChar($character)
    }
    $secureString.MakeReadOnly()
    return $secureString
}

function ConvertTo-PlainText {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureString)

    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Save-WhatsappProtectedToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstanceId,
        [Parameter(Mandatory = $true)][Security.SecureString]$SecureToken,
        [string]$ApiUrl
    )

    Initialize-WhatsappDataDirectory
    $config = [ordered]@{
        idInstance       = $InstanceId
        apiTokenProtected = ($SecureToken | ConvertFrom-SecureString)
        DateUpdated      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    if ($ApiUrl) { $config.apiUrl = $ApiUrl.TrimEnd('/') }

    $config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigFilePath -Force -Encoding UTF8
    Protect-WhatsappPath -Path $script:ConfigFilePath
}

function New-WhatsappConfigFile {
    <#
    .SYNOPSIS
    Creates a DPAPI-protected Green API configuration for the current Windows user.
    #>
    [CmdletBinding()]
    param([switch]$Force)

    if ((Test-Path -LiteralPath $script:ConfigFilePath) -and -not $Force) {
        Write-Host ('Configuration already exists at {0}.' -f $script:ConfigFilePath) -ForegroundColor Green
        return $true
    }

    $instanceId = Read-Host 'Enter your Green API Instance ID'
    $secureToken = Read-Host 'Enter your Green API API Token' -AsSecureString
    if ([string]::IsNullOrWhiteSpace($instanceId) -or $secureToken.Length -eq 0) {
        Write-Error 'Instance ID and API token cannot be empty.'
        return $false
    }

    try {
        Save-WhatsappProtectedToken -InstanceId $instanceId -SecureToken $secureToken
        Write-Host ('Protected configuration created at {0}.' -f $script:ConfigFilePath) -ForegroundColor Green
        return $true
    }
    catch {
        Write-WhatsappLog -Level ERROR -Message ('Configuration creation failed: {0}' -f $_.Exception.ToString())
        Write-Error ('Configuration creation failed: {0}' -f $_.Exception.Message)
        return $false
    }
}

function Get-WhatsappConfig {
    <#
    .SYNOPSIS
    Loads the current user's DPAPI-protected Green API configuration.
    .DESCRIPTION
    Legacy plaintext tokens are automatically migrated to DPAPI protection.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:ConfigFilePath)) {
        Write-Warning ('Configuration not found at {0}. Run New-WhatsappConfigFile.' -f $script:ConfigFilePath)
        return $false
    }

    try {
        $config = Get-Content -LiteralPath $script:ConfigFilePath -Raw | ConvertFrom-Json
        $global:InstanceId = [string]$config.idInstance
        if ([string]::IsNullOrWhiteSpace($global:InstanceId)) {
            throw 'idInstance is missing from the configuration.'
        }

        if ($config.apiTokenProtected) {
            $secureToken = [string]$config.apiTokenProtected | ConvertTo-SecureString
            $global:Token = ConvertTo-PlainText -SecureString $secureToken
        }
        elseif ($config.apiTokenInstance) {
            $global:Token = [string]$config.apiTokenInstance
            $secureToken = ConvertTo-WhatsappSecureString -PlainText $global:Token
            Save-WhatsappProtectedToken -InstanceId $global:InstanceId -SecureToken $secureToken -ApiUrl ([string]$config.apiUrl)
            Write-Warning 'The legacy plaintext API token was migrated to DPAPI protection.'
            Write-WhatsappLog -Level WARN -Message 'Migrated a legacy plaintext API token to DPAPI protection.'
        }
        else {
            throw 'No protected API token is present in the configuration.'
        }

        if ($config.apiUrl) {
            $global:BaseUrl = '{0}/waInstance{1}' -f ([string]$config.apiUrl).TrimEnd('/'), $global:InstanceId
        }
        elseif ($config.BaseUrl) {
            $global:BaseUrl = [string]$config.BaseUrl
        }
        else {
            if ($global:InstanceId.Length -lt 4) { throw 'The instance ID is invalid.' }
            $prefix = $global:InstanceId.Substring(0, 4)
            $global:BaseUrl = 'https://{0}.api.greenapi.com/waInstance{1}' -f $prefix, $global:InstanceId
        }

        Protect-WhatsappPath -Path $script:ConfigDir
        return $true
    }
    catch {
        $global:InstanceId = $null
        $global:Token = $null
        $global:BaseUrl = $null
        Write-WhatsappLog -Level ERROR -Message ('Configuration load failed: {0}' -f $_.Exception.ToString())
        Write-Error ('Configuration load failed: {0}' -f $_.Exception.Message)
        return $false
    }
}

function Clear-WhatsappLocalData {
    <#
    .SYNOPSIS
    Removes cached media, local chat databases and logs older than the retention period.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param([ValidateRange(0, 3650)][int]$OlderThanDays = 30)

    $cutoff = (Get-Date).AddDays(-$OlderThanDays)
    $targets = @(
        (Join-Path $script:ConfigDir 'MediaCache'),
        (Join-Path $script:ConfigDir 'Database'),
        $script:LogDir
    )

    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target)) { continue }
        Get-ChildItem -LiteralPath $target -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove retained local data')) {
                    Remove-Item -LiteralPath $_.FullName -Force
                }
            }
    }
}

<#
===============================================================================
 ARCHITECT DEPLOYMENT RUNNER
===============================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MainPackageId,

    [Parameter(Mandatory = $true)]
    [string]$MainPackageVersion,

    [Parameter(Mandatory = $true)]
    [string]$ArchitectDeployPath,

    [Parameter(Mandatory = $true)]
    [string]$InstallationDirectoryPath,

    [Parameter(Mandatory = $true)]
    [string]$ArchitectFINumber,

    [Parameter(Mandatory = $true)]
    [string]$ArchitectMachineName,

    [Parameter(Mandatory = $false)]
    [string]$ArchitectBackupDestination = "C:\FiservBackups\",

    [Parameter(Mandatory = $false)]
    [string]$NexusRepositoryBaseUrl = "https://nexus-dev.onefiserv.net/repository",

    [Parameter(Mandatory = $false)]
    [string]$MainPackageRepository,

    [Parameter(Mandatory = $false)]
    [string]$ToolsPackageRepository = "nuget-na-ubg-ds-architect-apm0004833-private-ps-clients",

    [Parameter(Mandatory = $false)]
    [string]$ToolsPackageId = "SchemeRegenerator",

    [Parameter(Mandatory = $false)]
    [string]$ToolsPackageVersion = "1.0.0",

    [Parameter(Mandatory = $false)]
    [string]$WorkingRoot = "C:\Temp\HarnessArchitectDeploy",

    [Parameter(Mandatory = $false)]
    [switch]$KeepTempFiles
)

function New-DeploymentWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkingRoot,

        [Parameter(Mandatory = $true)]
        [string]$MainPackageId,

        [Parameter(Mandatory = $true)]
        [string]$MainPackageVersion
    )

    Write-Host "$($MyInvocation.MyCommand.Name):: START"

    try {
        Write-Host "$($MyInvocation.MyCommand.Name):: Parameters received:"
        Write-Host "$($MyInvocation.MyCommand.Name):: WorkingRoot        : $WorkingRoot"
        Write-Host "$($MyInvocation.MyCommand.Name):: MainPackageId      : $MainPackageId"
        Write-Host "$($MyInvocation.MyCommand.Name):: MainPackageVersion : $MainPackageVersion"

        $deploymentId = "{0}_{1}_{2}" -f $MainPackageId, $MainPackageVersion, (Get-Date -Format "yyyyMMddHHmmss")
        $workspacePath = Join-Path $WorkingRoot $deploymentId

        Write-Host "$($MyInvocation.MyCommand.Name):: Creating workspace: $workspacePath"

        New-Item -ItemType Directory -Force -Path $workspacePath | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $workspacePath "Packages") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $workspacePath "Tools") | Out-Null

        Write-Host "$($MyInvocation.MyCommand.Name):: Result: $workspacePath"

        return $workspacePath
    }
    catch {
        $contextMessage = "$($MyInvocation.MyCommand.Name):: Failed to create deployment workspace"
        Write-Host "$($MyInvocation.MyCommand.Name):: ERROR: $($_.Exception.Message)"
        throw [System.Exception]::new($contextMessage, $_.Exception)
    }
    finally {
        Write-Host "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Save-NuGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [string]$PackageVersion,

        [Parameter(Mandatory = $true)]
        [string]$RepositorySource,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    Write-Host "$($MyInvocation.MyCommand.Name):: START"

    try {
        Write-Host "$($MyInvocation.MyCommand.Name):: Parameters received:"
        Write-Host "$($MyInvocation.MyCommand.Name):: PackageId        : $PackageId"
        Write-Host "$($MyInvocation.MyCommand.Name):: PackageVersion   : $PackageVersion"
        Write-Host "$($MyInvocation.MyCommand.Name):: RepositorySource : $RepositorySource"
        Write-Host "$($MyInvocation.MyCommand.Name):: OutputDirectory  : $OutputDirectory"

        if (-not (Get-Command nuget.exe -ErrorAction SilentlyContinue)) {
            $exception = [System.InvalidOperationException]::new("nuget.exe was not found in PATH.")
            throw [System.Exception]::new("$($MyInvocation.MyCommand.Name):: NuGet executable was not found", $exception)
        }

        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

        Write-Host "$($MyInvocation.MyCommand.Name):: Downloading NuGet package"

        & nuget.exe install $PackageId `
            -Version $PackageVersion `
            -Source $RepositorySource `
            -OutputDirectory $OutputDirectory `
            -NonInteractive

        if ($LASTEXITCODE -ne 0) {
            $exception = [System.InvalidOperationException]::new("nuget.exe failed with exit code $LASTEXITCODE.")
            throw [System.Exception]::new("$($MyInvocation.MyCommand.Name):: Failed to download NuGet package", $exception)
        }

        $packagePath = Join-Path $OutputDirectory "$PackageId.$PackageVersion"

        if (-not (Test-Path $packagePath)) {
            $exception = [System.IO.DirectoryNotFoundException]::new("Expected package directory was not found: $packagePath")
            throw [System.Exception]::new("$($MyInvocation.MyCommand.Name):: Package directory was not found", $exception)
        }

        Write-Host "$($MyInvocation.MyCommand.Name):: Result: $packagePath"

        return $packagePath
    }
    catch {
        $contextMessage = "$($MyInvocation.MyCommand.Name):: Failed to save NuGet package"
        Write-Host "$($MyInvocation.MyCommand.Name):: ERROR: $($_.Exception.Message)"
        throw [System.Exception]::new($contextMessage, $_.Exception)
    }
    finally {
        Write-Host "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Invoke-ExternalPowerShellScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    Write-Host "$($MyInvocation.MyCommand.Name):: START"

    try {
        Write-Host "$($MyInvocation.MyCommand.Name):: Parameters received:"
        Write-Host "$($MyInvocation.MyCommand.Name):: ScriptPath : $ScriptPath"

        foreach ($key in $Parameters.Keys) {
            Write-Host "$($MyInvocation.MyCommand.Name):: $key : $($Parameters[$key])"
        }

        if (-not (Test-Path $ScriptPath)) {
            $exception = [System.IO.FileNotFoundException]::new("Script was not found: $ScriptPath")
            throw [System.Exception]::new("$($MyInvocation.MyCommand.Name):: Script was not found", $exception)
        }

        $argumentList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $ScriptPath
        )

        foreach ($key in $Parameters.Keys) {
            $argumentList += "-$key"
            $argumentList += $Parameters[$key]
        }

        Write-Host "$($MyInvocation.MyCommand.Name):: Running script"

        & powershell.exe @argumentList

        if ($LASTEXITCODE -ne 0) {
            $exception = [System.InvalidOperationException]::new("Script failed with exit code $LASTEXITCODE.")
            throw [System.Exception]::new("$($MyInvocation.MyCommand.Name):: External script failed", $exception)
        }

        Write-Host "$($MyInvocation.MyCommand.Name):: Script completed successfully"
    }
    catch {
        $contextMessage = "$($MyInvocation.MyCommand.Name):: Failed to invoke external PowerShell script"
        Write-Host "$($MyInvocation.MyCommand.Name):: ERROR: $($_.Exception.Message)"
        throw [System.Exception]::new($contextMessage, $_.Exception)
    }
    finally {
        Write-Host "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Invoke-ArchitectDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageRoot,

        [Parameter(Mandatory = $true)]
        [string]$ArchitectDeployPath,

        [Parameter(Mandatory = $true)]
        [string]$InstallationDirectoryPath,

        [Parameter(Mandatory = $true)]
        [string]$ArchitectFINumber,

        [Parameter(Mandatory = $true)]
        [string]$ArchitectMachineName,

        [Parameter(Mandatory = $true)]
        [string]$ArchitectBackupDestination
    )

    Write-Host "$($MyInvocation.MyCommand.Name):: START"

    try {
        Write-Host "$($MyInvocation.MyCommand.Name):: Parameters received:"
        Write-Host "$($MyInvocation.MyCommand.Name):: PackageRoot                   : $PackageRoot"
        Write-Host "$($MyInvocation.MyCommand.Name):: ArchitectDeployPath           : $ArchitectDeployPath"
        Write-Host "$($MyInvocation.MyCommand.Name):: InstallationDirectoryPath     : $InstallationDirectoryPath"
        Write-Host "$($MyInvocation.MyCommand.Name):: ArchitectFINumber             : $ArchitectFINumber"
        Write-Host "$($MyInvocation.MyCommand.Name):: ArchitectMachineName          : $ArchitectMachineName"
        Write-Host "$($MyInvocation.MyCommand.Name):: ArchitectBackupDestination    : $ArchitectBackupDestination"

        $commonParameters = @{
            ArchitectDeployPath        = $ArchitectDeployPath
            InstallationDirectoryPath  = $InstallationDirectoryPath
            ArchitectFINumber          = $ArchitectFINumber
            ArchitectMachineName       = $ArchitectMachineName
            ArchitectBackupDestination = $ArchitectBackupDestination
        }

        Invoke-ExternalPowerShellScript `
            -ScriptPath (Join-Path $PackageRoot "PreDeploy.ps1") `
            -Parameters $commonParameters

        Invoke-ExternalPowerShellScript `
            -ScriptPath (Join-Path $PackageRoot "Deploy.ps1") `
            -Parameters $commonParameters

        Write-Host "$($MyInvocation.MyCommand.Name):: Deployment completed successfully"
    }
    catch {
        $contextMessage = "$($MyInvocation.MyCommand.Name):: Architect deployment failed"
        Write-Host "$($MyInvocation.MyCommand.Name):: ERROR: $($_.Exception.Message)"
        throw [System.Exception]::new($contextMessage, $_.Exception)
    }
    finally {
        Write-Host "$($MyInvocation.MyCommand.Name):: END"
    }
}

function Remove-DeploymentWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspacePath,

        [Parameter(Mandatory = $false)]
        [switch]$KeepTempFiles
    )

    Write-Host "$($MyInvocation.MyCommand.Name):: START"

    try {
        Write-Host "$($MyInvocation.MyCommand.Name):: Parameters received:"
        Write-Host "$($MyInvocation.MyCommand.Name):: WorkspacePath : $WorkspacePath"
        Write-Host "$($MyInvocation.MyCommand.Name):: KeepTempFiles : $KeepTempFiles"

        if ($KeepTempFiles) {
            Write-Host "$($MyInvocation.MyCommand.Name):: Keeping temporary files"
            return
        }

        if (Test-Path $WorkspacePath) {
            Write-Host "$($MyInvocation.MyCommand.Name):: Removing workspace: $WorkspacePath"
            Remove-Item -Path $WorkspacePath -Recurse -Force
        }

        Write-Host "$($MyInvocation.MyCommand.Name):: Workspace cleanup completed"
    }
    catch {
        $contextMessage = "$($MyInvocation.MyCommand.Name):: Failed to remove deployment workspace"
        Write-Host "$($MyInvocation.MyCommand.Name):: ERROR: $($_.Exception.Message)"
        throw [System.Exception]::new($contextMessage, $_.Exception)
    }
    finally {
        Write-Host "$($MyInvocation.MyCommand.Name):: END"
    }
}

Write-Host "Invoke-ArchitectDeploymentRunner:: START"

$workspacePath = $null

try {
    Write-Host "Invoke-ArchitectDeploymentRunner:: Parameters received:"
    Write-Host "Invoke-ArchitectDeploymentRunner:: MainPackageId                : $MainPackageId"
    Write-Host "Invoke-ArchitectDeploymentRunner:: MainPackageVersion           : $MainPackageVersion"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ArchitectDeployPath          : $ArchitectDeployPath"
    Write-Host "Invoke-ArchitectDeploymentRunner:: InstallationDirectoryPath    : $InstallationDirectoryPath"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ArchitectFINumber            : $ArchitectFINumber"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ArchitectMachineName         : $ArchitectMachineName"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ArchitectBackupDestination   : $ArchitectBackupDestination"
    Write-Host "Invoke-ArchitectDeploymentRunner:: NexusRepositoryBaseUrl       : $NexusRepositoryBaseUrl"
    Write-Host "Invoke-ArchitectDeploymentRunner:: MainPackageRepository        : $MainPackageRepository"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ToolsPackageRepository       : $ToolsPackageRepository"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ToolsPackageId               : $ToolsPackageId"
    Write-Host "Invoke-ArchitectDeploymentRunner:: ToolsPackageVersion          : $ToolsPackageVersion"
    Write-Host "Invoke-ArchitectDeploymentRunner:: WorkingRoot                  : $WorkingRoot"
    Write-Host "Invoke-ArchitectDeploymentRunner:: KeepTempFiles                : $KeepTempFiles"

    if ([string]::IsNullOrWhiteSpace($MainPackageRepository)) {
        $exception = [System.ArgumentException]::new("MainPackageRepository is required.")
        throw [System.Exception]::new("Invoke-ArchitectDeploymentRunner:: Missing required repository", $exception)
    }

    $mainPackageSource = "$NexusRepositoryBaseUrl/$MainPackageRepository"
    $toolsPackageSource = "$NexusRepositoryBaseUrl/$ToolsPackageRepository"

    $workspacePath = New-DeploymentWorkspace `
        -WorkingRoot $WorkingRoot `
        -MainPackageId $MainPackageId `
        -MainPackageVersion $MainPackageVersion

    $mainPackageOutputPath = Join-Path $workspacePath "Packages"
    $toolsPackageOutputPath = Join-Path $workspacePath "Tools"

    $mainPackageRoot = Save-NuGetPackage `
        -PackageId $MainPackageId `
        -PackageVersion $MainPackageVersion `
        -RepositorySource $mainPackageSource `
        -OutputDirectory $mainPackageOutputPath

    $toolsPackageRoot = Save-NuGetPackage `
        -PackageId $ToolsPackageId `
        -PackageVersion $ToolsPackageVersion `
        -RepositorySource $toolsPackageSource `
        -OutputDirectory $toolsPackageOutputPath

    Write-Host "Invoke-ArchitectDeploymentRunner:: Tools package downloaded to: $toolsPackageRoot"

    Invoke-ArchitectDeployment `
        -PackageRoot $mainPackageRoot `
        -ArchitectDeployPath $ArchitectDeployPath `
        -InstallationDirectoryPath $InstallationDirectoryPath `
        -ArchitectFINumber $ArchitectFINumber `
        -ArchitectMachineName $ArchitectMachineName `
        -ArchitectBackupDestination $ArchitectBackupDestination

    Write-Host "Invoke-ArchitectDeploymentRunner:: Deployment finished successfully"
}
catch {
    Write-Host "Invoke-ArchitectDeploymentRunner:: ERROR: $($_.Exception.Message)"
    throw
}
finally {
    if ($null -ne $workspacePath) {
        Remove-DeploymentWorkspace `
            -WorkspacePath $workspacePath `
            -KeepTempFiles:$KeepTempFiles
    }

    Write-Host "Invoke-ArchitectDeploymentRunner:: END"
}

# copy pasted from https://gist.github.com/cloudhan/97db3c1e57895a09a80ec1f30c471cb3
function Set-EnvFromCmdSet {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$CmdSetResult
    )
    process {
        if ($CmdSetResult -Match "=") {
            $i = $CmdSetResult.IndexOf("=")
            $k = $CmdSetResult.Substring(0, $i)
            $v = $CmdSetResult.Substring($i + 1)
            Set-Item -Force -Path "Env:\$k" -Value "$v"
        }
    }
}

function Set-VSEnv {
    param (
        [parameter(Mandatory = $false)]
        [ValidateSet(2022, 2019, 2017)]
        [int]$Version = 2022,

        [parameter(Mandatory = $false)]
        [ValidateSet("all", "x86", "x64")]
        [String]$Arch = "x64"
    )

    $vs_where = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'

    if (-not (Test-Path $vs_where)) {
        throw "vswhere.exe not found at '$vs_where'"
    }

    $version_range = switch ($Version) {
        2022 { '[17,18)' }
        2019 { '[16,17)' }
        2017 { '[15,16)' }
    }

    $info = &$vs_where `
        -version $version_range `
        -latest `
        -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -format json | ConvertFrom-Json

    if ($info -is [System.Array]) {
        $info = $info[0]
    }

    $vs_env = @{
        install_path = if ($null -ne $info) { $info.installationPath } else { $null }
        all          = 'Common7\Tools\VsDevCmd.bat'
        x64          = 'VC\Auxiliary\Build\vcvars64.bat'
        x86          = 'VC\Auxiliary\Build\vcvars32.bat'
    }
    if ( $null -eq $vs_env.install_path) {
        throw "Visual Studio $Version with C++ build tools is not installed."
    }

    $path = Join-Path $vs_env.install_path $vs_env.$Arch

    if (-not (Test-Path $path)) {
        throw "Visual Studio environment script not found: $path"
    }

    C:/Windows/System32/cmd.exe /c "`"$path`" & set" | Set-EnvFromCmdSet

    if (-not $env:VCINSTALLDIR) {
        throw "VCINSTALLDIR was not set by $path"
    }

    $cl = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($null -eq $cl) {
        throw "cl.exe was not found after loading Visual Studio $Version $Arch environment."
    }

    if (-not $env:VSINSTALLDIR) {
        throw "VSINSTALLDIR was not set by $path"
    }

    if (-not $env:VCToolsVersion) {
        throw "VCToolsVersion was not set by $path"
    }

    $bazelVc = ([System.IO.Path]::GetFullPath($env:VCINSTALLDIR)).TrimEnd('\')
    $bazelVs = ([System.IO.Path]::GetFullPath($env:VSINSTALLDIR)).TrimEnd('\')
    $bazelVcFullVersion = $env:VCToolsVersion.TrimEnd('\')

    Set-Item -Force -Path "Env:\BAZEL_VS" -Value "$bazelVs"
    Set-Item -Force -Path "Env:\BAZEL_VC" -Value "$bazelVc"
    Set-Item -Force -Path "Env:\BAZEL_VC_FULL_VERSION" -Value "$bazelVcFullVersion"
    Write-Host -ForegroundColor Green "Visual Studio $Version $Arch Command Prompt variables set. cl.exe at $($cl.Source)"
    Write-Host -ForegroundColor Green "BAZEL_VS=$bazelVs"
    Write-Host -ForegroundColor Green "BAZEL_VC=$bazelVc"
    Write-Host -ForegroundColor Green "BAZEL_VC_FULL_VERSION=$bazelVcFullVersion"
}


class EnvironmentStack {
    static [System.Collections.Stack] $stack = [System.Collections.Stack]::new()
}

function Push-Environment {
    [EnvironmentStack]::stack.push([Environment]::GetEnvironmentVariables())
}

function Pop-Environment {
    [EnvironmentStack]::stack.pop().GetEnumerator() |
    ForEach-Object {
        Set-Item -Force -Path ("Env:\" + $_.Key) -Value $_.Value
    }
}

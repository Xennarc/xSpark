<#
Compile in an isolated staging directory, using an installed MetaEditor and its
standard include library. Never copies binaries into the running terminal.
https://www.metatrader5.com/en/metaeditor/help/beginning/integration_ide
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MetaEditor,
    [Parameter(Mandatory=$true)][string]$TerminalDataPath,
    [string]$OutputRoot = (Join-Path ([IO.Path]::GetTempPath()) ('xspark-compile-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!(Test-Path -LiteralPath $MetaEditor -PathType Leaf)) { throw "MetaEditor not found: $MetaEditor" }
$standardIncludes = Join-Path $TerminalDataPath 'MQL5\Include'
if (!(Test-Path -LiteralPath (Join-Path $standardIncludes 'Trade\Trade.mqh'))) {
    throw 'TerminalDataPath must contain MQL5\Include\Trade\Trade.mqh (the installed MT5 standard library).'
}
# Refuse an existing target: no stale EX5/log may make a failed compile pass.
if (Test-Path -LiteralPath $OutputRoot) { throw 'OutputRoot must be a new, empty path.' }
$mql = Join-Path $OutputRoot 'MQL5'
New-Item -ItemType Directory -Path (Join-Path $mql 'Include') -Force | Out-Null
Copy-Item -Path (Join-Path $standardIncludes '*') -Destination (Join-Path $mql 'Include') -Recurse -Force
Copy-Item -Path (Join-Path $repo 'MQL5\*') -Destination $mql -Recurse -Force
$targets = @((Join-Path $mql 'Experts\XSpark\XSpark.mq5'))
$targets += @(Get-ChildItem -LiteralPath (Join-Path $mql 'Scripts\Tests') -Filter '*.mq5' | ForEach-Object { $_.FullName })
$failed = @()
foreach ($target in $targets) {
    $compileArgs = '/compile:"{0}" /include:"{1}" /log' -f $target, $mql
    Start-Process -FilePath $MetaEditor -ArgumentList $compileArgs -Wait -PassThru | Out-Null
    $log = [IO.Path]::ChangeExtension($target, '.log')
    $binary = [IO.Path]::ChangeExtension($target, '.ex5')
    if (!(Test-Path -LiteralPath $log)) {
        $failed += $target
        Write-Warning "No compiler log: $target"
        continue
    }
    # MT5 logs are normally UTF-16LE. Handle UTF-8 logs with the same parser.
    $bytes = [IO.File]::ReadAllBytes($log)
    $unicode = ($bytes.Length -gt 1 -and (($bytes[0] -eq 255 -and $bytes[1] -eq 254) -or $bytes[1] -eq 0))
    $text = if ($unicode) { [Text.Encoding]::Unicode.GetString($bytes) } else { [Text.Encoding]::UTF8.GetString($bytes) }
    $matches = [regex]::Matches($text, '(?im)(\d+) errors?,\s*(\d+) warnings?')
    $clean = $matches.Count -gt 0
    if ($clean) {
        $summary = $matches[$matches.Count - 1]
        $clean = [int]$summary.Groups[1].Value -eq 0 -and [int]$summary.Groups[2].Value -eq 0
    }
    if (!$clean -or !(Test-Path -LiteralPath $binary)) {
        $failed += $target
        Write-Warning "Compilation failed, warned, or produced no EX5: $target"
        Write-Output $text
    } else { Write-Output "PASS: $target (0 errors, 0 warnings; EX5 present)" }
}
Write-Output "Compilation artifacts: $OutputRoot"
if ($failed.Count -gt 0) { throw "$($failed.Count) target(s) failed verification. Read their logs; nothing was deployed." }

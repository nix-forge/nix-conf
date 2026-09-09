param([string]$Path, [string]$Analyzer, [string]$Settings)
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { [Console]::Error.WriteLine($_.ToString()) }
    exit 1
}
Import-Module $Analyzer -ErrorAction Stop
$rules = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json -AsHashtable
# Inspect diagnostics after analysis: some rules assign different severities
# per finding. The command's -Severity parameter filters rules, not findings.
$findings = @(Invoke-ScriptAnalyzer -Path $Path -Settings $rules | Where-Object {
    $_.Severity.ToString() -in @('Error', 'Warning')
})
foreach ($finding in $findings) {
    [Console]::Error.WriteLine(("{0}:{1}:{2}: {3}: {4}" -f $Path, $finding.Line, $finding.Column, $finding.RuleName, $finding.Message))
}
if ($findings.Count -gt 0) { exit 1 }

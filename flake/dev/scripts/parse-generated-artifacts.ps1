param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Paths)
$failed = $false
foreach ($path in $Paths) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $failed = $true
        $errors | ForEach-Object { Write-Error "${path}:$($_.Message)" }
    }
}
if ($failed) { exit 1 }

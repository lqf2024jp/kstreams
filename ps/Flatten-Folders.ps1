[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BasePath = (Get-Location).Path
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$BasePath = (Resolve-Path -LiteralPath $BasePath).Path
$topFolders = Get-ChildItem -LiteralPath $BasePath -Directory

$movedCount = 0
$conflicts = @()

foreach ($top in $topFolders) {
    $topPath = $top.FullName

    $files = Get-ChildItem -LiteralPath $topPath -Recurse -File
    if (-not $files) { continue }

    $filesWithDepth = $files | ForEach-Object {
        $rel = $_.FullName.Substring($topPath.Length).TrimStart('\')
        $depth = ($rel -split '\\').Count - 1
        [PSCustomObject]@{
            File    = $_
            Depth   = $depth
            RelPath = $rel
        }
    } | Sort-Object Depth, RelPath

    # Track which target filenames are already claimed, independent of whether
    # -WhatIf actually performed the move, so conflict detection stays correct
    # in a dry run too.
    $claimed = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($name in ($filesWithDepth | Where-Object { $_.Depth -eq 0 } | ForEach-Object { $_.File.Name })) {
        [void]$claimed.Add($name)
    }

    foreach ($item in $filesWithDepth) {
        if ($item.Depth -eq 0) { continue }

        $target = Join-Path $topPath $item.File.Name

        if ($claimed.Contains($item.File.Name)) {
            $conflicts += [PSCustomObject]@{
                TopFolder      = $top.Name
                ConflictFile   = $item.File.FullName
                ExistingTarget = $target
            }
            Write-Verbose "Conflict, left in place: $($item.File.FullName)"
        }
        else {
            [void]$claimed.Add($item.File.Name)
            if ($PSCmdlet.ShouldProcess($item.File.FullName, "Move to $target")) {
                Move-Item -LiteralPath $item.File.FullName -Destination $target
                $movedCount++
            }
        }
    }
}

Write-Output "Moved: $movedCount file(s)"
Write-Output "Conflicts (left in place, not moved): $($conflicts.Count) file(s)"

if ($conflicts.Count -gt 0) {
    $conflicts | Format-List

    $logPath = Join-Path $BasePath "Flatten-Conflicts.csv"
    $conflicts | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding utf8 -WhatIf:$false
    Write-Output "Conflict log exported to: $logPath"
}

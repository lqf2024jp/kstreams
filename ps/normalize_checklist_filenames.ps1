<#
.SYNOPSIS
    「標準化ルール適用チェックリスト」形式の xlsx ファイル名を正規化するスクリプト。
    括弧を半角に統一し、括弧前後の余分な空白を詰め、バージョン表記の "Ver" 接頭辞を外す。

.DESCRIPTION
    - 対象: ファイル名に「標準化ルール適用チェックリスト」を含む *.xlsx
      (generate_file_list.ps1 とは異なり、無関係な xlsx を巻き込まないよう
      ファイル名に対象キーワードを含むものだけをスキャン対象にする)
    - 変換: 全角括弧（）→半角()、括弧前後の空白除去、"_Ver0.41"→"_0.41" のように
      Ver接頭辞を除去。バージョン部分の正規表現は generate_file_list.ps1 /
      merge_versions_by_id.ps1 / pivot_check_records.ps1 と同じ
      "(?:Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\.xlsx$" を踏襲する
    - 括弧・アンダースコアのどちらも見つからないファイル(例: 拡張子直前がバージョンでも
      括弧でもない "標準化ルール適用チェックリスト.xlsx" や "_split.xlsx")は
      正規化対象がないため「対象外」として一覧表示するだけでリネームしない
    - 既定はプレビューのみ(何も変更しない)。実際にリネームするには -Apply を指定する
    - -Apply 時は、リネーム前に元ファイルを $BackupRoot\$BackupFolderName 以下に
      フォルダ構成を保ったままコピーしてから Rename-Item する(この場所は C:\work\bak
      とは別。C:\work\bak は手動コピーされた .ps1 の旧版置き場であり、データファイルの
      自動バックアップ置き場として流用すると紛らわしいため)
    - リネーム後の名前が「同一バッチ内の他ファイルと重複する」「同フォルダに元々別ファイルとして
      存在する」場合はそのファイルのリネームのみ中止しエラー表示する(上書き事故防止)

.PARAMETER FolderPath
    処理対象のルートフォルダ。既定値は $PSScriptRoot。

.PARAMETER Apply
    指定した場合のみ実際にバックアップ+リネームを行う。指定しない場合はプレビューのみ。

.PARAMETER BackupRoot
    バックアップの保存先ルート。既定値は "$FolderPath\bak"。

.EXAMPLE
    .\normalize_checklist_filenames.ps1
    .\normalize_checklist_filenames.ps1 -Apply
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [switch]$Apply,
    [string]$BackupRoot,
    [string]$BackupFolderName = "normalize_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
)

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}
if ([string]::IsNullOrEmpty($BackupRoot)) {
    $BackupRoot = Join-Path $FolderPath "bak"
}

Write-Host "対象フォルダ: $FolderPath"
Write-Host "モード: $(if ($Apply) { 'Apply(実際にリネーム)' } else { 'プレビューのみ' })" -ForegroundColor Cyan
Write-Host "----------------------------------------"

$files = Get-ChildItem -Path $FolderPath -Recurse -File -Filter "*.xlsx" |
    Where-Object { $_.Name -notlike "~`$*" -and $_.Name -like "*標準化ルール適用チェックリスト*" }

if ($files.Count -eq 0) {
    Write-Host "対象ファイルが見つかりませんでした。"
    exit
}

# 「チェックリスト(内容)_バージョン.xlsx」の形を一括で読み取り、正規化した名前を
# 組み立てる。括弧の全半角統一・空白除去・Ver接頭辞除去をこの1本の正規表現/組み立てで行う
# (3つを別々の -replace にすると、空白と接頭辞除去の順序次第で結果がぶれるため)。
$NormalizeRegex = '^(?<head>.*標準化ルール適用チェックリスト)\s*[（(]\s*(?<inner>.+?)\s*[）)]\s*_?\s*(?:Ver)?(?<ver>\d+(?:\.\d+)+)(?<suf>[A-Za-z]?)\.xlsx$'

function Get-NormalizedFileName {
    param([string]$FileName)
    if ($FileName -match $NormalizeRegex) {
        return "$($matches['head'])($($matches['inner']))_$($matches['ver'])$($matches['suf']).xlsx"
    }
    return $null
}

$toRename = @()
$alreadyOk = @()
$unmatched = @()

# 同フォルダ内の元のファイル名一覧(小文字化)。リネーム後の名前が既存の別ファイルと
# 衝突していないかを確認するために使う(Windowsのファイル名は大文字小文字を区別しない)。
$existingNamesByDir = @{}
foreach ($f in $files) {
    $dir = $f.DirectoryName
    if (-not $existingNamesByDir.ContainsKey($dir)) { $existingNamesByDir[$dir] = @{} }
    $existingNamesByDir[$dir][$f.Name.ToLowerInvariant()] = $true
}

foreach ($f in $files) {
    $relativePath = $f.FullName.Substring($FolderPath.Length).TrimStart('\')
    $newName = Get-NormalizedFileName -FileName $f.Name

    if ($null -eq $newName) {
        $unmatched += $relativePath
        continue
    }

    if ($newName -eq $f.Name) {
        $alreadyOk += $relativePath
        continue
    }

    $toRename += [PSCustomObject]@{
        Directory    = $f.DirectoryName
        RelativeDir  = (Split-Path $relativePath -Parent)
        OldName      = $f.Name
        NewName      = $newName
        OldFullName  = $f.FullName
    }
}

# 衝突チェック1: 同一バッチ内で複数ファイルが同じ新ファイル名になる場合
$collisionGroups = $toRename | Group-Object Directory, NewName | Where-Object { $_.Count -gt 1 }
$collisionKeys = @{}
foreach ($g in $collisionGroups) {
    foreach ($item in $g.Group) { $collisionKeys["$($item.Directory)|$($item.NewName)"] = "同一バッチ内で重複" }
}

# 衝突チェック2: 新ファイル名が同フォルダに元々存在する別ファイルと一致する場合
foreach ($item in $toRename) {
    $key = "$($item.Directory)|$($item.NewName)"
    if ($collisionKeys.ContainsKey($key)) { continue }
    $lowerNew = $item.NewName.ToLowerInvariant()
    if ($lowerNew -ne $item.OldName.ToLowerInvariant() -and
        $existingNamesByDir[$item.Directory].ContainsKey($lowerNew)) {
        $collisionKeys[$key] = "既存の別ファイルと同名"
    }
}

$collisions = @()
$safeToRename = @()
foreach ($item in $toRename) {
    $key = "$($item.Directory)|$($item.NewName)"
    if ($collisionKeys.ContainsKey($key)) {
        $collisions += [PSCustomObject]@{ Item = $item; Reason = $collisionKeys[$key] }
    } else {
        $safeToRename += $item
    }
}

if ($safeToRename.Count -gt 0) {
    Write-Host "変更予定 ($($safeToRename.Count) 件):" -ForegroundColor Cyan
    $safeToRename | Select-Object RelativeDir, OldName, NewName | Format-Table -AutoSize
}

if ($collisions.Count -gt 0) {
    Write-Host "衝突のためスキップ ($($collisions.Count) 件):" -ForegroundColor Red
    foreach ($c in $collisions) {
        Write-Host "  - [$($c.Reason)] $($c.Item.RelativeDir)\$($c.Item.OldName) -> $($c.Item.NewName)" -ForegroundColor Red
    }
}

if ($alreadyOk.Count -gt 0) {
    Write-Host "既に準拠済み: $($alreadyOk.Count) 件" -ForegroundColor Yellow
}

if ($unmatched.Count -gt 0) {
    Write-Host "対象外(括弧+バージョンの形式に一致しないため未処理): $($unmatched.Count) 件" -ForegroundColor Yellow
    $unmatched | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

Write-Host "----------------------------------------"

if (-not $Apply) {
    Write-Host "プレビューのみです。実際にリネームするには -Apply を指定して再実行してください。" -ForegroundColor Cyan
    exit
}

if ($safeToRename.Count -eq 0) {
    Write-Host "リネーム対象がないため終了します。" -ForegroundColor Cyan
    exit
}

$backupDir = Join-Path $BackupRoot $BackupFolderName
$renamedCount = 0
$errorCount = 0

foreach ($item in $safeToRename) {
    try {
        $backupSubDir = if ($item.RelativeDir) { Join-Path $backupDir $item.RelativeDir } else { $backupDir }
        New-Item -ItemType Directory -Path $backupSubDir -Force | Out-Null
        Copy-Item -LiteralPath $item.OldFullName -Destination (Join-Path $backupSubDir $item.OldName) -Force

        Rename-Item -LiteralPath $item.OldFullName -NewName $item.NewName -ErrorAction Stop
        Write-Host "OK: $($item.RelativeDir)\$($item.OldName) -> $($item.NewName)" -ForegroundColor Green
        $renamedCount++
    }
    catch {
        Write-Host "エラー: $($item.RelativeDir)\$($item.OldName) - $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "----------------------------------------"
Write-Host "完了: リネーム $renamedCount 件 / 既に準拠 $($alreadyOk.Count) 件 / 対象外 $($unmatched.Count) 件 / 衝突スキップ $($collisions.Count) 件 / エラー $errorCount 件" -ForegroundColor Green
if ($renamedCount -gt 0) {
    Write-Host "バックアップ先: $backupDir" -ForegroundColor Green
}

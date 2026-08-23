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
    - 右括弧の欠落・"]"での代用・バージョンが括弧より前にある・Windowsのコピー時重複
      サフィックス "(2)" が付いている、といった実データの表記ゆれにも対応する
      (詳細は本体のコメント参照)。バージョンの後ろに人が書いた注記が続くものなど、
      機械的に安全と判断できないファイルは「対象外」として一覧表示するだけでリネームしない
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

# generate_file_list.ps1 と同じ2段階パース(先にバージョンを抜き出してから、残りを
# 括弧形式/アンダースコア形式のどちらかに当てはめる)を踏襲する。括弧形式だけを見る
# 単一正規表現では、括弧を使わない「アンダースコア形式」(標準化ルール適用チェックリスト_...)
# のファイルを拾えないため。
# バージョンが全く無いファイル(括弧・アンダースコアの装飾も名称も無い裸ファイルや、
# Split-MergedCells.ps1 の副産物 "_split.xlsx" など)は対象外として扱う。
#
# 実データには下記のような表記ゆれもあるため、それぞれ個別に対応する:
#   - バージョンの直前に Windows のコピー時重複サフィックス " (2)" が付いている
#     -> バージョン抽出の邪魔になるので先に剥がす(剥がした結果、既存の別ファイルと
#        同名になってしまう場合は後段の衝突チェックで検出されるため、ここで安全に剥がしてよい)
#   - バージョンと拡張子の間に余分な空白がある(例: "_Ver0.20 .xlsx")
#     -> 空白を許容するよう正規表現側で吸収する
#   - 右括弧が全角/半角ではなく "]" になっている -> 右括弧の文字クラスに追加する
#   - 右括弧そのものが無い(左括弧だけで終わっている) -> バージョンを取り除いた残り
#     全部を inner として扱い、右括弧は補って出力する(位置はバージョンを取り除いた
#     地点で確定するので、位置の推測にはならない)
#   - バージョンが括弧の"前"に書かれている(例: "チェックリスト 0.55(RP_...).xlsx")
#     -> 末尾からのバージョン抽出に失敗した場合のフォールバックとして別ルートで解析する
#
# 一方、バージョンの後ろに人が書いた注記が続くもの(例: "1.04_■から設計者へ .xlsx")は
# どこまでが正式なバージョン表記か機械的に判断できないため、あえて対象外のままにする。
$VersionTailRegex = '(?:Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\s*\.xlsx$'
$DupSuffixRegex = '\s*\(\d+\)$'
$BracketClosedRegex = '^(?<head>.*標準化ルール適用チェックリスト)\s*[（(]\s*(?<inner>.+?)\s*[）)\]]\s*$'
$BracketOpenOnlyRegex = '^(?<head>.*標準化ルール適用チェックリスト)\s*[（(]\s*(?<inner>.+)$'
$UnderscoreOnlyRegex = '^(?<head>.*標準化ルール適用チェックリスト)_(?<inner>.+)$'
$VersionPrefixRegex = '^(?<head>.*標準化ルール適用チェックリスト)\s*(?<ver>\d+(?:\.\d+)+)(?<suf>[A-Za-z]?)\s*[（(]\s*(?<inner>.+?)\s*[）)\]]\s*$'

function Build-NormalizedName {
    param($Head, $Inner, $Ver, $Suf)
    return "$Head($($Inner.Trim()))_$Ver$Suf.xlsx"
}

# 戻り値: リネーム後の名前が求まった場合は @{ Name = ...; Note = ... }(Noteは通常のケースなら
# 空文字、右括弧を補った/バージョン位置を動かした等の推測を伴う場合のみ理由を入れる)。
# 対象外の場合は $null。
function Get-NormalizedFileName {
    param([string]$FileName)

    $baseName = (($FileName -replace '\.xlsx$', '') -replace $DupSuffixRegex, '').TrimEnd()
    $hadDupSuffix = ($FileName -replace '\.xlsx$', '').TrimEnd() -ne $baseName

    $tailCheck = "$baseName.xlsx"
    if ($tailCheck -match $VersionTailRegex) {
        $ver = $matches[1]
        $suf = $matches[2]
        $nameForParsing = $baseName -replace ('_?(?:Ver)?' + [regex]::Escape($ver + $suf) + '\s*$'), ''

        if ($nameForParsing -match $BracketClosedRegex) {
            $name = Build-NormalizedName $matches['head'] $matches['inner'] $ver $suf
            $note = if ($hadDupSuffix) { "Windows重複サフィックスを除去" } else { "" }
            return @{ Name = $name; Note = $note }
        }
        if ($nameForParsing -match $BracketOpenOnlyRegex) {
            $name = Build-NormalizedName $matches['head'] $matches['inner'] $ver $suf
            return @{ Name = $name; Note = "右括弧が無かったため補完" }
        }
        if ($nameForParsing -match $UnderscoreOnlyRegex) {
            $name = Build-NormalizedName $matches['head'] $matches['inner'] $ver $suf
            $note = if ($hadDupSuffix) { "Windows重複サフィックスを除去" } else { "" }
            return @{ Name = $name; Note = $note }
        }
        return $null
    }

    # 末尾にバージョンが見つからない場合、「バージョンが括弧の前に書かれている」形式を試す
    if ($baseName -match $VersionPrefixRegex) {
        $name = Build-NormalizedName $matches['head'] $matches['inner'] $matches['ver'] $matches['suf']
        return @{ Name = $name; Note = "バージョンの位置を括弧の後ろに移動" }
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
    $result = Get-NormalizedFileName -FileName $f.Name

    if ($null -eq $result) {
        $unmatched += $relativePath
        continue
    }

    if ($result.Name -eq $f.Name) {
        $alreadyOk += $relativePath
        continue
    }

    $toRename += [PSCustomObject]@{
        Directory    = $f.DirectoryName
        RelativeDir  = (Split-Path $relativePath -Parent)
        OldName      = $f.Name
        NewName      = $result.Name
        Note         = $result.Note
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
    $safeToRename | Select-Object RelativeDir, OldName, NewName, Note | Format-Table -AutoSize

    $inferred = $safeToRename | Where-Object { $_.Note }
    if ($inferred.Count -gt 0) {
        Write-Host "うち $($inferred.Count) 件は推測を伴う補完(右括弧の補完・バージョン位置の移動・重複サフィックス除去)です。-Apply 前に必ず内容を確認してください。" -ForegroundColor Magenta
    }
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

# 件数が多いとコンソール/スクリーンショットでは読み切れないため、確認用にファイルへも出力する。
$unmatchedReportPath = Join-Path $FolderPath "normalize_unmatched.txt"
$previewReportPath = Join-Path $FolderPath "normalize_preview.csv"

if ($unmatched.Count -gt 0) {
    $unmatched | Out-File -FilePath $unmatchedReportPath -Encoding UTF8
    Write-Host "対象外一覧を出力しました: $unmatchedReportPath" -ForegroundColor Cyan
} elseif (Test-Path $unmatchedReportPath) {
    Remove-Item $unmatchedReportPath -Force
}

if ($safeToRename.Count -gt 0) {
    $safeToRename | Select-Object RelativeDir, OldName, NewName, Note |
        Export-Csv -Path $previewReportPath -Encoding UTF8 -NoTypeInformation
    Write-Host "変更予定一覧を出力しました: $previewReportPath" -ForegroundColor Cyan
} elseif (Test-Path $previewReportPath) {
    Remove-Item $previewReportPath -Force
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

<#
.SYNOPSIS
    フォルダ以下(サブフォルダ含む)にある「標準化ルール適用チェックリスト」形式の
    xlsx ファイルすべてから、ファイル名を解析して一覧表(ファイル一覧.xlsx)を
    生成するスクリプト。

.DESCRIPTION
    - フォルダ内(既定ではスクリプト自身の場所)の xlsx を再帰的に検索
      (Excel 起動中にできる ~$xxx.xlsx は除外)
    - ファイル名から ID/名称 を抽出する。対応する命名形式は3種類:
        全角括弧      : 標準化ルール適用チェックリスト（...）
        半角括弧      : 標準化ルール適用チェックリスト(...)
        アンダースコア: 標準化ルール適用チェックリスト_...(括弧を使わないファイル用)
      どれにも一致しないファイルは一覧から除外されるが、件数と一覧を最後に表示するので
      漏れに気付ける
    - ID の先頭セグメント(最初の "_" までの部分。例: IO_06_020_0010_07 なら "IO")を
      ID分類 列として自動抽出する。IO/DL/PT などの意味付けは手元のデータからは
      断定できないため、コード自体をそのまま分類キーとして出力する
    - ファイル名末尾のバージョン表記(_Ver0.41 / _0.58(接頭辞なし) / _Ver0.99g(末尾英字) /
      _1.03 / 表記なし、など)を解析する。バージョン列には実際の値ではなく、
      「Ver+小数」「小数のみ」「Ver+小数+英字」「小数+英字」「バージョンなし」という
      表記パターンの分類を出力する(命名規則の書き方が揃っているかを確認する用途)
    - 担当領域 = 一級サブフォルダ名(共通/債権/販売①/販売②/販売③など)
    - ファイルパス列にルートフォルダからの相対パスを出力する(ファイル名の重複だけでは
      どのフォルダのファイルか分からないため)
    - 出力は Excel COM 経由で xlsx として書き出す。COM は try/finally で確実に解放し、
      保存先が Excel で開かれたままなどの理由で失敗しても、エラーメッセージを出した上で
      Excel プロセスが残らないようにする

.PARAMETER FolderPath
    処理対象のルートフォルダ。既定値はこのスクリプト自身が置かれているフォルダ
    ($PSScriptRoot)。ダブルクリックではなく手動で dot-source した場合など
    $PSScriptRoot が空になるケースのみ、カレントディレクトリにフォールバックする。

.PARAMETER OutFileName
    出力ファイル名。既定 "ファイル一覧.xlsx"(ルートフォルダ直下に保存)。

.EXAMPLE
    .\generate_file_list.ps1
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [string]$OutFileName = "ファイル一覧.xlsx"
)

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

Write-Host "対象フォルダ: $FolderPath"

$files = Get-ChildItem -Path $FolderPath -Recurse -Filter "*.xlsx" -File | Where-Object { $_.Name -notlike "~$*" }

if ($files.Count -eq 0) {
    Write-Host "処理対象の .xlsx ファイルが見つかりませんでした。"
    exit
}

Write-Host "検出ファイル数: $($files.Count)"
Write-Host "----------------------------------------"

# ファイル名の末尾からバージョン表記を抜き出す(merge_versions_by_id.ps1 /
# pivot_check_records.ps1 と同じ正規表現)。
# "_Ver0.41" "_1.03" "_0.58"(接頭辞なし) "_Ver0.99g"(末尾に英字1文字) など
# 表記ゆれがあるため、拡張子の直前にある「数字.数字...(英字1文字)」だけを見る。
# 見つからない場合は空文字を返す(バージョン表記なし)。
# 戻り値は名称からバージョン部分を切り離す用途(ID/名称の解析)にのみ使う、実際の数値。
function Get-FileVersionText {
    param([string]$fileName)

    if ($fileName -match '(?:Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\.xlsx$') {
        return $matches[1] + $matches[2]
    }
    return ""
}

# バージョン表記の「書き方」を分類する(実際のバージョン値そのものではなく、
# 命名規則が守られているかを見るための分類パターン)。
# 「Ver」接頭辞の有無 x 末尾英字の有無で4パターン、表記自体が無ければ「バージョンなし」。
function Get-FileVersionPattern {
    param([string]$fileName)

    if ($fileName -match '(Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\.xlsx$') {
        $hasPrefix = -not [string]::IsNullOrEmpty($matches[1])
        $hasSuffix = -not [string]::IsNullOrEmpty($matches[3])

        if ($hasPrefix -and $hasSuffix) { return "Ver+小数+英字" }
        if ($hasPrefix) { return "Ver+小数" }
        if ($hasSuffix) { return "小数+英字" }
        return "小数のみ"
    }
    return "バージョンなし"
}

$results = @()
$unmatchedFiles = @()

foreach ($f in $files) {
    $name = $f.BaseName  # 拡張子を含まないファイル名
    $version = Get-FileVersionText -fileName $f.Name
    $versionPattern = Get-FileVersionPattern -fileName $f.Name

    # 括弧形式は右括弧が区切りになるので、括弧の外にあるバージョン表記(例: "）_Ver0.41")は
    # 元々 $inner に含まれない。一方アンダースコア形式は区切りが無いため、末尾のバージョン
    # 表記を先に取り除いておかないと名称にバージョンが混入してしまう(例:
    # "IO_..._他部門得意先出荷入力_Ver0.99g" のまま解析すると 名称="他部門得意先出荷入力_Ver0.99g" になる)。
    $nameForParsing = $name
    if ($version -ne "") {
        $nameForParsing = $name -replace ('_?(?:Ver)?' + [regex]::Escape($version) + '$'), ''
    }

    # 「標準化ルール適用チェックリスト(...)」括弧内の内容を抽出する。
    # 括弧は全角（）・半角() どちらでもよいが、実際に使われた方を命名形式列に残す。
    # 括弧を使わず「標準化ルール適用チェックリスト_...」形式のファイルにも対応する。
    $inner = $null
    $nameFormat = ""

    if ($nameForParsing -match '標準化ルール適用チェックリスト\s*([（(])\s*(.+?)\s*[）)]') {
        $inner = $matches[2]
        $nameFormat = if ($matches[1] -eq '（') { "全角括弧" } else { "半角括弧" }
    } elseif ($nameForParsing -match '標準化ルール適用チェックリスト_(.+)$') {
        $inner = $matches[1]
        $nameFormat = "アンダースコア"
    }

    if ($null -eq $inner) {
        $relativeFilePath = $f.FullName.Substring($FolderPath.Length).TrimStart('\')
        $unmatchedFiles += $relativeFilePath
        continue
    }

    # 括弧内容を ID (先頭の ASCII: 字母/数字/下划線) と 名称 (最初の非ASCII/日本語文字以降)
    # に分割する。ID内部の構造は統一されていない(字母段+数字段が混在、前缀の文字数も
    # 一定でない)ため、"最初の非ASCII文字が出る位置"で切る方式にしている。
    # 例: "CMN_WP_BP_003_ワークフロー取戻処理" -> ID=CMN_WP_BP_003, 名称=ワークフロー取戻処理
    if ($inner -match '^([\x00-\x7F]+?)_?([^\x00-\x7F].*)$') {
        $id = $matches[1]
        $label = $matches[2]
    } else {
        # 全部ASCII(日本語名称部分が無い)極端なケース。ID に原文をそのまま入れ、名称は空にする
        $id = $inner
        $label = ""
    }

    # ID分類 = ID の先頭セグメント(最初の "_" まで)。IO/DL/PT などが何を意味するかは
    # 手元のデータだけでは断定できないため、コードそのものを分類キーとして出力する
    # (意味付けは利用者側で後付けできるように)。
    $idPrefix = ($id -split '_')[0]

    $relativePath = $f.DirectoryName.Substring($FolderPath.Length).TrimStart('\')
    $topFolder = ($relativePath -split '\\')[0]
    $relativeFilePath = $f.FullName.Substring($FolderPath.Length).TrimStart('\')

    $results += [PSCustomObject]@{
        担当領域     = $topFolder
        ID           = $id
        ID分類       = $idPrefix
        名称         = $label
        バージョン   = $versionPattern
        ファイル名   = $f.Name
        ファイルパス = $relativeFilePath
        命名形式     = $nameFormat
    }
}

Write-Host "解析成功: $($results.Count) 件 / 命名規則に一致しなかったファイル: $($unmatchedFiles.Count) 件"
if ($unmatchedFiles.Count -gt 0) {
    Write-Host "命名規則に一致しなかったファイル(一覧には含まれません):" -ForegroundColor Yellow
    $unmatchedFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if ($results.Count -eq 0) {
    Write-Host "命名規則に一致するファイルがありませんでした。出力ファイルは作成しません。"
    exit
}

$sorted = $results | Sort-Object 担当領域, ID分類, ID
Write-Host "----------------------------------------"
$sorted | Format-Table -AutoSize

$xlsxPath = Join-Path $FolderPath $OutFileName

$excel = $null
$workbook = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $workbook = $excel.Workbooks.Add()
    $sheet = $workbook.Worksheets.Item(1)

    $headers = @("担当領域", "ID", "ID分類", "名称", "バージョン", "ファイル名", "ファイルパス", "命名形式")

    # データ範囲をあらかじめ文字列書式にしておく。そうしないと ID の "0010" が 10 に
    # なったり、バージョンの "0.58" が 0.58(数値)として書式が変わったりする
    # (collect_check_records.ps1 / merge_versions_by_id.ps1 と同じ対策)。
    $dataRange = $sheet.Range($sheet.Cells(2, 1), $sheet.Cells($sorted.Count + 1, $headers.Count))
    $dataRange.NumberFormat = "@"

    for ($c = 0; $c -lt $headers.Count; $c++) {
        $sheet.Cells.Item(1, $c + 1) = $headers[$c]
        $sheet.Cells.Item(1, $c + 1).Font.Bold = $true
    }

    $row = 2
    foreach ($item in $sorted) {
        $sheet.Cells.Item($row, 1) = $item.担当領域
        $sheet.Cells.Item($row, 2) = $item.ID
        $sheet.Cells.Item($row, 3) = $item.ID分類
        $sheet.Cells.Item($row, 4) = $item.名称
        $sheet.Cells.Item($row, 5) = $item.バージョン
        $sheet.Cells.Item($row, 6) = $item.ファイル名
        $sheet.Cells.Item($row, 7) = $item.ファイルパス
        $sheet.Cells.Item($row, 8) = $item.命名形式
        $row++
    }

    $usedRange = $sheet.UsedRange
    $usedRange.EntireColumn.AutoFit() | Out-Null

    # xlsx として保存 (FileFormat 51 = xlOpenXMLWorkbook)
    $workbook.SaveAs($xlsxPath, 51)
    $workbook.Close($false)
    $workbook = $null
    $excel.Quit()

    Write-Host "`n出力しました: $xlsxPath" -ForegroundColor Green
}
catch {
    Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $OutFileName が Excel で開かれている場合は、閉じてから再実行してください。" -ForegroundColor Red
}
finally {
    if ($null -ne $workbook) {
        try { $workbook.Close($false) } catch {}
    }
    if ($null -ne $excel) {
        try { $excel.Quit() } catch {}
        try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {}
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

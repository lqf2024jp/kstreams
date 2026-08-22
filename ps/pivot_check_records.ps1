<#
.SYNOPSIS
    実施記録一覧.xlsx(長い形式: 1行 = 1ファイルの1項番の記録)を、
    1行 = 1ファイル、列 = 項番 の一覧表(out.xlsx)に変換するスクリプト。

.DESCRIPTION
    - 実施記録一覧.xlsx をファイル名でグループ化し、各ファイルの各項番について
      「NGが1件でもあればNG、無ければOKが1件でもあればOK、どちらも無ければ空欄」
      というルールで結果を1つにまとめる
    - out.xlsx の1~3行目(見出し・項番の並び・列幅など)は一切変更しない。
      1行目E列以降に既に入っている項番の並び順・重複もそのまま使う
    - out.xlsx 自体を開いて4行目以降だけを書き換える(新しいファイルは作らない)

.PARAMETER FolderPath
    処理対象のフォルダ。既定値はこのスクリプト自身が置かれているフォルダ($PSScriptRoot)。

.PARAMETER InFileName
    入力ファイル名。既定値 "実施記録一覧.xlsx"。

.PARAMETER OutFileName
    出力先ファイル名。既定値 "out.xlsx"。このファイル自体を開いて4行目以降を書き換える
    (1~3行目の見出し・書式はそのまま)ので、事前に存在している必要がある。

.EXAMPLE
    .\pivot_check_records.ps1
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [string]$InFileName = "実施記録一覧.xlsx",
    [string]$OutFileName = "out.xlsx"
)

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

$inPath = Join-Path $FolderPath $InFileName
$outPath = Join-Path $FolderPath $OutFileName

if (-not (Test-Path $inPath)) {
    Write-Host "入力ファイルが見つかりません: $inPath" -ForegroundColor Red
    exit
}
if (-not (Test-Path $outPath)) {
    Write-Host "出力先のテンプレートファイルが見つかりません: $outPath" -ForegroundColor Red
    Write-Host "(項番の列見出しをこのファイルの1行目E列以降からコピーするため必要です)" -ForegroundColor Red
    exit
}

# 指定したテキストが表す列番号を、ヘッダー行(1行目)から探す
function Find-HeaderColumn {
    param($ws, [string]$text, [int]$lastCol)

    for ($c = 1; $c -le $lastCol; $c++) {
        if ($ws.Cells(1, $c).Value2 -eq $text) { return $c }
    }
    return $null
}

$excel = $null
$wbIn = $null
$wbOut = $null
$records = $null
$templateHeaders = @()

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    # ---- 実施記録一覧.xlsx を読み込む ----
    $wbIn = $excel.Workbooks.Open($inPath, [Type]::Missing, $true)  # ReadOnly
    $wsIn = $wbIn.Worksheets.Item(1)
    $usedIn = $wsIn.UsedRange
    $lastColIn = [int]$usedIn.Column + [int]$usedIn.Columns.Count - 1
    $lastRowIn = [int]$usedIn.Row + [int]$usedIn.Rows.Count - 1

    $colTopFolder = Find-HeaderColumn -ws $wsIn -text "担当領域" -lastCol $lastColIn
    $colId         = Find-HeaderColumn -ws $wsIn -text "ID"       -lastCol $lastColIn
    $colLabel      = Find-HeaderColumn -ws $wsIn -text "名称"     -lastCol $lastColIn
    $colFileName   = Find-HeaderColumn -ws $wsIn -text "ファイル名" -lastCol $lastColIn
    $colItemNo     = Find-HeaderColumn -ws $wsIn -text "項番"     -lastCol $lastColIn
    $colResult     = Find-HeaderColumn -ws $wsIn -text "結果"     -lastCol $lastColIn

    if ($null -eq $colTopFolder -or $null -eq $colId -or $null -eq $colLabel -or
        $null -eq $colFileName -or $null -eq $colItemNo -or $null -eq $colResult) {
        throw "$InFileName の1行目から必要な列(担当領域/ID/名称/ファイル名/項番/結果)が見つかりませんでした。"
    }

    # ファイル名をキーに、ファイル情報と「項番 -> 結果(OK/NG)」の対応を集計する
    # (Ordered なので、実施記録一覧.xlsx に最初に出てきた順でファイルが並ぶ)
    $files = [ordered]@{}

    for ($r = 2; $r -le $lastRowIn; $r++) {
        $fileName = $wsIn.Cells($r, $colFileName).Text
        if ([string]::IsNullOrEmpty($fileName)) { continue }

        if (-not $files.Contains($fileName)) {
            $files[$fileName] = [PSCustomObject]@{
                担当領域   = $wsIn.Cells($r, $colTopFolder).Text
                ID         = $wsIn.Cells($r, $colId).Text
                名称       = $wsIn.Cells($r, $colLabel).Text
                ファイル名 = $fileName
                項番結果   = @{}   # 項番 -> "OK" / "NG"
            }
        }

        $itemNo = $wsIn.Cells($r, $colItemNo).Text
        $result = $wsIn.Cells($r, $colResult).Text
        if ([string]::IsNullOrEmpty($itemNo)) { continue }
        if ($result -ne "OK" -and $result -ne "NG") { continue }

        $entry = $files[$fileName]
        if ($result -eq "NG") {
            $entry.項番結果[$itemNo] = "NG"
        } elseif (-not $entry.項番結果.ContainsKey($itemNo)) {
            $entry.項番結果[$itemNo] = "OK"
        }
    }

    $records = $files.Values | Sort-Object 担当領域, ID, ファイル名

    $wbIn.Close($false)
    $wbIn = $null

    # ---- out.xlsx 自体を書き込み可能で開く(1~3行目は一切書き換えない) ----
    $wbOut = $excel.Workbooks.Open($outPath)
    $sheet = $wbOut.Worksheets.Item(1)
    $usedOut = $sheet.UsedRange
    $lastColOut = [int]$usedOut.Column + [int]$usedOut.Columns.Count - 1
    $lastRowOut = [int]$usedOut.Row + [int]$usedOut.Rows.Count - 1

    # 1行目のE列以降を、項番の列見出しとしてそのまま読み込む(並び・重複はそのまま使う)
    for ($c = 5; $c -le $lastColOut; $c++) {
        $templateHeaders += $sheet.Cells(1, $c).Text
    }

    if ($templateHeaders.Count -eq 0) {
        throw "$OutFileName の1行目のE列以降に項番の見出しが見つかりませんでした。"
    }

    $colCount = 4 + $templateHeaders.Count
    $dataStartRow = 4
    $dataEndRow = $dataStartRow + $records.Count - 1

    # 前回実行時の残りデータが今回より行数が多い場合に備えて、4行目から
    # 現在の最終行までをクリアしてから書き直す(書式は消さない ClearContents を使う)
    $clearLastRow = [Math]::Max($lastRowOut, $dataEndRow)
    if ($clearLastRow -ge $dataStartRow) {
        $sheet.Range($sheet.Cells($dataStartRow, 1), $sheet.Cells($clearLastRow, $colCount)).ClearContents() | Out-Null
    }

    if ($records.Count -gt 0) {
        # 書き込むデータ範囲だけテキスト書式にする(1~3行目の書式には触れない)。
        # そうしないと "06" のような数字だけの結果/項番が書き込み時に数値化されてしまう。
        $dataRange = $sheet.Range($sheet.Cells($dataStartRow, 1), $sheet.Cells($dataEndRow, $colCount))
        $dataRange.NumberFormat = "@"
    }

    $row = $dataStartRow
    foreach ($item in $records) {
        $sheet.Cells.Item($row, 1) = $item.担当領域
        $sheet.Cells.Item($row, 2) = $item.ID
        $sheet.Cells.Item($row, 3) = $item.名称
        $sheet.Cells.Item($row, 4) = $item.ファイル名

        for ($i = 0; $i -lt $templateHeaders.Count; $i++) {
            $itemNo = $templateHeaders[$i]
            if ($item.項番結果.ContainsKey($itemNo)) {
                $sheet.Cells.Item($row, 5 + $i) = $item.項番結果[$itemNo]
            }
        }
        $row++
    }

    $wbOut.Save()
    $wbOut.Close($false)
    $wbOut = $null

    Write-Host "対象ファイル数: $($records.Count)" -ForegroundColor Green
    Write-Host "項番の列数: $($templateHeaders.Count)" -ForegroundColor Green
    Write-Host "出力しました($dataStartRow 行目から): $outPath" -ForegroundColor Green
}
catch {
    Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $OutFileName が Excel で開かれている場合は、閉じてから再実行してください。" -ForegroundColor Red
}
finally {
    if ($null -ne $wbIn) { try { $wbIn.Close($false) } catch {} }
    if ($null -ne $wbOut) { try { $wbOut.Close($false) } catch {} }
    if ($null -ne $excel) {
        try { $excel.Quit() } catch {}
        try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {}
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

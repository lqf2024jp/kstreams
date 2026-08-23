<#
.SYNOPSIS
    フォルダ以下(サブフォルダ含む)にある「標準化ルール適用チェックリスト」形式の
    xlsx ファイルすべてから、「画面(基本設計)」「帳票(基本設計)」シートの
    項番ごとの実施記録(バージョン/実施日/実施者/結果)を収集し、
    一覧表として書き出すスクリプト。

.DESCRIPTION
    - フォルダ内(既定ではスクリプト自身の場所)の xlsx を再帰的に検索
    - ファイル名が「標準化ルール適用チェックリスト(...)」の形式のものだけを対象とする
    - 対象シートの「項番」ヘッダーを手動ループで探し(Find メソッドは COM 経由だと
      型キャストエラーが出やすいため使用しない)、その近くの行から
      「バージョン」「実施日」「実施者」「結果」ヘッダーを探す
    - 項番の行から最終データ行まで、1行ごとに実施記録を読み取る
      (項番が結合セルのままでも、結合範囲の左上セルの値を使うので問題ない)
    - 全ファイル分の記録をまとめて1つの xlsx に出力する

.PARAMETER FolderPath
    処理対象のルートフォルダ。既定値はこのスクリプト自身が置かれているフォルダ($PSScriptRoot)。

.PARAMETER Recurse
    サブフォルダを含めるかどうか。既定で $true。

.PARAMETER OutFileName
    出力ファイル名。既定値は実行日の日付付きで "yyyyMMdd_実施記録一覧_merge_befor.xlsx"
    (スクリプトと同じフォルダに保存)。

.EXAMPLE
    .\collect_check_records.ps1
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [bool]$Recurse = $true,
    [string]$OutFileName = "$(Get-Date -Format 'yyyyMMdd')_実施記録一覧_merge_befor.xlsx"
)

# 処理対象とするシート名(この2つ以外のシートは無条件でスキップ)
$SheetNameScreen = "画面(基本設計)"
$SheetNameReport = "帳票(基本設計)"
$TargetSheetNames = @($SheetNameScreen, $SheetNameReport)

# 実施記録のヘッダーを探す際に、項番ヘッダー行から何行下まで見るか
$RecordHeaderSearchRows = 3

# 「項番」ヘッダーを探す際に走査する最大行数
$HeaderSearchMaxRows = 30

# xlUp 定数 (Excel VBA の xlUp = -4162)
$xlUp = -4162

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

Write-Host "対象フォルダ: $FolderPath"
Write-Host "サブフォルダを含む: $Recurse"
Write-Host "対象シート: $($TargetSheetNames -join ', ')"

$getChildParams = @{
    Path   = $FolderPath
    Filter = "*.xlsx"
    File   = $true
}
if ($Recurse) { $getChildParams["Recurse"] = $true }

$files = Get-ChildItem @getChildParams | Where-Object { $_.Name -notlike "~$*" }

if ($files.Count -eq 0) {
    Write-Host "処理対象の .xlsx ファイルが見つかりませんでした。"
    exit
}

Write-Host "検出ファイル数: $($files.Count)"
Write-Host "----------------------------------------"

# 「項番」ヘッダーセルを、UsedRange内を手動ループして探す
# (COM経由のFindメソッドは型キャストエラーが出やすいため使わない)
function Find-HeaderCell {
    param($ws, [string]$text, [int]$maxRows)

    $usedRange = $ws.UsedRange
    $firstRow = [int]$usedRange.Row
    $firstCol = [int]$usedRange.Column
    $totalRows = [int]$usedRange.Rows.Count
    $totalCols = [int]$usedRange.Columns.Count

    $lastRow = $firstRow + $totalRows - 1
    $lastCol = $firstCol + $totalCols - 1

    $searchLastRow = [Math]::Min($lastRow, $firstRow + $maxRows - 1)

    for ($r = $firstRow; $r -le $searchLastRow; $r++) {
        for ($c = $firstCol; $c -le $lastCol; $c++) {
            $v = $ws.Cells($r, $c).Value2
            if ($v -eq $text) {
                return $ws.Cells($r, $c)
            }
        }
    }
    return $null
}

# 指定した行範囲(全列)から、指定テキストに一致するセルの列番号を探す
# (項番ヘッダーの近くだけを見ることで、シート上部の文書メタ情報にある
#  同名セル、例えば文書バージョンの「バージョン」を誤って拾わないようにする)
function Find-ColumnInRowRange {
    param($ws, [string]$text, [int]$rowFrom, [int]$rowTo, [int]$colFrom, [int]$colTo)

    for ($r = $rowFrom; $r -le $rowTo; $r++) {
        for ($c = $colFrom; $c -le $colTo; $c++) {
            $v = $ws.Cells($r, $c).Value2
            if ($v -eq $text) {
                return $c
            }
        }
    }
    return $null
}

# 実施記録が1件も取れなかったファイル用の、ファイル単位の情報だけの空行
function New-BlankRecord {
    param([string]$topFolder, [string]$id, [string]$label, [string]$fileName, [string]$filePath)

    return [PSCustomObject]@{
        担当領域     = $topFolder
        ID           = $id
        名称         = $label
        ファイル名   = $fileName
        ファイルパス = $filePath
        シート名     = ""
        項番         = ""
        バージョン   = ""
        実施日       = ""
        実施者       = ""
        結果         = ""
    }
}

$records = @()
$processedFileCount = 0
$skipCount = 0
$errorCount = 0
$skippedFiles = @()
$errorFiles = @()

foreach ($file in $files) {

    # ファイル名が「標準化ルール適用チェックリスト(...)」または
    # 「標準化ルール適用チェックリスト_...」(括弧を使わないファイルもある)形式で
    # なければ対象外
    if ($file.BaseName -match '標準化ルール適用チェックリスト\s*[（(]\s*(.+?)\s*[）)]') {
        $inner = $matches[1]
    } elseif ($file.BaseName -match '標準化ルール適用チェックリスト_(.+)$') {
        $inner = $matches[1]
    } else {
        continue
    }
    if ($inner -match '^([A-Za-z]{2}(?:_[0-9]+)+)_(.+)$') {
        $id = $matches[1]
        $label = $matches[2]
    } else {
        $id = $inner
        $label = ""
    }

    # ID の先頭(最初の "_" より前)の分類により読み込むシートを絞り込む
    # (IO/DL→画面のみ、PT→帳票のみ、それ以外→両方)。この分類値自体は出力列には含めない。
    $idPrefix = ($id -split '_')[0]
    switch ($idPrefix) {
        "IO"    { $sheetsToProcess = @($SheetNameScreen) }
        "DL"    { $sheetsToProcess = @($SheetNameScreen) }
        "PT"    { $sheetsToProcess = @($SheetNameReport) }
        default { $sheetsToProcess = $TargetSheetNames }
    }

    $relativePath = $file.DirectoryName.Substring($FolderPath.Length).TrimStart('\')
    $topFolder = ($relativePath -split '\\')[0]
    $relativeFilePath = $file.FullName.Substring($FolderPath.Length).TrimStart('\')

    Write-Host "処理中: $($file.FullName)"

    # このファイルから1件も実施記録が取れなかった場合、担当領域/ID/名称/ファイル名だけの
    # 空行を後で追加する(0バイト/対象シート無し/ヘッダー無し/エラー、どの経路でも0のまま)
    $fileRecordCount = 0

    # ファイルサイズが0の場合、OneDrive/SharePointの「オンラインのみ」プレースホルダー
    # である可能性が高く、COM経由では正しく開けないため事前にスキップする
    if ($file.Length -eq 0) {
        Write-Host "  -> ファイルサイズが 0 バイトです。OneDrive/SharePoint の同期状態が" -ForegroundColor Red
        Write-Host "     「オンラインのみ」になっている可能性があります。エクスプローラーで" -ForegroundColor Red
        Write-Host "     このファイルを右クリック → 「このデバイス上で常に保持する」を選択し、" -ForegroundColor Red
        Write-Host "     ダウンロード完了後に再実行してください。スキップします。" -ForegroundColor Red
        $skipCount++
        $skippedFiles += $file.Name
        $records += New-BlankRecord -topFolder $topFolder -id $id -label $label -fileName $file.Name -filePath $relativeFilePath
        continue
    }

    $excel = $null
    $wb = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false

        $wb = $excel.Workbooks.Open($file.FullName, [Type]::Missing, $true)  # ReadOnly=$true

        if ($null -eq $wb) {
            throw "ワークブックを開けませんでした(Workbooks.Open が null を返しました)。ファイルが破損しているか、他のプロセスでロックされている可能性があります。"
        }

        foreach ($sheetName in $sheetsToProcess) {

            $ws = $null
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $sheetName) { $ws = $s; break }
            }
            if ($null -eq $ws) { continue }

            $headerCell = Find-HeaderCell -ws $ws -text "項番" -maxRows $HeaderSearchMaxRows
            if ($null -eq $headerCell) {
                Write-Host "  [$sheetName] 「項番」ヘッダーが見つからず、スキップ" -ForegroundColor Yellow
                continue
            }

            $headerMerge = $headerCell.MergeArea
            $headerRow = $headerMerge.Row
            $headerEndRow = $headerRow + $headerMerge.Rows.Count - 1
            $itemColStart = $headerMerge.Column
            $itemColEnd = $headerMerge.Column + $headerMerge.Columns.Count - 1

            # 項番ヘッダーの近く(headerRow ～ headerRow+RecordHeaderSearchRows)から
            # バージョン/実施日/実施者/結果 の列を探す(シート全体は検索しない)
            $usedRange = $ws.UsedRange
            $searchColFrom = [int]$usedRange.Column
            $searchColTo = $searchColFrom + [int]$usedRange.Columns.Count - 1
            $searchRowTo = $headerRow + $RecordHeaderSearchRows

            $colVersion = Find-ColumnInRowRange -ws $ws -text "バージョン" -rowFrom $headerRow -rowTo $searchRowTo -colFrom $searchColFrom -colTo $searchColTo
            $colDate    = Find-ColumnInRowRange -ws $ws -text "実施日"     -rowFrom $headerRow -rowTo $searchRowTo -colFrom $searchColFrom -colTo $searchColTo
            $colActor   = Find-ColumnInRowRange -ws $ws -text "実施者"     -rowFrom $headerRow -rowTo $searchRowTo -colFrom $searchColFrom -colTo $searchColTo
            $colResult  = Find-ColumnInRowRange -ws $ws -text "結果"       -rowFrom $headerRow -rowTo $searchRowTo -colFrom $searchColFrom -colTo $searchColTo

            if ($null -eq $colVersion -or $null -eq $colDate -or $null -eq $colActor -or $null -eq $colResult) {
                Write-Host "  [$sheetName] バージョン/実施日/実施者/結果 のヘッダーが揃わず、スキップ" -ForegroundColor Yellow
                continue
            }

            # 項番列における最終データ行を取得(Split-MergedCells.ps1 と同じロジック)
            $totalSheetRows = [int]$ws.Rows.Count
            $bottomCell = $ws.Cells($totalSheetRows, $itemColStart)
            $lastCellInCol = $bottomCell.End($xlUp)
            $lastRow = [int]$lastCellInCol.Row
            if ($lastRow -le $headerEndRow) {
                Write-Host "  [$sheetName] データ行が無いためスキップ" -ForegroundColor Yellow
                continue
            }

            for ($r = $headerEndRow + 1; $r -le $lastRow; $r++) {
                # NumberFormat次第で "01"→1、"0.20"→0.2 のように表示が変わってしまうため、
                # Value2 ではなく Text(セルに実際表示されている文字列)を使う
                $itemCell = $ws.Cells($r, $itemColStart)
                if ($itemCell.MergeCells -eq $true) {
                    $itemMerge = $itemCell.MergeArea
                    $itemNo = $ws.Cells([int]$itemMerge.Row, [int]$itemMerge.Column).Text
                } else {
                    $itemNo = $itemCell.Text
                }

                $verVal    = $ws.Cells($r, $colVersion).Text
                $dateVal   = $ws.Cells($r, $colDate).Text
                $actorVal  = $ws.Cells($r, $colActor).Text
                $resultVal = $ws.Cells($r, $colResult).Text

                $allBlank = [string]::IsNullOrEmpty($verVal) -and [string]::IsNullOrEmpty($dateVal) -and
                            [string]::IsNullOrEmpty($actorVal) -and [string]::IsNullOrEmpty($resultVal)
                if ($allBlank) { continue }

                $records += [PSCustomObject]@{
                    担当領域     = $topFolder
                    ID           = $id
                    名称         = $label
                    ファイル名   = $file.Name
                    ファイルパス = $relativeFilePath
                    シート名     = $sheetName
                    項番         = $itemNo
                    バージョン   = $verVal
                    実施日       = $dateVal
                    実施者       = $actorVal
                    結果         = $resultVal
                }
                $fileRecordCount++
            }
        }

        Write-Host "  -> $fileRecordCount 件の実施記録を取得" -ForegroundColor Green
        $processedFileCount++

        $wb.Close($false)
        $wb = $null
        $excel.Quit()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
        $excel = $null
    }
    catch {
        Write-Host "  -> エラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "     発生行: $($_.InvocationInfo.ScriptLineNumber) / 例外種別: $($_.Exception.GetType().FullName)" -ForegroundColor DarkRed
        $errorCount++
        $errorFiles += $file.Name
    }
    finally {
        if ($null -ne $wb) {
            try { $wb.Close($false) } catch {}
        }
        if ($null -ne $excel) {
            try { $excel.Quit() } catch {}
            try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {}
        }
    }

    # 対象シートが無い/ヘッダーが見つからない/エラーなどで1件も記録が取れなかった場合、
    # 担当領域/ID/名称/ファイル名だけの空行を追加する(内容が取れた場合はここでは何もしない)
    if ($fileRecordCount -eq 0) {
        $records += New-BlankRecord -topFolder $topFolder -id $id -label $label -fileName $file.Name -filePath $relativeFilePath
    }
}

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Write-Host "----------------------------------------"
Write-Host "処理ファイル数: $processedFileCount / スキップ: $skipCount / エラー: $errorCount"
if ($skippedFiles.Count -gt 0) {
    Write-Host "スキップしたファイル:" -ForegroundColor Yellow
    $skippedFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($errorFiles.Count -gt 0) {
    Write-Host "エラーになったファイル:" -ForegroundColor Red
    $errorFiles | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($records.Count -eq 0) {
    Write-Host "実施記録が1件も取得できませんでした。出力ファイルは作成しません。"
    exit
}

Write-Host "合計 $($records.Count) 件の実施記録を取得しました。出力ファイルを作成します..."

$sorted = $records | Sort-Object 担当領域, ID, ファイル名, 項番
$xlsxPath = Join-Path $FolderPath $OutFileName

$excel = $null
$workbook = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $workbook = $excel.Workbooks.Add()
    $sheet = $workbook.Worksheets.Item(1)

    $headers = @("担当領域", "ID", "名称", "ファイル名", "ファイルパス", "シート名", "項番", "バージョン", "実施日", "実施者", "結果")
    for ($c = 0; $c -lt $headers.Count; $c++) {
        $sheet.Cells.Item(1, $c + 1) = $headers[$c]
        $sheet.Cells.Item(1, $c + 1).Font.Bold = $true
    }

    # データ範囲をあらかじめ文字列書式にしておく。そうしないと "01"→1、"0.20"→0.2、
    # "2026/6/2"→シリアル値 のように Excel が値を勝手に数値/日付として解釈してしまう。
    if ($sorted.Count -gt 0) {
        $dataRange = $sheet.Range($sheet.Cells(2, 1), $sheet.Cells($sorted.Count + 1, $headers.Count))
        $dataRange.NumberFormat = "@"
    }

    $row = 2
    foreach ($item in $sorted) {
        $sheet.Cells.Item($row, 1) = $item.担当領域
        $sheet.Cells.Item($row, 2) = $item.ID
        $sheet.Cells.Item($row, 3) = $item.名称
        $sheet.Cells.Item($row, 4) = $item.ファイル名
        $sheet.Cells.Item($row, 5) = $item.ファイルパス
        $sheet.Cells.Item($row, 6) = $item.シート名
        $sheet.Cells.Item($row, 7) = $item.項番
        $sheet.Cells.Item($row, 8) = $item.バージョン
        $sheet.Cells.Item($row, 9) = $item.実施日
        $sheet.Cells.Item($row, 10) = $item.実施者
        $sheet.Cells.Item($row, 11) = $item.結果
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

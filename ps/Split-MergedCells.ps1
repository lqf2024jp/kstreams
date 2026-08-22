<#
.SYNOPSIS
    スクリプトが置かれているフォルダ以下(サブフォルダ含む)にある
    すべての .xlsx ファイルに対して、
    シート名が「画面(基本設計)」または「帳票(基本設計)」のシートだけを対象に、
    「項番」ヘッダーの下にある縦横結合セルを一括で解除し、
    元の値を各セルに埋め込むスクリプト。

.DESCRIPTION
    - フォルダ内(既定ではスクリプト自身の場所)の xlsx を再帰的に検索
    - 各ファイルのシートのうち、名前が「画面(基本設計)」「帳票(基本設計)」の
      2つだけを処理対象とする(それ以外のシート名は無条件でスキップ)
    - 対象シート内で、セル値が "項番" のヘッダーセルを、UsedRange内を
      手動でループして探す(Find メソッドは COM 経由だと型キャストエラーが
      出やすいため使用しない)
    - そのヘッダーが属する結合範囲の「列幅」を基準に、
      ヘッダー行より下にある同じ列幅の結合セルをすべて解除
    - 解除後、結合されていた範囲の全セルに元の値をコピー
    - 対象シートに「項番」ヘッダーが無い場合はそのシートのみスキップ(ファイルは処理継続)

.PARAMETER FolderPath
    処理対象のルートフォルダ。既定値はこのスクリプト自身が置かれているフォルダ($PSScriptRoot)。

.PARAMETER Recurse
    サブフォルダを含めるかどうか。既定で $true (サブフォルダも処理する)。
    サブフォルダを含めたくない場合は -Recurse:$false を指定。

.PARAMETER Overwrite
    指定すると元ファイルを直接上書き保存する。
    指定しない場合は "元ファイル名_split.xlsx" として別名保存し、
    元ファイルは変更しない(既定・安全側)。

.PARAMETER HeaderSearchMaxRows
    「項番」ヘッダーを探す際に走査する最大行数(表の先頭からの範囲)。
    既定 30 行。表のヘッダーがそれより下にある特殊なファイルがあれば増やす。

.EXAMPLE
    # 既定:スクリプト自身のフォルダ以下を再帰的に処理し、別名で保存
    .\Split-MergedCells.ps1

.EXAMPLE
    # 元ファイルを直接上書き
    .\Split-MergedCells.ps1 -Overwrite
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [bool]$Recurse = $true,
    [switch]$Overwrite,
    [string]$OutSuffix = "_split",
    [int]$HeaderSearchMaxRows = 30
)

# 処理対象とするシート名(この2つ以外のシートは無条件でスキップ)
$TargetSheetNames = @("画面(基本設計)", "帳票(基本設計)")

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

Write-Host "対象ファイル数: $($files.Count)"
Write-Host "----------------------------------------"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.ScreenUpdating = $false

$successCount = 0
$skipCount = 0
$errorCount = 0

# 「項番」ヘッダーセルを、UsedRange内を手動ループして探す
# (COM経由のFindメソッドは型キャストエラーが出やすいため使わない)
function Find-HeaderCell {
    param($ws, [int]$maxRows)

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
            $targetCell = $ws.Cells($r, $c)
            $v = $targetCell.Value2
            if ($v -eq "項番") {
                return $targetCell
            }
        }
    }
    return $null
}

foreach ($file in $files) {
    Write-Host "処理中: $($file.FullName)"

    # ファイルサイズが0の場合、OneDrive/SharePointの「オンラインのみ」プレースホルダー
    # である可能性が高く、COM経由では正しく開けないため事前にスキップする
    if ($file.Length -eq 0) {
        Write-Host "  -> ファイルサイズが 0 バイトです。OneDrive/SharePoint の同期状態が" -ForegroundColor Red
        Write-Host "     「オンラインのみ」になっている可能性があります。エクスプローラーで" -ForegroundColor Red
        Write-Host "     このファイルを右クリック → 「このデバイス上で常に保持する」を選択し、" -ForegroundColor Red
        Write-Host "     ダウンロード完了後に再実行してください。スキップします。" -ForegroundColor Red
        $skipCount++
        continue
    }

    $wb = $null
    try {
        $wb = $excel.Workbooks.Open($file.FullName, [Type]::Missing, $false)  # ReadOnly=$false

        if ($null -eq $wb) {
            throw "ワークブックを開けませんでした(Workbooks.Open が null を返しました)。ファイルが破損しているか、他のプロセスでロックされている可能性があります。"
        }
        $changedAny = $false
        $anyTargetSheetFound = $false

        foreach ($sheetName in $TargetSheetNames) {

            $ws = $null
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $sheetName) { $ws = $s; break }
            }
            if ($null -eq $ws) {
                # このファイルには該当シートが存在しない -> スキップ
                continue
            }
            $anyTargetSheetFound = $true

            # --- 「項番」ヘッダーセルを探す(手動ループ) ---
            $headerCell = Find-HeaderCell -ws $ws -maxRows $HeaderSearchMaxRows

            if ($null -eq $headerCell) {
                Write-Host "  [$sheetName] 「項番」ヘッダーが見つからず、スキップ" -ForegroundColor Yellow
                continue
            }

            $headerMerge = $headerCell.MergeArea
            $headerEndRow = $headerMerge.Row + $headerMerge.Rows.Count - 1
            $startCol = $headerMerge.Column
            $endCol = $headerMerge.Column + $headerMerge.Columns.Count - 1

            # そのヘッダー列における最終データ行を取得
            $totalSheetRows = [int]$ws.Rows.Count
            $bottomCell = $ws.Cells($totalSheetRows, $startCol)
            $lastCellInCol = $bottomCell.End($xlUp)
            $lastRow = [int]$lastCellInCol.Row
            if ($lastRow -le $headerEndRow) {
                Write-Host "  [$sheetName] データ行が無いためスキップ" -ForegroundColor Yellow
                continue
            }

            $r = $headerEndRow + 1
            $sheetChanged = $false
            while ($r -le $lastRow) {
                $cell = $ws.Cells($r, $startCol)
                if ($cell.MergeCells -eq $true) {
                    $mergeArea = $cell.MergeArea
                    $mStartCol = $mergeArea.Column
                    $mEndCol = $mergeArea.Column + $mergeArea.Columns.Count - 1

                    # ヘッダーと同じ列幅の結合だけを対象にする(無関係な結合を誤って壊さないため)
                    if ($mStartCol -eq $startCol -and $mEndCol -eq $endCol) {
                        # 取得と代入を1行にチェーンさせない(PowerShell+Excel COMの既知の不具合を回避)
                        # $mergeArea.Cells(1,1) はまれに NullReferenceException / InvalidCastException を
                        # 起こすことがあるため、既にワークシート全体で使っている $ws.Cells(row, col) の
                        # 呼び出し方に統一して同じ結果(結合範囲の左上セル)を取得する
                        $topLeftCell = $ws.Cells([int]$mergeArea.Row, [int]$mergeArea.Column)
                        $val = $topLeftCell.Value2
                        if ($null -eq $val) { $val = "" }
                        # [DEBUG] 210行目の InvalidCastException 調査用。原因判明後に削除。
                        Write-Host "    [DEBUG] val='$val' / type=$($val.GetType().FullName)" -ForegroundColor DarkGray

                        $mRowCountRaw = $mergeArea.Rows.Count
                        $mRowCount = [int]$mRowCountRaw

                        $mergeArea.UnMerge()

                        for ($i = 0; $i -lt $mRowCount; $i++) {
                            for ($c = $startCol; $c -le $endCol; $c++) {
                                $targetRow = [int]($r + $i)
                                $targetCol = [int]$c
                                $targetCell = $ws.Cells($targetRow, $targetCol)
                                $targetCell.Value2 = $val
                            }
                        }
                        $changedAny = $true
                        $sheetChanged = $true
                        $r = [int]($r + $mRowCount)
                        continue
                    }
                }
                $r++
            }

            if ($sheetChanged) {
                Write-Host "  [$sheetName] 結合セルを分割しました" -ForegroundColor Green
            }
        }

        if (-not $anyTargetSheetFound) {
            Write-Host "  -> 対象シート(画面(基本設計)/帳票(基本設計))が無いためスキップ" -ForegroundColor Yellow
            $skipCount++
            $wb.Close($false)
            $wb = $null
            continue
        }

        if ($changedAny) {
            if ($Overwrite) {
                $wb.Save()
                Write-Host "  -> 上書き保存しました" -ForegroundColor Green
            }
            else {
                $newName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + $OutSuffix + $file.Extension
                $newPath = Join-Path $file.DirectoryName $newName
                $wb.SaveAs($newPath)
                Write-Host "  -> 別名保存しました: $newName" -ForegroundColor Green
            }
            $successCount++
        }
        else {
            Write-Host "  -> 対象シートはあったが、変更対象の結合セルなし" -ForegroundColor Yellow
            $skipCount++
        }

        $wb.Close($false)
        $wb = $null
    }
    catch {
        Write-Host "  -> エラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "     発生行: $($_.InvocationInfo.ScriptLineNumber) / 例外種別: $($_.Exception.GetType().FullName)" -ForegroundColor DarkRed
        if ($_.Exception.InnerException) {
            Write-Host "     内部例外: $($_.Exception.InnerException.Message)" -ForegroundColor DarkRed
        }
        $errorCount++
        if ($null -ne $wb) {
            try { $wb.Close($false) } catch {}
        }
    }
}

$excel.Quit()
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Write-Host "----------------------------------------"
Write-Host "完了: 成功 $successCount 件 / スキップ $skipCount 件 / エラー $errorCount 件"

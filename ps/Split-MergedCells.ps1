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
    [int]$HeaderSearchMaxRows = 30,
    [string]$LogPath = ""
)

# 処理対象とするシート名(この2つ以外のシートは無条件でスキップ)
$TargetSheetNames = @("画面(基本設計)", "帳票(基本設計)")

# xlUp 定数 (Excel VBA の xlUp = -4162)
$xlUp = -4162

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

# --- ログをファイルにも残す(客先での不具合切り分け用) ---
if ([string]::IsNullOrEmpty($LogPath)) {
    $logDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $LogPath = Join-Path $logDir ("Split-MergedCells_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
try {
    Start-Transcript -Path $LogPath -Append | Out-Null
    Write-Host "ログファイル: $LogPath"
}
catch {
    Write-Host "警告: ログファイルの作成に失敗しました($LogPath): $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- 実行環境の診断情報(「ローカルでは動くが客先で動かない」原因切り分け用) ---
Write-Host "===== 実行環境情報 ====="
Write-Host "実行日時: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "PowerShellバージョン: $($PSVersionTable.PSVersion)"
Write-Host "PowerShellエディション: $($PSVersionTable.PSEdition)"
Write-Host "プロセスビット数: $(if ([Environment]::Is64BitProcess) { '64bit' } else { '32bit' })"
Write-Host "OS: $([Environment]::OSVersion.VersionString) / OSビット数: $(if ([Environment]::Is64BitOperatingSystem) { '64bit' } else { '32bit' })"
Write-Host "実行ユーザー: $([Environment]::UserDomainName)\$([Environment]::UserName)"
Write-Host "カルチャ: $([System.Globalization.CultureInfo]::CurrentCulture.Name) / UIカルチャ: $([System.Globalization.CultureInfo]::CurrentUICulture.Name)"
Write-Host "スクリプトパス: $PSCommandPath"
Write-Host "========================"

Write-Host "対象フォルダ: $FolderPath"
Write-Host "サブフォルダを含む: $Recurse"
Write-Host "対象シート: $($TargetSheetNames -join ', ')"

$getChildParams = @{
    Path   = $FolderPath
    Filter = "*.xlsx"
    File   = $true
}
if ($Recurse) { $getChildParams["Recurse"] = $true }

if (-not (Test-Path -LiteralPath $FolderPath -PathType Container)) {
    Write-Host "エラー: 対象フォルダが存在しません: $FolderPath" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

$files = Get-ChildItem @getChildParams | Where-Object { $_.Name -notlike "~$*" }

if ($files.Count -eq 0) {
    Write-Host "処理対象の .xlsx ファイルが見つかりませんでした。"
    try { Stop-Transcript | Out-Null } catch {}
    exit
}

Write-Host "対象ファイル数: $($files.Count)"
$files | ForEach-Object { Write-Host "  - $($_.FullName) ($($_.Length) bytes)" }
Write-Host "----------------------------------------"

try {
    Write-Host "Excel COMオブジェクトを起動しています..."
    $excel = New-Object -ComObject Excel.Application
    Write-Host "Excel COMオブジェクトの起動完了"
}
catch {
    Write-Host "エラー: Excel COMオブジェクトの作成に失敗しました。" -ForegroundColor Red
    Write-Host "  → このマシンに Microsoft Excel がインストールされていないか、" -ForegroundColor Red
    Write-Host "    COMコンポーネントが正しく登録されていない可能性があります。" -ForegroundColor Red
    Write-Host "  例外メッセージ: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  例外種別: $($_.Exception.GetType().FullName)" -ForegroundColor DarkRed
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}

try {
    Write-Host "Excelバージョン: $($excel.Version) / Build: $($excel.Build)"
}
catch {
    Write-Host "警告: Excelバージョン情報の取得に失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
}

$excel.Visible = $false
$excel.DisplayAlerts = $false
$excel.ScreenUpdating = $false
# 「外部リンクを更新しますか?」等の確認ダイアログは DisplayAlerts=$false では
# 抑制できず、Visible=$false のため見えないまま Workbooks.Open が無反応になる
# (=スクリプトが固まったように見える)原因になるため、明示的に無効化しておく
$excel.AskToUpdateLinks = $false

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

    # エラー発生時にどこで止まったか分かるように、処理中のシート/行/列を都度記録しておく
    $currentSheetName = $null
    $currentRow = $null
    $currentCol = $null

    $wb = $null
    try {
        # UpdateLinks=0(外部リンクは更新しない/確認しない), ReadOnly=$false,
        # IgnoreReadOnlyRecommended=$true(読み取り推奨の確認も出さない)
        # これらを明示しないと、Visible=$false で見えないダイアログが裏で
        # 表示されて Open が無反応(=固まったように見える)になることがある
        Write-Host "  Workbooks.Open 呼び出し開始..."
        $wb = $excel.Workbooks.Open($file.FullName, 0, $false, [Type]::Missing, [Type]::Missing, [Type]::Missing, $true)
        Write-Host "  Workbooks.Open 呼び出し完了"

        if ($null -eq $wb) {
            throw "ワークブックを開けませんでした(Workbooks.Open が null を返しました)。ファイルが破損しているか、他のプロセスでロックされている可能性があります。"
        }

        $allSheetNames = @($wb.Worksheets | ForEach-Object { $_.Name })
        Write-Host "  ブック内の全シート名: $($allSheetNames -join ' / ')"

        $changedAny = $false
        $anyTargetSheetFound = $false

        foreach ($sheetName in $TargetSheetNames) {
            $currentSheetName = $sheetName

            $ws = $null
            foreach ($s in $wb.Worksheets) {
                if ($s.Name -eq $sheetName) { $ws = $s; break }
            }
            if ($null -eq $ws) {
                # このファイルには該当シートが存在しない -> スキップ
                # (名前が完全一致しないだけの可能性もあるため、実際のシート名は上の一覧で確認できる)
                continue
            }
            $anyTargetSheetFound = $true

            # --- 「項番」ヘッダーセルを探す(手動ループ) ---
            $headerCell = Find-HeaderCell -ws $ws -maxRows $HeaderSearchMaxRows

            if ($null -eq $headerCell) {
                Write-Host "  [$sheetName] 「項番」ヘッダーが見つからず、スキップ(先頭 $HeaderSearchMaxRows 行以内に見つかりませんでした)" -ForegroundColor Yellow
                continue
            }
            Write-Host "  [$sheetName] 「項番」ヘッダー発見: 行=$($headerCell.Row) 列=$($headerCell.Column)"

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
                $currentRow = $r
                $currentCol = $startCol
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
                        $valTypeName = $val.GetType().FullName

                        $mRowCountRaw = $mergeArea.Rows.Count
                        $mRowCount = [int]$mRowCountRaw

                        Write-Host "    結合解除開始: 行=$r〜$($r + $mRowCount - 1) 列=$startCol-$endCol (値の型=$valTypeName)"
                        $mergeArea.UnMerge()
                        Write-Host "    結合解除完了、値の書き込み開始"

                        for ($i = 0; $i -lt $mRowCount; $i++) {
                            for ($c = $startCol; $c -le $endCol; $c++) {
                                $targetRow = [int]($r + $i)
                                $targetCol = [int]$c
                                $targetCell = $ws.Cells($targetRow, $targetCol)
                                try {
                                    $targetCell.Value2 = $val
                                }
                                catch {
                                    # Value2への直接代入がキャスト例外になる環境がある(値の.NET型と
                                    # Excel COMの版で相性が悪いケース)。原因特定のため型情報を出力した上で、
                                    # 数値なら double、それ以外は string にキャストして再試行する
                                    Write-Host "     [診断] Value2直接代入が失敗: 行=$targetRow 列=$targetCol 値の型=$valTypeName 値='$val' エラー=$($_.Exception.Message)" -ForegroundColor Magenta
                                    $retried = $false
                                    if ($val -is [double] -or $val -is [int] -or $val -is [int64] -or $val -is [single] -or $val -is [decimal]) {
                                        try {
                                            $targetCell.Value2 = [double]$val
                                            $retried = $true
                                            Write-Host "     [診断] [double]キャストで再試行→成功" -ForegroundColor Magenta
                                        }
                                        catch {}
                                    }
                                    if (-not $retried) {
                                        $targetCell.Value2 = [string]$val
                                        Write-Host "     [診断] [string]キャストで再試行→成功(セルは文字列型になります)" -ForegroundColor Magenta
                                    }
                                }
                            }
                        }
                        Write-Host "    値の書き込み完了"
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
            Write-Host "  Workbook.Close 呼び出し開始(保存なし)..."
            $wb.Close($false)
            Write-Host "  Workbook.Close 呼び出し完了"
            $wb = $null
            continue
        }

        if ($changedAny) {
            if ($Overwrite) {
                Write-Host "  Workbook.Save 呼び出し開始(上書き保存)..."
                $wb.Save()
                Write-Host "  Workbook.Save 呼び出し完了"
                Write-Host "  -> 上書き保存しました" -ForegroundColor Green
            }
            else {
                $newName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + $OutSuffix + $file.Extension
                $newPath = Join-Path $file.DirectoryName $newName
                Write-Host "  Workbook.SaveAs 呼び出し開始: $newName ..."
                $wb.SaveAs($newPath)
                Write-Host "  Workbook.SaveAs 呼び出し完了"
                Write-Host "  -> 別名保存しました: $newName" -ForegroundColor Green
            }
            $successCount++
        }
        else {
            Write-Host "  -> 対象シートはあったが、変更対象の結合セルなし" -ForegroundColor Yellow
            $skipCount++
        }

        Write-Host "  Workbook.Close 呼び出し開始..."
        $wb.Close($false)
        Write-Host "  Workbook.Close 呼び出し完了"
        $wb = $null
    }
    catch {
        Write-Host "  -> エラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "     発生行: $($_.InvocationInfo.ScriptLineNumber) / 例外種別: $($_.Exception.GetType().FullName)" -ForegroundColor DarkRed
        Write-Host "     処理中だったシート: $currentSheetName / 行: $currentRow / 列: $currentCol" -ForegroundColor DarkRed
        Write-Host "     ファイル: $($file.FullName)" -ForegroundColor DarkRed
        Write-Host "     HResult: $($_.Exception.HResult) / スタックトレース:`n$($_.ScriptStackTrace)" -ForegroundColor DarkRed
        if ($_.Exception.InnerException) {
            Write-Host "     内部例外: $($_.Exception.InnerException.Message)" -ForegroundColor DarkRed
        }
        $errorCount++
        if ($null -ne $wb) {
            try { $wb.Close($false) } catch {}
        }
    }
}

Write-Host "Excel.Quit 呼び出し開始..."
try {
    $excel.Quit()
    Write-Host "Excel.Quit 呼び出し完了"
}
catch {
    Write-Host "警告: Excel終了処理でエラー: $($_.Exception.Message)" -ForegroundColor Yellow
}
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

Write-Host "----------------------------------------"
Write-Host "完了: 成功 $successCount 件 / スキップ $skipCount 件 / エラー $errorCount 件"
Write-Host "ログファイル: $LogPath"

try { Stop-Transcript | Out-Null } catch {}

<#
.SYNOPSIS
    実施記録一覧_merge_after.xlsx(長い形式: 1行 = 1IDの1項番の、既にバージョン間で
    マージ済みの記録)を、1行 = 1ID(機能)、列 = 項番 の一覧表に変換し、IDの
    プレフィックスに応じて 画面用_out.xlsx(IO_/DL_) と 帳票用_out.xlsx(RP_) の
    2ファイルに振り分けて出力するスクリプト。

.DESCRIPTION
    - 実施記録一覧_merge_after.xlsx は merge_versions_by_id.ps1 が既に
      「同じIDの複数バージョンの中から項番ごとに採用すべき結果を1つに決める」
      処理を済ませた長い形式のデータなので、このスクリプトでは
      ファイル内の重複解消(NG優先マージ)は行わない。ID単位で項番をそのまま
      列に展開するだけでよい。
    - IDのプレフィックスで出力先を振り分ける: IO_/DL_(画面、基本設計) は
      画面用_out.xlsx へ、RP_(帳票、基本設計) は 帳票用_out.xlsx へ。
      画面と帳票では要求されるチェックリスト項番が異なるため、それぞれの
      テンプレートファイルの1行目に既に入っている項番セットをそのまま使う。
      どちらのプレフィックスにも一致しないIDはスキップし、console に警告を出す。
    - 各テンプレートファイルの1~3行目(見出し・項番の並び・列幅など)は一切
      変更しない。1行目E列以降に既に入っている項番の並び順・重複もそのまま使う
    - 各テンプレートファイル自体を開いて4行目以降だけを書き換える
      (新しいファイルは作らない)
    - 1つのIDの中で項番によって採用元ファイルが異なる場合があるため、
      ファイル名 列には実際に採用された結果を持つ全ファイルを、
      バージョンの新しい順に列挙する。項番が1件も無いID(全バージョンで
      未実施)は、merge_versions_by_id.ps1 が残した空行から
      そのままファイル名だけ引き継ぐ。
    - 3行目の「最新バージョンファイル名」列(1行目の項番見出しが終わった
      直後の列。テンプレートによって位置が異なるため、UsedRange の最終列を
      決め打ちにせず、3行目を実際に検索して見つける)には、そのIDに関わった
      ファイルの中で最もバージョンが新しいものの元のファイル名(バージョン
      番号込み)を書き込む。ファイル名 列(項番ごとの採用元を素の名前で列挙)
      とは別に、そのIDを直近どのバージョンが触ったかを一目で見るための列。

.PARAMETER FolderPath
    処理対象のフォルダ。既定値はこのスクリプト自身が置かれているフォルダ($PSScriptRoot)。

.PARAMETER InFileName
    入力ファイル名。既定値は実行日の日付付きで "yyyyMMdd_実施記録一覧_merge_after.xlsx"。

.PARAMETER ScreenOutFileName
    画面(IO_/DL_)用の出力先ファイル名。既定値 "画面用_out.xlsx"。このファイル自体を
    開いて4行目以降を書き換える(1~3行目の見出し・書式はそのまま)ので、事前に
    存在している必要がある。

.PARAMETER ReportOutFileName
    帳票(RP_)用の出力先ファイル名。既定値 "帳票用_out.xlsx"。ScreenOutFileName と
    同様、事前に存在している必要がある。

.EXAMPLE
    .\pivot_check_records.ps1
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [string]$InFileName = "$(Get-Date -Format 'yyyyMMdd')_実施記録一覧_merge_after.xlsx",
    [string]$ScreenOutFileName = "画面用_out.xlsx",
    [string]$ReportOutFileName = "帳票用_out.xlsx"
)

if ([string]::IsNullOrEmpty($FolderPath)) {
    $FolderPath = (Get-Location).Path
}

$inPath = Join-Path $FolderPath $InFileName
$screenOutPath = Join-Path $FolderPath $ScreenOutFileName
$reportOutPath = Join-Path $FolderPath $ReportOutFileName

if (-not (Test-Path $inPath)) {
    Write-Host "入力ファイルが見つかりません: $inPath" -ForegroundColor Red
    exit
}
if (-not (Test-Path $screenOutPath)) {
    Write-Host "出力先のテンプレートファイルが見つかりません: $screenOutPath" -ForegroundColor Red
    Write-Host "(項番の列見出しをこのファイルの1行目E列以降からコピーするため必要です)" -ForegroundColor Red
    exit
}
if (-not (Test-Path $reportOutPath)) {
    Write-Host "出力先のテンプレートファイルが見つかりません: $reportOutPath" -ForegroundColor Red
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

# 指定した行($row)を左から検索し、テキストが完全一致するセルの列番号を返す。
# UsedRange の最終列には書式だけ残った空白セルが含まれることがあり、それを
# 「最新バージョンファイル名」列の位置だと決め打ちできないため、実際にテキストを
# 探して位置を特定する。見つからなければ $null を返す。
function Find-RowTextColumn {
    param($ws, [int]$row, [string]$text, [int]$searchUpperBound)

    for ($c = 1; $c -le $searchUpperBound; $c++) {
        if ($ws.Cells($row, $c).Text -eq $text) { return $c }
    }
    return $null
}

# out.xlsx が想定どおりの形式(1行目E列="チェックリスト項番"、3行目A~D列="担当領域/ID/名称/ファイル名"、
# 3行目の「最新バージョンファイル名」列)になっているかを確認する。
# ずれている問題点のリストを返す(空なら問題なし)。
function Test-OutTemplateFormat {
    param($sheet, $colVersionCol)

    $problems = @()

    $expectedLabels = @("担当領域", "ID", "名称", "ファイル名")
    for ($c = 1; $c -le 4; $c++) {
        $actual = $sheet.Cells(3, $c).Text
        $expected = $expectedLabels[$c - 1]
        if ($actual -ne $expected) {
            $colLetter = [char](64 + $c)
            $problems += "3行目 ${colLetter}列: 期待値='$expected' / 実際の値='$actual'"
        }
    }

    $itemLabel = $sheet.Cells(1, 5).Text
    if ($itemLabel -ne "チェックリスト項番") {
        $problems += "1行目 E列: 期待値='チェックリスト項番' / 実際の値='$itemLabel'"
    }

    if ($null -eq $colVersionCol) {
        $problems += "3行目: 「最新バージョンファイル名」という見出しの列が見つかりません"
    }

    return $problems
}

# ファイル名の末尾からバージョン番号を抜き出す(merge_versions_by_id.ps1 と同じロジック)。
# ファイル名列に複数ファイルを新しい順で列挙するために使う。
function Get-FileVersionKey {
    param([string]$fileName)

    if ($fileName -match '(?:Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\.xlsx$') {
        try {
            $ver = [version]$matches[1]
        } catch {
            return $null
        }
        return [PSCustomObject]@{ Version = $ver; Suffix = $matches[2] }
    }
    return $null
}

# ファイル名の末尾からバージョン部分と拡張子を取り除いた「素の」ファイル名を返す。
# 同じIDの複数バージョンは、バージョン番号を除けば同一のファイル名になるはずなので、
# ファイル名列にはこれを1つだけ表示する(バージョン違いの同じ名前を何度も並べない)。
function Get-BaseFileName {
    param([string]$fileName)

    $base = $fileName -replace '_?(?:Ver)?\d+(?:\.\d+)+[A-Za-z]?\.xlsx$', ''
    $base = $base -replace '\.xlsx$', ''
    return $base
}

function Compare-FileVersionKey {
    param($a, $b)

    if ($null -eq $a -and $null -eq $b) { return 0 }
    if ($null -eq $a) { return -1 }
    if ($null -eq $b) { return 1 }

    $cmp = $a.Version.CompareTo($b.Version)
    if ($cmp -ne 0) { return $cmp }
    return [string]::Compare($a.Suffix, $b.Suffix, [System.StringComparison]::Ordinal)
}

# $records(担当領域/ID/名称/ファイル名/最新バージョンファイル名/項番結果 を持つ配列)を
# 1つのテンプレートファイル($outPath)の4行目以降に書き込む。テンプレートの1行目
# E列以降(最終列の「最新バージョンファイル名」を除く)にある項番見出しをそのまま使う。
# エラーはこの関数内で捕捉して報告するだけで、呼び出し元には投げない
# (画面用/帳票用の片方が失敗しても、もう片方の処理は続行できるようにするため)。
function Write-PivotOutput {
    param($excel, $records, [string]$outPath, [string]$outFileName)

    $wbOut = $null
    try {
        $wbOut = $excel.Workbooks.Open($outPath)
        $sheet = $wbOut.Worksheets.Item(1)

        $usedOut = $sheet.UsedRange
        $lastColOut = [int]$usedOut.Column + [int]$usedOut.Columns.Count - 1
        $lastRowOut = [int]$usedOut.Row + [int]$usedOut.Rows.Count - 1

        $colVersionCol = Find-RowTextColumn -ws $sheet -row 3 -text "最新バージョンファイル名" -searchUpperBound $lastColOut

        # ---- フォーマットチェック ----
        $formatProblems = Test-OutTemplateFormat -sheet $sheet -colVersionCol $colVersionCol
        if ($formatProblems.Count -eq 0) {
            Write-Host "$outFileName のフォーマットチェック: 正しいです" -ForegroundColor Green
        } else {
            Write-Host "$outFileName のフォーマットチェック: 正しくありません" -ForegroundColor Red
            foreach ($p in $formatProblems) { Write-Host "  - $p" -ForegroundColor Red }
            throw "$outFileName のフォーマットが想定と異なるため、書き込みを中止しました。"
        }

        # 1行目のF列以降(E列は「チェックリスト項番」という見出しラベル自体が入っている
        # だけで項番ではないため除外し、「最新バージョンファイル名」列も除く)を、
        # 項番の列見出しとしてそのまま読み込む(並び・重複はそのまま使う)
        $templateHeaders = @()
        for ($c = 6; $c -le $colVersionCol - 1; $c++) {
            $templateHeaders += $sheet.Cells(1, $c).Text
        }

        if ($templateHeaders.Count -eq 0) {
            throw "$outFileName の1行目のF列以降に項番の見出しが見つかりませんでした。"
        }

        # クリア/書き込み対象は A列から最新バージョンファイル名列までの全幅
        $colCount = $colVersionCol
        $dataStartRow = 4
        $dataEndRow = $dataStartRow + $records.Count - 1

        # 前回実行時の残りデータが今回より行数が多い場合に備えて、4行目から
        # 現在の最終行までをクリアしてから書き直す(書式は消さない ClearContents を使う)
        $clearLastRow = [Math]::Max($lastRowOut, $dataEndRow)
        if ($clearLastRow -ge $dataStartRow) {
            $clearRange = $sheet.Range($sheet.Cells($dataStartRow, 1), $sheet.Cells($clearLastRow, $colCount))
            $clearRange.ClearContents() | Out-Null
            # 以前のバージョンのスクリプトが4行目以降に "@"(テキスト)書式を付けていたことがあり、
            # 残ったままだと ファイル名 を複数連結した長い文字列が古いExcelで .Text が "###" に
            # なる表示不具合を起こす。このスクリプトが書く内容(担当領域/ID/名称/ファイル名/OK/NG)は
            # そもそも数値と誤認識される心配が無いので、General に戻しておく。
            # (書式変更が失敗しても致命的ではない――データ自体は Value2 では正しく入っているので、
            #  ここで処理全体を止めずに警告だけ出す)
            try {
                $clearRange.NumberFormat = "General"
            } catch {
                Write-Host "  警告: 4行目以降の書式リセットに失敗しました($($_.Exception.Message))。データは正しく書き込まれますが、長いファイル名が '###' と表示される場合があります。" -ForegroundColor Yellow
            }
        }

        # このスクリプトが4行目以降に書き込むのは 担当領域/ID/名称/ファイル名(すべて文字列)と
        # OK/NG の結果だけで、"06" のような数字だけの項番文字列は書かない(項番は1行目に
        # 既にある見出しをそのまま使うだけ)。そのため NumberFormat="@" は不要
        # ——付けると逆に、ファイル名を複数連結した長い文字列が古いExcelで .Text が
        # "###" になる表示不具合を引き起こす(merge_versions_by_id.ps1 で踏んだのと同じ問題)。

        $row = $dataStartRow
        foreach ($item in $records) {
            $sheet.Cells.Item($row, 1) = $item.担当領域
            $sheet.Cells.Item($row, 2) = $item.ID
            $sheet.Cells.Item($row, 3) = $item.名称
            $sheet.Cells.Item($row, 4) = $item.ファイル名
            $sheet.Cells.Item($row, $colVersionCol) = $item.最新バージョンファイル名

            for ($i = 0; $i -lt $templateHeaders.Count; $i++) {
                $itemNo = $templateHeaders[$i]
                if ($item.項番結果.ContainsKey($itemNo)) {
                    $sheet.Cells.Item($row, 6 + $i) = $item.項番結果[$itemNo]
                }
            }
            $row++
        }

        $wbOut.Save()
        $wbOut.Close($false)
        $wbOut = $null

        Write-Host "対象ID数: $($records.Count)" -ForegroundColor Green
        Write-Host "項番の列数: $($templateHeaders.Count)" -ForegroundColor Green
        Write-Host "出力しました($dataStartRow 行目から): $outPath" -ForegroundColor Green

        # ---- どの機能(ID)でも一度もチェックされていないチェックリスト項番を洗い出す ----
        $checkedItemNos = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($item in $records) {
            foreach ($key in $item.項番結果.Keys) {
                [void]$checkedItemNos.Add($key)
            }
        }
        $neverChecked = @($templateHeaders | Where-Object { -not $checkedItemNos.Contains($_) })

        if ($neverChecked.Count -gt 0) {
            Write-Host "どの機能でもチェックされていないチェックリスト項番 ($($neverChecked.Count)件):" -ForegroundColor Yellow
            foreach ($n in $neverChecked) { Write-Host "  - $n" -ForegroundColor Yellow }
        } else {
            Write-Host "すべてのチェックリスト項番が、いずれかの機能でチェックされています。" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "エラー($outFileName): $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  $outFileName が Excel で開かれている場合は、閉じてから再実行してください。" -ForegroundColor Red
    }
    finally {
        if ($null -ne $wbOut) { try { $wbOut.Close($false) } catch {} }
    }
}

$excel = $null
$wbIn = $null
$records = $null

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    # ---- 実施記録一覧_merge_after.xlsx を読み込む ----
    $wbIn = $excel.Workbooks.Open($inPath, [Type]::Missing, $true)  # ReadOnly
    $wsIn = $wbIn.Worksheets.Item(1)
    $usedIn = $wsIn.UsedRange
    $lastColIn = [int]$usedIn.Column + [int]$usedIn.Columns.Count - 1
    $lastRowIn = [int]$usedIn.Row + [int]$usedIn.Rows.Count - 1

    $colTopFolder = Find-HeaderColumn -ws $wsIn -text "担当領域"   -lastCol $lastColIn
    $colId        = Find-HeaderColumn -ws $wsIn -text "ID"         -lastCol $lastColIn
    $colLabel     = Find-HeaderColumn -ws $wsIn -text "名称"       -lastCol $lastColIn
    $colFileName  = Find-HeaderColumn -ws $wsIn -text "ファイル名" -lastCol $lastColIn
    $colItemNo    = Find-HeaderColumn -ws $wsIn -text "項番"       -lastCol $lastColIn
    $colResult    = Find-HeaderColumn -ws $wsIn -text "結果"       -lastCol $lastColIn

    if ($null -eq $colTopFolder -or $null -eq $colId -or $null -eq $colLabel -or
        $null -eq $colFileName -or $null -eq $colItemNo -or $null -eq $colResult) {
        throw "$InFileName の1行目から必要な列(担当領域/ID/名称/ファイル名/項番/結果)が見つかりませんでした。"
    }

    # ID単位で集計する。merge_after は既にバージョン間のマージが済んでいるので、
    # ここでは項番ごとの結果とファイル名をそのまま受け取るだけでよい。
    $ids = [ordered]@{}

    for ($r = 2; $r -le $lastRowIn; $r++) {
        $id = $wsIn.Cells($r, $colId).Text
        if ([string]::IsNullOrEmpty($id)) { continue }

        if (-not $ids.Contains($id)) {
            $ids[$id] = [PSCustomObject]@{
                担当領域         = $wsIn.Cells($r, $colTopFolder).Text
                名称             = $wsIn.Cells($r, $colLabel).Text
                項番結果         = @{}          # 項番 -> 結果
                ContributingFiles = [ordered]@{} # ファイル名 -> $true (登場順の重複排除用)
            }
        }
        $entry = $ids[$id]

        $fileName = $wsIn.Cells($r, $colFileName).Text
        if (-not [string]::IsNullOrEmpty($fileName) -and -not $entry.ContributingFiles.Contains($fileName)) {
            $entry.ContributingFiles[$fileName] = $true
        }

        $itemNo = $wsIn.Cells($r, $colItemNo).Text
        $result = $wsIn.Cells($r, $colResult).Text
        if ([string]::IsNullOrEmpty($itemNo)) { continue }
        if ($result -ne "OK" -and $result -ne "NG") { continue }

        $entry.項番結果[$itemNo] = $result
    }

    $wbIn.Close($false)
    $wbIn = $null

    if ($ids.Count -eq 0) {
        Write-Host "$InFileName に有効なレコードが見つかりませんでした。" -ForegroundColor Yellow
        exit
    }

    $records = @()
    foreach ($id in $ids.Keys) {
        $entry = $ids[$id]

        # 実際に採用された全ファイルを新しい順に並べる
        $fileList = @($entry.ContributingFiles.Keys)
        for ($i = 0; $i -lt $fileList.Count; $i++) {
            for ($j = $i + 1; $j -lt $fileList.Count; $j++) {
                $vi = Get-FileVersionKey -fileName $fileList[$i]
                $vj = Get-FileVersionKey -fileName $fileList[$j]
                if ((Compare-FileVersionKey $vi $vj) -lt 0) {
                    $tmp = $fileList[$i]; $fileList[$i] = $fileList[$j]; $fileList[$j] = $tmp
                }
            }
        }

        # ファイル名列: バージョン番号を取り除いた「素の」ファイル名を表示する。
        # 同じIDの複数バージョンはバージョン番号を除けば同一名になるはずなので、
        # 重複を除いた上で(新しい順のまま)並べる。長いバージョン付きファイル名を
        # 複数連結すると読みにくく、古いExcelで表示が崩れることもあるため。
        $baseNames = @()
        foreach ($f in $fileList) {
            $base = Get-BaseFileName -fileName $f
            if ($baseNames -notcontains $base) { $baseNames += $base }
        }

        # 最新バージョンファイル名列: バージョン番号を除去する前の、そのIDに関わった
        # ファイルの中で最もバージョンが新しいものの元のファイル名(バージョン番号込み)
        $latestVersionFileName = if ($fileList.Count -gt 0) { $fileList[0] } else { "" }

        $records += [PSCustomObject]@{
            担当領域   = $entry.担当領域
            ID         = $id
            名称       = $entry.名称
            ファイル名 = ($baseNames -join "、")
            最新バージョンファイル名 = $latestVersionFileName
            項番結果   = $entry.項番結果
        }
    }

    # 結果が1件だけの場合でも配列のままにする(単一オブジェクトだと.Countが効かない)
    $records = @($records | Sort-Object 担当領域, ID)

    # ---- IDのプレフィックスで 画面用(IO_/DL_) / 帳票用(RP_) に振り分ける ----
    $screenRecords = @($records | Where-Object { $_.ID -match '^(IO|DL)_' })
    $reportRecords = @($records | Where-Object { $_.ID -match '^RP_' })
    $unmatched     = @($records | Where-Object { $_.ID -notmatch '^(IO|DL|RP)_' })

    foreach ($u in $unmatched) {
        Write-Host "  警告: ID '$($u.ID)' はIO_/DL_/RP_のどれにも一致しないためスキップします。" -ForegroundColor Yellow
    }

    Write-Host "---- 画面用 ($ScreenOutFileName) ----" -ForegroundColor Cyan
    Write-PivotOutput -excel $excel -records $screenRecords -outPath $screenOutPath -outFileName $ScreenOutFileName

    Write-Host "---- 帳票用 ($ReportOutFileName) ----" -ForegroundColor Cyan
    Write-PivotOutput -excel $excel -records $reportRecords -outPath $reportOutPath -outFileName $ReportOutFileName
}
catch {
    Write-Host "エラー: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if ($null -ne $wbIn) { try { $wbIn.Close($false) } catch {} }
    if ($null -ne $excel) {
        try { $excel.Quit() } catch {}
        try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null } catch {}
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

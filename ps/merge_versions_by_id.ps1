<#
.SYNOPSIS
    実施記録一覧_merge_befor.xlsx(長い形式: 1行 = 1ファイルの1項番の記録)を、
    同じID(機能)の複数バージョンファイルをまとめて、項番ごとに最新バージョンの
    結果を採用した長い形式(実施記録一覧_merge_after.xlsx)に変換するスクリプト。

.DESCRIPTION
    - 古いバージョンのある項番は NG かもしれないし OK かもしれないし、
      そもそも未実施(空欄や "-")かもしれない。後から出た新しいバージョンで
      未実施だった項番が実施されたり、既に実施済みの項番が再実施されたり
      することがある。新しいバージョンほど正しい結果だが、新しいバージョンが
      全項番を網羅しているとは限らない。
    - そのため、各項番について「最新バージョンから順に見ていき、
      最初に見つかった意味のある結果(OK/NG)」を最終結果として採用する。
      どのバージョンでも実施されていない項番は出力しない。
    - ファイル内で同じ項番が複数行にまたがる場合(結合セル由来)は、
      collect_check_records.ps1 / pivot_check_records.ps1 と同じルールで
      先に1つにまとめる:NGが1件でもあればNG、無ければOKが1件でもあればOK。
    - 出力は入力と同じ列構成の長い形式。1行 = 1ID(機能)の1項番の、
      採用されたバージョンファイルの記録(バージョン/実施日/実施者/結果ともに
      採用元のファイルの値をそのまま引き継ぐ)。out.xlsx のような項番一覧
      テンプレートには依存しない(項番を列に展開するのは pivot_check_records.ps1
      の役割)。

.PARAMETER FolderPath
    処理対象のフォルダ。既定値はこのスクリプト自身が置かれているフォルダ($PSScriptRoot)。

.PARAMETER InFileName
    入力ファイル名。既定値は実行日の日付付きで "yyyyMMdd_実施記録一覧_merge_befor.xlsx"。

.PARAMETER OutFileName
    出力ファイル名。既定値は実行日の日付付きで "yyyyMMdd_実施記録一覧_merge_after.xlsx"
    (新規作成/上書き)。

.EXAMPLE
    .\merge_versions_by_id.ps1
#>

param(
    [string]$FolderPath = $PSScriptRoot,
    [string]$InFileName = "$(Get-Date -Format 'yyyyMMdd')_実施記録一覧_merge_befor.xlsx",
    [string]$OutFileName = "$(Get-Date -Format 'yyyyMMdd')_実施記録一覧_merge_after.xlsx"
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

# 指定したテキストが表す列番号を、ヘッダー行(1行目)から探す
function Find-HeaderColumn {
    param($ws, [string]$text, [int]$lastCol)

    for ($c = 1; $c -le $lastCol; $c++) {
        if ($ws.Cells(1, $c).Value2 -eq $text) { return $c }
    }
    return $null
}

# ファイル名の末尾からバージョン番号を抜き出す。
# "_Ver0.41" "_1.03" "_0.58" "_Ver0.99g"(末尾に英字1文字) "入力0.58"(区切り無し) など
# 表記ゆれがあるため、拡張子の直前にある「数字.数字...(英字1文字)」だけを見る。
# 見つからない場合は $null を返す(バージョン不明 = 最も古い扱いにする)。
function Get-FileVersionKey {
    param([string]$fileName)

    if ($fileName -match '(?:Ver)?(\d+(?:\.\d+)+)([A-Za-z]?)\.xlsx$') {
        try {
            $ver = [version]$matches[1]
        } catch {
            return $null
        }
        return [PSCustomObject]@{
            Version = $ver
            Suffix  = $matches[2]
        }
    }
    return $null
}

# 2つのバージョンキーを比較する(aの方が新しければ正の値)。
# バージョン不明(=$null)は常に一番古い扱い。
function Compare-FileVersionKey {
    param($a, $b)

    if ($null -eq $a -and $null -eq $b) { return 0 }
    if ($null -eq $a) { return -1 }
    if ($null -eq $b) { return 1 }

    $cmp = $a.Version.CompareTo($b.Version)
    if ($cmp -ne 0) { return $cmp }
    return [string]::Compare($a.Suffix, $b.Suffix, [System.StringComparison]::Ordinal)
}

$excel = $null
$wbIn = $null
$wbOut = $null
$records = $null

try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    # ---- 実施記録一覧_merge_befor.xlsx を読み込む ----
    $wbIn = $excel.Workbooks.Open($inPath, [Type]::Missing, $true)  # ReadOnly
    $wsIn = $wbIn.Worksheets.Item(1)
    $usedIn = $wsIn.UsedRange
    $lastColIn = [int]$usedIn.Column + [int]$usedIn.Columns.Count - 1
    $lastRowIn = [int]$usedIn.Row + [int]$usedIn.Rows.Count - 1

    $colTopFolder = Find-HeaderColumn -ws $wsIn -text "担当領域"     -lastCol $lastColIn
    $colId        = Find-HeaderColumn -ws $wsIn -text "ID"           -lastCol $lastColIn
    $colLabel     = Find-HeaderColumn -ws $wsIn -text "名称"         -lastCol $lastColIn
    $colFileName  = Find-HeaderColumn -ws $wsIn -text "ファイル名"   -lastCol $lastColIn
    $colFilePath  = Find-HeaderColumn -ws $wsIn -text "ファイルパス" -lastCol $lastColIn
    $colSheetName = Find-HeaderColumn -ws $wsIn -text "シート名"     -lastCol $lastColIn
    $colItemNo    = Find-HeaderColumn -ws $wsIn -text "項番"         -lastCol $lastColIn
    $colVersion   = Find-HeaderColumn -ws $wsIn -text "バージョン"   -lastCol $lastColIn
    $colDate      = Find-HeaderColumn -ws $wsIn -text "実施日"       -lastCol $lastColIn
    $colActor     = Find-HeaderColumn -ws $wsIn -text "実施者"       -lastCol $lastColIn
    $colResult    = Find-HeaderColumn -ws $wsIn -text "結果"         -lastCol $lastColIn

    if ($null -eq $colTopFolder -or $null -eq $colId -or $null -eq $colLabel -or
        $null -eq $colFileName -or $null -eq $colItemNo -or $null -eq $colResult) {
        throw "$InFileName の1行目から必要な列(担当領域/ID/名称/ファイル名/項番/結果)が見つかりませんでした。"
    }

    # 第1段階: ID > ファイル名 > 項番 の階層で、ファイル内の同一項番の複数行を
    # 「NGが1件でもあればNG、無ければOKが1件でもあればOK」でまとめておく。
    # 採用元の行がわかるよう、結果だけでなくバージョン/実施日/実施者/ファイルパス/
    # シート名もそのまま保持する。
    $ids = [ordered]@{}

    for ($r = 2; $r -le $lastRowIn; $r++) {
        $id = $wsIn.Cells($r, $colId).Text
        $fileName = $wsIn.Cells($r, $colFileName).Text
        if ([string]::IsNullOrEmpty($id) -or [string]::IsNullOrEmpty($fileName)) { continue }

        if (-not $ids.Contains($id)) {
            $ids[$id] = [PSCustomObject]@{
                担当領域  = $wsIn.Cells($r, $colTopFolder).Text
                名称      = $wsIn.Cells($r, $colLabel).Text
                Files     = [ordered]@{}
                FilePaths = @{}   # ファイル名 -> ファイルパス(項番の有効/無効に関わらずファイル単位で持つ)
            }
        }
        $idEntry = $ids[$id]

        if (-not $idEntry.Files.Contains($fileName)) {
            $idEntry.Files[$fileName] = @{}
        }
        $fileItems = $idEntry.Files[$fileName]

        # ファイルパスはファイル単位の情報なので、項番が空/結果がOK・NG以外でも
        # (=このすぐ下の continue で弾かれるより前に)必ず記録しておく
        if (-not $idEntry.FilePaths.ContainsKey($fileName)) {
            $idEntry.FilePaths[$fileName] = if ($colFilePath) { $wsIn.Cells($r, $colFilePath).Text } else { "" }
        }

        $itemNo = $wsIn.Cells($r, $colItemNo).Text
        $result = $wsIn.Cells($r, $colResult).Text
        if ([string]::IsNullOrEmpty($itemNo)) { continue }
        if ($result -ne "OK" -and $result -ne "NG") { continue }

        $rowInfo = [PSCustomObject]@{
            結果       = $result
            バージョン = if ($colVersion) { $wsIn.Cells($r, $colVersion).Text } else { "" }
            実施日     = if ($colDate) { $wsIn.Cells($r, $colDate).Text } else { "" }
            実施者     = if ($colActor) { $wsIn.Cells($r, $colActor).Text } else { "" }
            ファイルパス = if ($colFilePath) { $wsIn.Cells($r, $colFilePath).Text } else { "" }
            シート名   = if ($colSheetName) { $wsIn.Cells($r, $colSheetName).Text } else { "" }
        }

        # ファイル内の同一項番の複数行をまとめる(NG優先)
        if ($result -eq "NG") {
            $fileItems[$itemNo] = $rowInfo
        } elseif (-not $fileItems.ContainsKey($itemNo)) {
            $fileItems[$itemNo] = $rowInfo
        }
    }

    $wbIn.Close($false)
    $wbIn = $null

    # 第2段階: IDごとに、ファイルを新しいバージョン順に並べて項番をマージする
    $records = @()
    foreach ($id in $ids.Keys) {
        $idEntry = $ids[$id]

        # バージョンの新しい順(降順)に並べる。PowerShell 5.1 には汎用の
        # Comparer が無いため、Compare-FileVersionKey を使って手動でソートする。
        $fileList = @($idEntry.Files.Keys)
        for ($i = 0; $i -lt $fileList.Count; $i++) {
            for ($j = $i + 1; $j -lt $fileList.Count; $j++) {
                $vi = Get-FileVersionKey -fileName $fileList[$i]
                $vj = Get-FileVersionKey -fileName $fileList[$j]
                if ((Compare-FileVersionKey $vi $vj) -lt 0) {
                    $tmp = $fileList[$i]; $fileList[$i] = $fileList[$j]; $fileList[$j] = $tmp
                }
            }
        }
        # $fileList は新しい順(降順)になる

        $mergedItems = @{}  # 項番 -> (採用元ファイル名, rowInfo)
        foreach ($fileName in $fileList) {
            $fileItems = $idEntry.Files[$fileName]
            foreach ($itemNo in $fileItems.Keys) {
                if (-not $mergedItems.ContainsKey($itemNo)) {
                    $mergedItems[$itemNo] = [PSCustomObject]@{
                        ファイル名 = $fileName
                        Row        = $fileItems[$itemNo]
                    }
                }
            }
        }

        if ($mergedItems.Count -eq 0) {
            # このIDはどのバージョンにも有効なOK/NG記録が1件も無い。
            # collect_check_records.ps1 の「1件も取れなかったファイルも空行を残す」のと
            # 同じ考え方で、最新バージョンのファイル名だけ入れた空行を残す。
            # ファイルパスはファイル単位の情報なので、項番の有無に関わらず引ける。
            $records += [PSCustomObject]@{
                担当領域     = $idEntry.担当領域
                ID           = $id
                名称         = $idEntry.名称
                ファイル名   = $fileList[0]
                ファイルパス = $idEntry.FilePaths[$fileList[0]]
                シート名     = ""
                項番         = ""
                バージョン   = ""
                実施日       = ""
                実施者       = ""
                結果         = ""
            }
        } else {
            foreach ($itemNo in ($mergedItems.Keys | Sort-Object)) {
                $picked = $mergedItems[$itemNo]
                $records += [PSCustomObject]@{
                    担当領域     = $idEntry.担当領域
                    ID           = $id
                    名称         = $idEntry.名称
                    ファイル名   = $picked.ファイル名
                    ファイルパス = $picked.Row.ファイルパス
                    シート名     = $picked.Row.シート名
                    項番         = $itemNo
                    バージョン   = $picked.Row.バージョン
                    実施日       = $picked.Row.実施日
                    実施者       = $picked.Row.実施者
                    結果         = $picked.Row.結果
                }
            }
        }
    }

    # 結果が1件だけの場合でも配列のままにする(単一オブジェクトだと.Countが効かない)
    $records = @($records | Sort-Object 担当領域, ID, 項番)

    if ($records.Count -eq 0) {
        Write-Host "マージ対象の実施記録がありませんでした。出力ファイルは作成しません。" -ForegroundColor Yellow
        exit
    }

    # ---- 実施記録一覧_merge_after.xlsx を新規作成して書き出す ----
    $wbOut = $excel.Workbooks.Add()
    $sheet = $wbOut.Worksheets.Item(1)

    $headers = @("担当領域", "ID", "名称", "ファイル名", "ファイルパス", "シート名", "項番", "バージョン", "実施日", "実施者", "結果")

    # データ範囲をあらかじめ文字列書式にしておく。そうしないと "01"→1、"0.20"→0.2 のように
    # Excel が値を勝手に数値として解釈してしまう(collect_check_records.ps1 と同じ対策)。
    $fullRange = $sheet.Range($sheet.Cells(1, 1), $sheet.Cells($records.Count + 1, $headers.Count))
    $fullRange.NumberFormat = "@"

    for ($c = 0; $c -lt $headers.Count; $c++) {
        $sheet.Cells.Item(1, $c + 1) = $headers[$c]
        $sheet.Cells.Item(1, $c + 1).Font.Bold = $true
    }

    $row = 2
    foreach ($item in $records) {
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
    $wbOut.SaveAs($outPath, 51)
    $wbOut.Close($false)
    $wbOut = $null

    Write-Host "対象ID数: $(($records | Select-Object -ExpandProperty ID -Unique).Count)" -ForegroundColor Green
    Write-Host "出力レコード数: $($records.Count)" -ForegroundColor Green
    Write-Host "出力しました: $outPath" -ForegroundColor Green
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

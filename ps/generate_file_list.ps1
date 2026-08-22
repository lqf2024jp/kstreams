# ===== 从文件名解析ID/名称,生成汇总表 =====
# 请在 work\work 目录下打开 PowerShell 后执行本脚本
$root = Get-Location

# 递归查找所有 xlsx 文件(排除 Excel 打开时产生的临时文件 ~$xxx.xlsx)
$files = Get-ChildItem -Path $root -Recurse -Filter "*.xlsx" -File | Where-Object { $_.Name -notmatch '^~\$' }

$results = @()
$rootPath = (Get-Location).Path

foreach ($f in $files) {
    $name = $f.BaseName  # 不含扩展名的文件名

    # 提取"標準化ルール適用チェックリスト(...)"括号内的内容
    # 括号支持全角（）和半角(),前后允许有空格
    if ($name -match '標準化ルール適用チェックリスト\s*[（(]\s*(.+?)\s*[）)]') {
        $inner = $matches[1]

        # 把括号内内容拆成 ID (纯ASCII: 字母/数字/下划线) 和 名称 (从第一个非ASCII/日文字符开始)
        # 之前用"字母+数字段"猜结构的正则不稳(ID内部结构并不统一,比如字母段+数字段混杂,
        # 或前缀不是固定2个字母),改成按"第一个非ASCII字符出现的位置"切分,更符合实际命名规律
        # 例: "CMN_WP_BP_003_ワークフロー取戻処理"
        #     -> ID  = CMN_WP_BP_003
        #        名称 = ワークフロー取戻処理
        #     "DL_00_M_MENU_GP_メニューグループ検索"
        #     -> ID  = DL_00_M_MENU_GP
        #        名称 = メニューグループ検索
        if ($inner -match '^([\x00-\x7F]+?)_?([^\x00-\x7F].*)$') {
            $id = $matches[1]
            $label = $matches[2]
        } else {
            # 全部是ASCII(没有日文名称部分)的极端情况,原样放入ID,名称留空
            $id = $inner
            $label = ""
        }

        # 担当領域 = 一级目录名(共通/債権/販売①/販売②/販売③)
        $relativePath = $f.DirectoryName.Substring($rootPath.Length).TrimStart('\')
        $topFolder = ($relativePath -split '\\')[0]

        $results += [PSCustomObject]@{
            業務分類       = ""
            担当領域       = $topFolder
            ID             = $id
            名称           = $label
            エクセルファイル名 = $f.Name
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "没有找到符合命名规则的文件。"
} else {
    Write-Host "共解析出 $($results.Count) 条记录:`n"
    $results | Sort-Object 担当領域, ID | Format-Table -AutoSize

    # 直接生成 xlsx 文件(通过 Excel COM 组件,彻底避开CSV编码问题)
    # 前提: 本机需要安装 Excel
    $sorted = $results | Sort-Object 担当領域, ID
    $xlsxPath = Join-Path $root "ファイル一覧.xlsx"

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false

    $workbook = $excel.Workbooks.Add()
    $sheet = $workbook.Worksheets.Item(1)

    # 写表头
    $headers = @("業務分類", "担当領域", "ID", "名称", "エクセルファイル名")
    for ($c = 0; $c -lt $headers.Count; $c++) {
        $sheet.Cells.Item(1, $c + 1) = $headers[$c]
        $sheet.Cells.Item(1, $c + 1).Font.Bold = $true
    }

    # 写数据(从第2行开始)
    $row = 2
    foreach ($item in $sorted) {
        $sheet.Cells.Item($row, 1) = $item.業務分類
        $sheet.Cells.Item($row, 2) = $item.担当領域
        $sheet.Cells.Item($row, 3) = $item.ID
        $sheet.Cells.Item($row, 4) = $item.名称
        $sheet.Cells.Item($row, 5) = $item.エクセルファイル名
        $row++
    }

    # 自动调整列宽
    $usedRange = $sheet.UsedRange
    $usedRange.EntireColumn.AutoFit() | Out-Null

    # 保存为 xlsx (FileFormat 51 = xlOpenXMLWorkbook)
    $workbook.SaveAs($xlsxPath, 51)
    $workbook.Close($false)
    $excel.Quit()

    # 释放COM对象,避免Excel进程残留在后台
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($sheet) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($excel) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    Write-Host "`n已导出到: $xlsxPath"
}

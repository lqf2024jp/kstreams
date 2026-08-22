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

        # 把括号内内容拆成 ID (字母+数字下划线组合) 和 名称 (剩余部分)
        # 例: "IO_06_020_0010_07_他部門得意先出荷入力"
        #     -> ID  = IO_06_020_0010_07
        #        名称 = 他部門得意先出荷入力
        if ($inner -match '^([A-Za-z]{2}(?:_[0-9]+)+)_(.+)$') {
            $id = $matches[1]
            $label = $matches[2]
        } else {
            # 匹配不上标准格式的,ID留原始内容,名称留空,方便你之后人工核对
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

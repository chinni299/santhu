# DuoChat Development Startup Script
# Run this script to start BOTH the backend and Flutter Web together
# Usage: .\start_dev.ps1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DuoChat Dev Startup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if backend is already running
$port5000 = netstat -ano | Select-String ":5000 "
if ($port5000) {
    Write-Host "[INFO] Backend already running on port 5000" -ForegroundColor Yellow
} else {
    Write-Host "[START] Starting Node.js backend on port 5000..." -ForegroundColor Green
    Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\server'; node src/server.js" -WindowStyle Normal
    Start-Sleep -Seconds 3
}

# Verify backend is up
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5000" -UseBasicParsing -TimeoutSec 5
    Write-Host "[OK] Backend is running: $($response.Content.Substring(0,[Math]::Min(60,$response.Content.Length)))" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Backend failed to start! Check server terminal." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[START] Starting Flutter Web on port 49780..." -ForegroundColor Green
Write-Host "  User 1: http://localhost:49780  (Normal window)" -ForegroundColor White
Write-Host "  User 2: http://localhost:49780  (Incognito window)" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C to stop Flutter Web" -ForegroundColor Gray

flutter run -d chrome --web-port 49780

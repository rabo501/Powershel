# Włącz PSRemoting (WinRM)
Enable-PSRemoting -Force

# Upewnij się, że listener działa na wszystkich adresach
winrm quickconfig -q

# Otwórz port 5985 w firewallu (dla WinRM HTTP)
New-NetFirewallRule -Name "WinRM HTTP" -DisplayName "WinRM HTTP" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985

# Sprawdź status usługi WinRM
Get-Service WinRM

Write-Host "Konfiguracja WinRM zakończona! Serwer gotowy do zdalnych poleceń."
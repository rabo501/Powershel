# Skrypt PowerShell do zdalnej aktualizacji Windows z menu
# Wymaga: PSWindowsUpdate, uprawnień administratora, połączenia VPN

function Show-Menu {
    Clear-Host
    Write-Host "     === MENU AKTUALIZACJI WINDOWS ===" -ForegroundColor Green
    Write-Host "     1. Zarządzaj listą komputerów" -ForegroundColor Green
    Write-Host "     2. Sprawdź i skonfiguruj zdalne ustawienia" -ForegroundColor Green
    Write-Host "     3. Wykonaj aktualizacje na komputerach z listy" -ForegroundColor Green
    Write-Host "     0. Wyjście" -ForegroundColor Red
}

function Manage-ComputerList {
    $listPath = ".\ListaKomputerow.txt"
    if (-not (Test-Path $listPath)) { New-Item $listPath -ItemType File | Out-Null }
    $choice = Read-Host "Wybierz opcję: [1] Dodaj komputer [2] Wyświetl listę [3] Usuń komputer"
    switch ($choice) {
        '1' {
            $newComp = Read-Host "Podaj nazwę lub IP komputera"
            Add-Content $listPath $newComp
            Write-Host "Dodano: " + $newComp
        }
        '2' {
            Get-Content $listPath | ForEach-Object { Write-Host $_ }
        }
        '3' {
            $compToRemove = Read-Host "Podaj nazwę/IP komputera do usunięcia"
            (Get-Content $listPath) | Where-Object { $_ -ne $compToRemove } | Set-Content $listPath
            Write-Host "Usunięto: " + $compToRemove
        }
        default {
            Write-Host "Nieprawidłowa opcja!"
        }
    }
    Read-Host "Naciśnij Enter, aby kontynuować..."
}

function Check-And-ConfigureRemote {
    $listPath = ".\ListaKomputerow.txt"
    $computers = Get-Content $listPath
    $cred = Get-Credential -Message "Podaj poświadczenia administratora"
    foreach ($comp in $computers) {
        Write-Host "`nSprawdzanie: " + $comp
        $winrmOK = $false
        $psremotingOK = $false
        $firewallOK = $false
        $errors = @()
        try {
            $winrm = Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                winrm enumerate winrm/config/listener
            } -ErrorAction Stop
            $winrmOK = $true
        } catch {
            $errors += "WinRM NIE działa"
        }
        try {
            $psremoting = Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                Get-PSSessionConfiguration
            } -ErrorAction Stop
            $psremotingOK = $true
        } catch {
            $errors += "PSRemoting NIE działa"
        }
        try {
            $firewall = Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                Get-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" | Where-Object { $_.Enabled -eq "True" }
            } -ErrorAction Stop
            if ($firewall) { $firewallOK = $true } else { $errors += "Reguła firewall WinRM wyłączona" }
        } catch {
            $errors += "Brak reguły firewall WinRM"
        }

        if ($winrmOK -and $psremotingOK -and $firewallOK) {
            Write-Host "Konfiguracja poprawna na " + $comp
        } else {
            Write-Host "Problemy na " + $comp + ":"
            foreach ($err in $errors) { Write-Host "- " + $err }
            $ans = Read-Host "Czy chcesz wykonać automatyczną konfigurację? (T/N)"
            if ($ans -eq 'T') {
                try {
                    Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                        Enable-PSRemoting -Force
                        winrm quickconfig -quiet
                        Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -Enabled True
                    } -ErrorAction Stop
                    Write-Host "Konfiguracja zakończona na " + $comp
                } catch {
                    $blad = "$(Get-Date) | $comp | Konfiguracja | Błąd: $($_.Exception.Message)"
                    Write-Host $blad
                    Add-Content -Path ".\Bledy.txt" -Value $blad
                }
            }
        }
    }
    Read-Host "Naciśnij Enter, aby kontynuować..."
}

function Update-Computers {
    $listPath = ".\ListaKomputerow.txt"
    $computers = Get-Content $listPath
    $cred = Get-Credential -Message "Podaj poświadczenia administratora"
    $report = @()

    foreach ($comp in $computers) {
        Write-Host "`nAktualizuję: " + $comp
        $updateCount = 0
        $updateList = ""
        $status = ""
        $restartNeeded = $false
        $errorDetails = ""

        try {
            $updates = Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                Import-Module PSWindowsUpdate
                Get-WindowsUpdate -AcceptAll -IgnoreReboot
            } -ErrorAction Stop

            if ($updates -and $updates.Count -gt 0) {
                $updateCount = $updates.Count
                $updateList = ($updates | Select-Object -ExpandProperty Title) -join ", "
                Write-Host "Do zainstalowania: $updateCount aktualizacji"
                try {
                    Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                        Import-Module PSWindowsUpdate
                        Install-WindowsUpdate -AcceptAll -IgnoreReboot -AutoReboot
                    } -ErrorAction Stop

                    $restartNeeded = Invoke-Command -ComputerName $comp -Credential $cred -ScriptBlock {
                        (Get-WindowsUpdate -AcceptAll -IgnoreReboot).RebootRequired
                    }

                    $status = "Aktualizacje zainstalowane"
                } catch {
                    $status = "Błąd podczas instalacji"
                    $errorDetails = $_.Exception.Message
                    $blad = "$(Get-Date) | $comp | Update | Błąd instalacji: $errorDetails"
                    Write-Host $blad
                    Add-Content -Path ".\Bledy.txt" -Value $blad
                }
            } else {
                $status = "Brak aktualizacji"
            }
        } catch {
            $status = "Błąd podczas pobierania listy aktualizacji"
            $errorDetails = $_.Exception.Message
            $blad = "$(Get-Date) | $comp | Update | Błąd pobierania listy: $errorDetails"
            Write-Host $blad
            Add-Content -Path ".\Bledy.txt" -Value $blad
        }

        $report += [PSCustomObject]@{
            Komputer = $comp
            Status = $status
            Restart = $restartNeeded
            LiczbaAktualizacji = $updateCount
            ListaAktualizacji = $updateList
            SzczegółyBłędu = $errorDetails
        }
    }
    $report | Export-Csv -Path ".\RaportAktualizacji.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "Raport zapisany do RaportAktualizacji.csv"
    Read-Host "Naciśnij Enter, aby kontynuować..."
}

$kontynuuj = $true
do {
    Show-Menu
    $option = Read-Host "Wybierz opcję"
    switch ($option) {
        '1' { Manage-ComputerList }
        '2' { Check-And-ConfigureRemote }
        '3' { Update-Computers }
        '0' { $kontynuuj = $false }
        default { Write-Host "Nieprawidłowa opcja!" }
    }
} while ($kontynuuj)
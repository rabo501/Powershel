# ==========================================
# Adobe Reader - zdalna instalacja/usuwanie
# Windows PowerShell 5.1 + WinRM
# ==========================================

$InstallerUrl = 'https://ardownload3.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600322110/AcroRdrDCx642600322110_MUI.exe'
$InstallerHash = '345617BAF5EADB2BEDDDF6AB485085385FEF9E81F742957167B20F61E3A44F9F'

# Ten fragment działa na komputerze docelowym.
$ZdalnySkrypt = {
    param(
        [string]$Operacja,
        [bool]$Podglad,
        [string]$Url,
        [string]$OczekiwanyHash
    )

    $ErrorActionPreference = 'Stop'

    function Pobierz-Adobe {
        $Sciezki = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        @(
            Get-ItemProperty -Path $Sciezki -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.DisplayName -match '^Adobe (Acrobat|Reader)\b'
                }
        )
    }

    function Nowy-Wynik {
        param(
            [string]$Program,
            [string]$Wersja,
            [string]$Wynik,
            $Kod = $null,
            [string]$Log = '-'
        )

        [PSCustomObject]@{
            Komputer = $env:COMPUTERNAME
            Program  = $Program
            Wersja   = $Wersja
            Wynik    = $Wynik
            Kod      = $Kod
            Log      = $Log
        }
    }

    try {
        $Programy = @(Pobierz-Adobe)

        # ==========================================
        # INSTALACJA
        # ==========================================
        if ($Operacja -eq 'Instalacja') {

            # Nie instalujemy na istniejącym Acrobacie/Readerze.
            if ($Programy.Count -gt 0) {
                foreach ($Program in $Programy) {
                    Nowy-Wynik `
                        -Program $Program.DisplayName `
                        -Wersja $Program.DisplayVersion `
                        -Wynik 'Pominięto instalację: Adobe jest już zainstalowany.'
                }
                return
            }

            if ($Podglad) {
                Nowy-Wynik `
                    -Program 'Adobe Acrobat Reader 64-bit' `
                    -Wersja '26.003.22110' `
                    -Wynik 'Gotowy do pobrania i instalacji.'
                return
            }

            $Architektura = [Environment]::GetEnvironmentVariable(
                'PROCESSOR_ARCHITECTURE',
                'Machine'
            )

            if ($Architektura -ne 'AMD64') {
                Nowy-Wynik `
                    -Program 'Adobe Acrobat Reader 64-bit' `
                    -Wersja '-' `
                    -Wynik "Pominięto: architektura systemu to $Architektura, a pakiet jest przeznaczony dla x64."
                return
            }

            $Id = [guid]::NewGuid().ToString('N')
            $Folder = Join-Path $env:TEMP "AdobeReader-$Id"
            $Instalator = Join-Path $Folder 'AdobeReaderSetup.exe'
            $Log = Join-Path $env:WINDIR "Temp\AdobeReader-install-$Id.log"

            try {
                New-Item -Path $Folder -ItemType Directory -Force |
                    Out-Null

                # Każda stacja pobiera plik bezpośrednio z Adobe.
                [Net.ServicePointManager]::SecurityProtocol =
                    [Net.SecurityProtocolType]::Tls12

                Invoke-WebRequest `
                    -Uri $Url `
                    -OutFile $Instalator `
                    -UseBasicParsing `
                    -ErrorAction Stop

                # Weryfikacja sumy pliku.
                $Hash = (Get-FileHash -Path $Instalator -Algorithm SHA256).Hash

                if ($Hash -ne $OczekiwanyHash) {
                    throw "Niezgodna suma SHA-256. Instalacja została zatrzymana."
                }

                # Weryfikacja podpisu cyfrowego.
                $Podpis = Get-AuthenticodeSignature -FilePath $Instalator

                if (
                    $Podpis.Status -ne 'Valid' -or
                    $null -eq $Podpis.SignerCertificate -or
                    $Podpis.SignerCertificate.Subject -notmatch 'Adobe'
                ) {
                    throw "Nie udało się potwierdzić ważnego podpisu Adobe. Status: $($Podpis.Status)."
                }

                # Cicha instalacja; bez automatycznego restartu.
                # Log MSI zostanie zapisany na komputerze docelowym.
                $Argumenty = "-sfx_nu /sAll /rs /msi /L*v `"$Log`" REBOOT=ReallySuppress"

                $Proces = Start-Process `
                    -FilePath $Instalator `
                    -ArgumentList $Argumenty `
                    -Wait `
                    -PassThru `
                    -ErrorAction Stop

                $Kod = $Proces.ExitCode
                $PoInstalacji = @(Pobierz-Adobe)

                if ($Kod -eq 0 -and $PoInstalacji.Count -gt 0) {
                    $Nazwa = ($PoInstalacji.DisplayName -join '; ')
                    $Wersja = ($PoInstalacji.DisplayVersion -join '; ')

                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik 'Instalator zakończył pracę; znaleziono wpis Adobe.' `
                        -Kod $Kod `
                        -Log $Log
                }
                elseif ($Kod -eq 3010) {
                    Nowy-Wynik `
                        -Program 'Adobe Acrobat Reader 64-bit' `
                        -Wersja '26.003.22110' `
                        -Wynik 'Instalacja wymaga ponownego uruchomienia komputera.' `
                        -Kod $Kod `
                        -Log $Log
                }
                else {
                    Nowy-Wynik `
                        -Program 'Adobe Acrobat Reader 64-bit' `
                        -Wersja '26.003.22110' `
                        -Wynik 'Nie potwierdzono instalacji. Sprawdź kod i log.' `
                        -Kod $Kod `
                        -Log $Log
                }
            }
            catch {
                Nowy-Wynik `
                    -Program 'Adobe Acrobat Reader 64-bit' `
                    -Wersja '26.003.22110' `
                    -Wynik "Błąd pobierania lub instalacji: $($_.Exception.Message)" `
                    -Log $Log
            }
            finally {
                # Usuwamy tylko tymczasowy instalator utworzony przez skrypt.
                if (Test-Path -LiteralPath $Folder) {
                    Remove-Item -LiteralPath $Folder -Recurse -Force `
                        -ErrorAction SilentlyContinue
                }
            }

            return
        }

        # ==========================================
        # ODINSTALOWANIE
        # ==========================================
        if ($Operacja -eq 'Usuwanie') {

            if ($Programy.Count -eq 0) {
                Nowy-Wynik `
                    -Program '-' `
                    -Wersja '-' `
                    -Wynik 'Nie znaleziono wpisu Adobe Acrobat ani Reader.'
                return
            }

            # Nie zamykamy programu za użytkownika.
            $AdobeUruchomiony = @(
                Get-Process -Name 'Acrobat', 'AcroRd32' `
                    -ErrorAction SilentlyContinue
            ).Count -gt 0

            foreach ($Program in $Programy) {
                $Nazwa = $Program.DisplayName
                $Wersja = $Program.DisplayVersion
                $KodMSI = $Program.PSChildName

                $CzyReader = $Nazwa -match '^Adobe (Acrobat )?Reader\b'
                $CzyAcrobat64 = $Nazwa -eq 'Adobe Acrobat (64-bit)'
                $CzyDoUsuniecia = $CzyReader -or $CzyAcrobat64

                $CzyMSI = (
                    $Program.WindowsInstaller -eq 1 -and
                    $KodMSI -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
                )

                if (-not $CzyDoUsuniecia) {
                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik 'Pominięto: nazwa nie znajduje się na liście do usunięcia.'
                    continue
                }

                if (-not $CzyMSI) {
                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik 'Pominięto: nie rozpoznano kodu instalacji MSI.'
                    continue
                }

                if ($AdobeUruchomiony) {
                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik 'Pominięto: Adobe jest uruchomiony. Zamknij program i ponów operację.'
                    continue
                }

                if ($Podglad) {
                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik "Gotowy do usunięcia. Kod MSI: $KodMSI"
                    continue
                }

                $Id = [guid]::NewGuid().ToString('N')
                $Log = Join-Path $env:WINDIR "Temp\AdobeReader-uninstall-$Id.log"

                try {
                    $Argumenty = "/x $KodMSI /qn /norestart /L*v `"$Log`""

                    $Proces = Start-Process `
                        -FilePath "$env:SystemRoot\System32\msiexec.exe" `
                        -ArgumentList $Argumenty `
                        -Wait `
                        -PassThru `
                        -ErrorAction Stop

                    $Kod = $Proces.ExitCode
                    $WpisPozostal = Test-Path -LiteralPath $Program.PSPath

                    if ($Kod -eq 0 -and -not $WpisPozostal) {
                        $Opis = 'Odinstalowano; wpis programu zniknął z rejestru.'
                    }
                    elseif ($Kod -eq 3010) {
                        $Opis = 'Wymagane ponowne uruchomienie komputera.'
                    }
                    else {
                        $Opis = "Nie potwierdzono usunięcia. Wpis pozostał: $WpisPozostal. Sprawdź log."
                    }

                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik $Opis `
                        -Kod $Kod `
                        -Log $Log
                }
                catch {
                    Nowy-Wynik `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Wynik "Błąd odinstalowania: $($_.Exception.Message)" `
                        -Log $Log
                }
            }

            return
        }

        throw "Nieznana operacja: $Operacja"
    }
    catch {
        Nowy-Wynik `
            -Program '-' `
            -Wersja '-' `
            -Wynik "Błąd na komputerze docelowym: $($_.Exception.Message)"
    }
}

function Uruchom-NaKomputerach {
    param(
        [string[]]$Komputery,
        [string]$Operacja,
        [bool]$Podglad
    )

    foreach ($Komputer in $Komputery) {
        Write-Host "Sprawdzam: $Komputer" -ForegroundColor Cyan

        try {
            Invoke-Command `
                -ComputerName $Komputer `
                -ScriptBlock $ZdalnySkrypt `
                -ArgumentList $Operacja, $Podglad, $InstallerUrl, $InstallerHash `
                -ErrorAction Stop
        }
        catch {
            [PSCustomObject]@{
                Komputer = $Komputer
                Program  = '-'
                Wersja   = '-'
                Wynik    = "Błąd połączenia lub wykonania: $($_.Exception.Message)"
                Kod      = $null
                Log      = '-'
            }
        }
    }
}

do {
    Write-Host ''
    Write-Host '========================================'
    Write-Host '        ZARZĄDZANIE ADOBE READER'
    Write-Host '========================================'
    Write-Host '1. Usuń Adobe Reader'
    Write-Host '2. Zainstaluj Adobe Reader'
    Write-Host '3. Wyjście'
    Write-Host ''

    $Wybor = Read-Host 'Wybierz opcję'

    if ($Wybor -eq '3') {
        break
    }

    if ($Wybor -notin @('1', '2')) {
        Write-Host 'Nieprawidłowa opcja.' -ForegroundColor Yellow
        continue
    }

    $Operacja = if ($Wybor -eq '1') {
        'Usuwanie'
    }
    else {
        'Instalacja'
    }

    $WpisaneKomputery = Read-Host 'Podaj nazwy komputerów po przecinku'

    $Komputery = @(
        $WpisaneKomputery -split '[,;]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Select-Object -Unique
    )

    if ($Komputery.Count -eq 0) {
        Write-Host 'Nie podano nazw komputerów.' -ForegroundColor Yellow
        continue
    }

    Write-Host ''
    Write-Host "PODGLĄD — $Operacja" -ForegroundColor Yellow

    $PodgladWyniki = @(
        Uruchom-NaKomputerach `
            -Komputery $Komputery `
            -Operacja $Operacja `
            -Podglad $true
    )

    $PodgladWyniki |
        Format-Table Komputer, Program, Wersja, Wynik -AutoSize -Wrap

    Write-Host ''
    $Potwierdzenie = Read-Host 'Aby wykonać operację, wpisz TAK'

    if ($Potwierdzenie -ne 'TAK') {
        Write-Host 'Operacja anulowana.' -ForegroundColor Yellow
        continue
    }

    Write-Host ''
    Write-Host "WYKONYWANIE — $Operacja" -ForegroundColor Green

    $Wyniki = @(
        Uruchom-NaKomputerach `
            -Komputery $Komputery `
            -Operacja $Operacja `
            -Podglad $false
    )

    Write-Host ''
    Write-Host 'PODSUMOWANIE' -ForegroundColor Green

    $Wyniki |
        Format-Table Komputer, Program, Wersja, Wynik, Kod -AutoSize -Wrap

    Write-Host ''
    Write-Host 'SZCZEGÓŁY — w tym logi na komputerach docelowych'

    $Wyniki |
        Format-List Komputer, Program, Wersja, Wynik, Kod, Log

} while ($true)

Write-Host 'Koniec pracy skryptu.'
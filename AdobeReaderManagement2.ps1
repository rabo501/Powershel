# ==========================================================
# ZDALNE ZARZĄDZANIE ADOBE READER
# Windows PowerShell 5.1 + WinRM
#
# Lista komputerów:
# %LOCALAPPDATA%\AdobeReaderZarzadzanie\komputery.txt
# ==========================================================

$WersjaInstalatora = '26.003.22110'
$InstallerUrl = 'https://ardownload3.adobe.com/pub/adobe/acrobat/win/AcrobatDC/2600322110/AcroRdrDCx642600322110_MUI.exe'
$InstallerHash = '345617BAF5EADB2BEDDDF6AB485085385FEF9E81F742957167B20F61E3A44F9F'

$FolderDanych = Join-Path $env:LOCALAPPDATA 'AdobeReaderZarzadzanie'
$PlikKomputerow = Join-Path $FolderDanych 'komputery.txt'

try {
    New-Item -Path $FolderDanych -ItemType Directory -Force -ErrorAction Stop |
        Out-Null
}
catch {
    Write-Host "Nie można utworzyć folderu listy komputerów: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# ----------------------------------------------------------
# FUNKCJE LISTY KOMPUTERÓW
# ----------------------------------------------------------

function Pobierz-ListeKomputerow {
    if (-not (Test-Path -LiteralPath $PlikKomputerow)) {
        return
    }

    Get-Content -LiteralPath $PlikKomputerow -Encoding UTF8 -ErrorAction Stop |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' } |
        Select-Object -Unique
}

function Zapisz-ListeKomputerow {
    param(
        [AllowEmptyCollection()]
        [string[]]$Komputery
    )

    $Unikalne = @(
        $Komputery |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Sort-Object -Unique
    )

    # Zapisuje także pustą listę, jeśli usunięto ostatni komputer.
    [System.IO.File]::WriteAllLines(
        $PlikKomputerow,
        [string[]]$Unikalne,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Pokaz-ListeKomputerow {
    $Lista = @(Pobierz-ListeKomputerow)

    Write-Host ''
    Write-Host 'LISTA KOMPUTERÓW' -ForegroundColor Cyan

    if ($Lista.Count -eq 0) {
        Write-Host 'Lista jest pusta.'
    }
    else {
        $Numer = 1

        foreach ($Komputer in $Lista) {
            Write-Host ("{0}. {1}" -f $Numer, $Komputer)
            $Numer++
        }
    }

    Write-Host ''
    Write-Host "Plik listy: $PlikKomputerow"
}

function Podziel-Nazwy {
    param([string]$Tekst)

    @(
        $Tekst -split '[,;]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            Select-Object -Unique
    )
}

function Menu-ListyKomputerow {
    do {
        Pokaz-ListeKomputerow

        Write-Host ''
        Write-Host '1. Dodaj komputery'
        Write-Host '2. Usuń komputery z listy'
        Write-Host '3. Wróć do menu głównego'
        Write-Host ''

        $WyborListy = Read-Host 'Wybierz opcję'

        switch ($WyborListy) {
            '1' {
                $Tekst = Read-Host 'Podaj nazwy komputerów po przecinku'
                $Nowe = @(Podziel-Nazwy -Tekst $Tekst)

                if ($Nowe.Count -eq 0) {
                    Write-Host 'Nie podano nazw.' -ForegroundColor Yellow
                    break
                }

                $Biezace = @(Pobierz-ListeKomputerow)

                try {
                    Zapisz-ListeKomputerow -Komputery @($Biezace + $Nowe)
                    Write-Host 'Lista została zapisana.' -ForegroundColor Green
                }
                catch {
                    Write-Host "Błąd zapisu listy: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            '2' {
                $Tekst = Read-Host 'Podaj nazwy do usunięcia po przecinku'
                $DoUsuniecia = @(Podziel-Nazwy -Tekst $Tekst)

                if ($DoUsuniecia.Count -eq 0) {
                    Write-Host 'Nie podano nazw.' -ForegroundColor Yellow
                    break
                }

                $Biezace = @(Pobierz-ListeKomputerow)

                $Pozostale = @(
                    $Biezace |
                        Where-Object { $_ -notin $DoUsuniecia }
                )

                try {
                    Zapisz-ListeKomputerow -Komputery $Pozostale
                    Write-Host 'Lista została zapisana.' -ForegroundColor Green
                }
                catch {
                    Write-Host "Błąd zapisu listy: $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            '3' {
                return
            }

            default {
                Write-Host 'Nieprawidłowa opcja.' -ForegroundColor Yellow
            }
        }
    } while ($true)
}

# ----------------------------------------------------------
# SKRYPT WYKONYWANY NA KOMPUTERZE DOCELOWYM
# ----------------------------------------------------------

$ZdalnySkrypt = {
    param(
        [string]$Operacja,
        [bool]$Podglad,
        [string]$Url,
        [string]$OczekiwanyHash,
        [string]$WersjaInstalatora
    )

    $ErrorActionPreference = 'Stop'

    function Nowy-Wynik {
        param(
            [string]$Status,
            [string]$Program = '-',
            [string]$Wersja = '-',
            [string]$Szczegoly = '-',
            $Kod = $null,
            [string]$Log = '-'
        )

        [PSCustomObject]@{
            Komputer  = $env:COMPUTERNAME
            Status    = $Status
            Program   = $Program
            Wersja    = $Wersja
            Szczegoly = $Szczegoly
            Kod       = $Kod
            Log       = $Log
        }
    }

    function Pobierz-Adobe {
        $Sciezki = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        @(
            Get-ItemProperty -Path $Sciezki -ErrorAction Stop |
                Where-Object {
                    $_.DisplayName -match '^Adobe (Acrobat|Reader)\b'
                }
        )
    }

    function Czy-ObslugiwanyProgram {
        param([string]$Nazwa)

        return (
            $Nazwa -match '^Adobe (Acrobat )?Reader\b' -or
            $Nazwa -eq 'Adobe Acrobat (64-bit)'
        )
    }

    try {
        $Programy = @(Pobierz-Adobe)

        $Obslugiwane = @(
            $Programy |
                Where-Object {
                    Czy-ObslugiwanyProgram -Nazwa $_.DisplayName
                }
        )

        # ==================================================
        # SPRAWDZENIE INSTALACJI
        # ==================================================

        if ($Operacja -eq 'Sprawdzanie') {
            if ($Obslugiwane.Count -gt 0) {
                $Nazwy = ($Obslugiwane |
                    ForEach-Object { $_.DisplayName }) -join '; '

                $Wersje = ($Obslugiwane |
                    ForEach-Object { $_.DisplayVersion }) -join '; '

                Nowy-Wynik `
                    -Status 'Zainstalowany' `
                    -Program $Nazwy `
                    -Wersja $Wersje `
                    -Szczegoly 'Znaleziono wpis w rejestrze.'
            }
            elseif ($Programy.Count -gt 0) {
                $Nazwy = ($Programy |
                    ForEach-Object { $_.DisplayName }) -join '; '

                Nowy-Wynik `
                    -Status 'Do sprawdzenia' `
                    -Program $Nazwy `
                    -Szczegoly 'Znaleziono inną nazwę Adobe Acrobat/Reader.'
            }
            else {
                Nowy-Wynik `
                    -Status 'Nie znaleziono' `
                    -Szczegoly 'Brak pasującego wpisu instalacji w rejestrze HKLM.'
            }

            return
        }

        # ==================================================
        # INSTALACJA
        # ==================================================

        if ($Operacja -eq 'Instalacja') {
            if ($Programy.Count -gt 0) {
                $Nazwy = ($Programy |
                    ForEach-Object { $_.DisplayName }) -join '; '

                Nowy-Wynik `
                    -Status 'Pominięto' `
                    -Program $Nazwy `
                    -Szczegoly 'Adobe Acrobat lub Reader jest już zainstalowany.'
                return
            }

            $Architektura = [Environment]::GetEnvironmentVariable(
                'PROCESSOR_ARCHITECTURE',
                'Machine'
            )

            if ($Architektura -ne 'AMD64') {
                Nowy-Wynik `
                    -Status 'Pominięto' `
                    -Szczegoly "System ma architekturę $Architektura; instalator jest przeznaczony dla x64."
                return
            }

            if ($Podglad) {
                Nowy-Wynik `
                    -Status 'Do instalacji' `
                    -Program 'Adobe Acrobat Reader 64-bit' `
                    -Wersja $WersjaInstalatora `
                    -Szczegoly 'Instalator zostanie pobrany na tę stację.'
                return
            }

            $Id = [guid]::NewGuid().ToString('N')
            $Folder = Join-Path $env:TEMP "AdobeReader-$Id"
            $Instalator = Join-Path $Folder 'AdobeReaderSetup.exe'
            $Log = Join-Path $env:WINDIR "Temp\AdobeReader-install-$Id.log"

            try {
                New-Item -Path $Folder -ItemType Directory -Force |
                    Out-Null

                [Net.ServicePointManager]::SecurityProtocol =
                    [Net.SecurityProtocolType]::Tls12

                Invoke-WebRequest `
                    -Uri $Url `
                    -OutFile $Instalator `
                    -UseBasicParsing `
                    -ErrorAction Stop

                $Hash = (
                    Get-FileHash -Path $Instalator -Algorithm SHA256
                ).Hash

                if ($Hash -ne $OczekiwanyHash) {
                    throw 'Niezgodna suma SHA-256 instalatora.'
                }

                $Podpis = Get-AuthenticodeSignature -FilePath $Instalator

                if (
                    $Podpis.Status -ne 'Valid' -or
                    $null -eq $Podpis.SignerCertificate -or
                    $Podpis.SignerCertificate.Subject -notmatch 'Adobe'
                ) {
                    throw "Nie potwierdzono podpisu Adobe. Status: $($Podpis.Status)."
                }

                $Argumenty = "-sfx_nu /sAll /rs /msi /L*v `"$Log`" REBOOT=ReallySuppress"

                $Proces = Start-Process `
                    -FilePath $Instalator `
                    -ArgumentList $Argumenty `
                    -Wait `
                    -PassThru `
                    -ErrorAction Stop

                $Kod = $Proces.ExitCode

                $PoInstalacji = @(
                    Pobierz-Adobe |
                        Where-Object {
                            Czy-ObslugiwanyProgram -Nazwa $_.DisplayName
                        }
                )

                if ($Kod -eq 0 -and $PoInstalacji.Count -gt 0) {
                    $Nazwy = ($PoInstalacji |
                        ForEach-Object { $_.DisplayName }) -join '; '

                    $Wersje = ($PoInstalacji |
                        ForEach-Object { $_.DisplayVersion }) -join '; '

                    Nowy-Wynik `
                        -Status 'Zainstalowano' `
                        -Program $Nazwy `
                        -Wersja $Wersje `
                        -Szczegoly 'Znaleziono wpis po instalacji.' `
                        -Kod $Kod `
                        -Log $Log
                }
                elseif ($Kod -eq 3010) {
                    Nowy-Wynik `
                        -Status 'Wymagany restart' `
                        -Program 'Adobe Acrobat Reader 64-bit' `
                        -Wersja $WersjaInstalatora `
                        -Szczegoly 'Uruchom ponownie komputer i sprawdź instalację.' `
                        -Kod $Kod `
                        -Log $Log
                }
                else {
                    Nowy-Wynik `
                        -Status 'Nie potwierdzono' `
                        -Program 'Adobe Acrobat Reader 64-bit' `
                        -Wersja $WersjaInstalatora `
                        -Szczegoly 'Sprawdź kod i log.' `
                        -Kod $Kod `
                        -Log $Log
                }
            }
            catch {
                Nowy-Wynik `
                    -Status 'Błąd instalacji' `
                    -Szczegoly $_.Exception.Message `
                    -Log $Log
            }
            finally {
                if (Test-Path -LiteralPath $Folder) {
                    Remove-Item `
                        -LiteralPath $Folder `
                        -Recurse `
                        -Force `
                        -ErrorAction SilentlyContinue
                }
            }

            return
        }

        # ==================================================
        # ODINSTALOWANIE
        # ==================================================

        if ($Operacja -eq 'Usuwanie') {
            if ($Programy.Count -eq 0) {
                Nowy-Wynik `
                    -Status 'Nie znaleziono' `
                    -Szczegoly 'Brak wpisu Adobe Acrobat lub Reader.'
                return
            }

            $AdobeUruchomiony = @(
                Get-Process -Name 'Acrobat', 'AcroRd32' `
                    -ErrorAction SilentlyContinue
            ).Count -gt 0

            foreach ($Program in $Programy) {
                $Nazwa = $Program.DisplayName
                $Wersja = $Program.DisplayVersion
                $KodMSI = $Program.PSChildName

                $CzyObslugiwany = Czy-ObslugiwanyProgram -Nazwa $Nazwa

                $CzyMSI = (
                    $Program.WindowsInstaller -eq 1 -and
                    $KodMSI -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
                )

                if (-not $CzyObslugiwany) {
                    Nowy-Wynik `
                        -Status 'Pominięto' `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly 'Nazwa nie znajduje się na liście do usunięcia.'
                    continue
                }

                if (-not $CzyMSI) {
                    Nowy-Wynik `
                        -Status 'Pominięto' `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly 'Nie rozpoznano kodu produktu MSI.'
                    continue
                }

                if ($AdobeUruchomiony) {
                    Nowy-Wynik `
                        -Status 'Pominięto' `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly 'Adobe jest uruchomiony. Zamknij go i ponów operację.'
                    continue
                }

                if ($Podglad) {
                    Nowy-Wynik `
                        -Status 'Do usunięcia' `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly "Kod MSI: $KodMSI"
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
                        $Status = 'Usunięto'
                        $Opis = 'Wpis instalacji zniknął z rejestru.'
                    }
                    elseif ($Kod -eq 3010) {
                        $Status = 'Wymagany restart'
                        $Opis = 'Uruchom ponownie komputer i sprawdź instalację.'
                    }
                    else {
                        $Status = 'Nie potwierdzono'
                        $Opis = "Wpis pozostał: $WpisPozostal. Sprawdź kod i log."
                    }

                    Nowy-Wynik `
                        -Status $Status `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly $Opis `
                        -Kod $Kod `
                        -Log $Log
                }
                catch {
                    Nowy-Wynik `
                        -Status 'Błąd usuwania' `
                        -Program $Nazwa `
                        -Wersja $Wersja `
                        -Szczegoly $_.Exception.Message `
                        -Log $Log
                }
            }

            return
        }

        throw "Nieznana operacja: $Operacja"
    }
    catch {
        Nowy-Wynik `
            -Status 'Błąd' `
            -Szczegoly $_.Exception.Message
    }
}

# ----------------------------------------------------------
# WYWOŁANIE NA KOMPUTERACH Z LISTY
# ----------------------------------------------------------

function Uruchom-NaKomputerach {
    param(
        [string[]]$Komputery,
        [string]$Operacja,
        [bool]$Podglad
    )

    foreach ($Komputer in $Komputery) {
        Write-Host "Łączę z: $Komputer" -ForegroundColor Cyan

        try {
            $ArgumentyZdalne = @(
                $Operacja
                $Podglad
                $InstallerUrl
                $InstallerHash
                $WersjaInstalatora
            )

            $WynikZdalny = @(
                Invoke-Command `
                    -ComputerName $Komputer `
                    -ScriptBlock $ZdalnySkrypt `
                    -ArgumentList $ArgumentyZdalne `
                    -ErrorAction Stop
            )

            if ($WynikZdalny.Count -eq 0) {
                [PSCustomObject]@{
                    Komputer  = $Komputer
                    Status    = 'Brak wyniku'
                    Program   = '-'
                    Wersja    = '-'
                    Szczegoly = 'Komputer nie zwrócił wyniku.'
                    Kod       = $null
                    Log       = '-'
                }
            }
            else {
                $WynikZdalny
            }
        }
        catch {
            [PSCustomObject]@{
                Komputer  = $Komputer
                Status    = 'Błąd połączenia'
                Program   = '-'
                Wersja    = '-'
                Szczegoly = $_.Exception.Message
                Kod       = $null
                Log       = '-'
            }
        }
    }
}

# ----------------------------------------------------------
# MENU GŁÓWNE
# ----------------------------------------------------------

do {
    Write-Host ''
    Write-Host '========================================'
    Write-Host '        ZARZĄDZANIE ADOBE READER'
    Write-Host '========================================'
    Write-Host '1. Usuń Adobe Reader'
    Write-Host '2. Zainstaluj Adobe Reader'
    Write-Host '3. Sprawdź instalację'
    Write-Host '4. Lista komputerów'
    Write-Host '5. Wyjście'
    Write-Host ''

    $Wybor = Read-Host 'Wybierz opcję'

    if ($Wybor -eq '5') {
        break
    }

    if ($Wybor -eq '4') {
        try {
            Menu-ListyKomputerow
        }
        catch {
            Write-Host "Błąd listy komputerów: $($_.Exception.Message)" -ForegroundColor Red
        }

        continue
    }

    if ($Wybor -notin @('1', '2', '3')) {
        Write-Host 'Nieprawidłowa opcja.' -ForegroundColor Yellow
        continue
    }

    try {
        $Komputery = @(Pobierz-ListeKomputerow)
    }
    catch {
        Write-Host "Nie można odczytać listy: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    if ($Komputery.Count -eq 0) {
        Write-Host 'Lista komputerów jest pusta. Dodaj komputery w menu 4.' -ForegroundColor Yellow
        continue
    }

    # Sprawdzenie tylko odczytuje informacje.
    if ($Wybor -eq '3') {
        Write-Host ''
        Write-Host 'SPRAWDZANIE INSTALACJI' -ForegroundColor Yellow

        $Wyniki = @(
            Uruchom-NaKomputerach `
                -Komputery $Komputery `
                -Operacja 'Sprawdzanie' `
                -Podglad $true
        )

        Write-Host ''
        $Wyniki |
            Format-Table Komputer, Status, Program, Wersja, Szczegoly -AutoSize -Wrap

        continue
    }

    $Operacja = if ($Wybor -eq '1') {
        'Usuwanie'
    }
    else {
        'Instalacja'
    }

    Write-Host ''
    Write-Host "PODGLĄD — $Operacja" -ForegroundColor Yellow
    Write-Host 'Operacja dotyczy wszystkich komputerów z zapisanej listy.'

    $PodgladWyniki = @(
        Uruchom-NaKomputerach `
            -Komputery $Komputery `
            -Operacja $Operacja `
            -Podglad $true
    )

    Write-Host ''
    $PodgladWyniki |
        Format-Table Komputer, Status, Program, Wersja, Szczegoly -AutoSize -Wrap

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
        Format-Table Komputer, Status, Program, Wersja, Kod -AutoSize -Wrap

    Write-Host ''
    Write-Host 'SZCZEGÓŁY — w tym ścieżki logów na stacjach'

    $Wyniki |
        Format-List Komputer, Status, Program, Wersja, Szczegoly, Kod, Log

} while ($true)

Write-Host 'Koniec pracy skryptu.'
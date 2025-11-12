Import-Module ActiveDirectory

function Show-Menu {
    Clear-Host
    Write-Host "      ======== MENU ZARZĄDZANIA UŻYTKOWNIKAMI ========"
    Write-Host "      1. Zarządzanie użytkownikami"
    Write-Host "      7. Odblokowanie konta"
    Write-Host "      8. Wyświetlanie historii logowania"
    Write-Host "      9. Przypisywanie uprawnień/kontenerów OU"
    Write-Host "      10. Masowe dodawanie do grupy (CSV)"
    Write-Host "      11. Eksport listy użytkowników do CSV"
    Write-Host "      0. Wyjście" -ForegroundColor Red
    Write-Host "      ==============================================="
}

function User-Management-Menu {
    do {
        Clear-Host
        Write-Host "      === Menu Zarządzania Użytkownikami ==="
        Write-Host "      1. Lista użytkowników (z wyborem OU)"
        Write-Host "      2. Dodawanie/modyfikacja użytkownika (e-mail, telefon, dział)"
        Write-Host "      3. Dodanie użytkownika do grupy (z filtrowaniem grup)"
        Write-Host "      4. Usunięcie użytkownika z grupy (z filtrowaniem grup)"
        Write-Host "      5. Sprawdzenie członkostwa użytkownika w grupach"
        Write-Host "      6. Zmiana hasła użytkownika"
        Write-Host "      0. Wyjście" -ForegroundColor Red
        $choice = Read-Host "Wybierz opcję (1-6 lub 0 aby wyjść)"

        switch ($choice) {
            1 { List-Users }
            2 { AddOrModify-User }
            3 { Add-UserToGroup }
            4 { Remove-UserFromGroup }
            5 { Check-UserGroups }
            6 { Change-UserPassword }
            0 { Write-Host "Wyjście " }
            default { Write-Host "Nieprawidłowy wybór." }
        }
        if ($choice -ne "0") { Pause }
    } while ($choice -ne "0")
}

function List-Users {
    $ous = @(Get-ADOrganizationalUnit -Filter * | Select-Object Name, DistinguishedName)

    Write-Host "Wybierz OU z listy lub wpisz 0, aby pobrać użytkowników z całego AD:"
    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Host "$($i + 1). $($ous[$i].Name) ($($ous[$i].DistinguishedName))"
    }
    Write-Host "0. Całe AD"

    $choice = Read-Host "Podaj numer OU"
    if ($choice -eq "0") {
        Get-ADUser -Filter * | Select-Object Name, SamAccountName, Enabled | Format-Table
    } elseif (($choice -match '^\d+$') -and ([int]$choice -ge 1) -and ([int]$choice -le $ous.Count)) {
        $selectedOU = $ous[[int]$choice - 1].DistinguishedName
        Get-ADUser -SearchBase $selectedOU -Filter * | Select-Object Name, SamAccountName, Enabled | Format-Table
    } else {
        Write-Host "Nieprawidłowy wybór."
    }
    Pause
}

function AddOrModify-User {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -Properties EmailAddress, telephoneNumber, Department -ErrorAction SilentlyContinue
    if ($user) {
        Write-Host "Użytkownik istnieje. Modyfikacja."
        Write-Host "Aktualny adres e-mail: $($user.EmailAddress)"
        $newEmail = Read-Host "Podaj nowy adres e-mail (Enter, aby nie zmieniać)"
        if ($newEmail) {
            Set-ADUser -Identity $sam -EmailAddress $newEmail
            Write-Host "Adres e-mail został zmieniony."
        } else {
            Write-Host "Adres e-mail bez zmian."
        }
        Write-Host "Aktualny numer telefonu: $($user.telephoneNumber)"
        $newPhone = Read-Host "Podaj nowy numer telefonu (Enter, aby nie zmieniać)"
        if ($newPhone) {
            Set-ADUser -Identity $sam -telephoneNumber $newPhone
            Write-Host "Numer telefonu został zmieniony."
        } else {
            Write-Host "Numer telefonu bez zmian."
        }
        Write-Host "Aktualny dział: $($user.Department)"
        $newDept = Read-Host "Podaj nowy dział (Enter, aby nie zmieniać)"
        if ($newDept) {
            Set-ADUser -Identity $sam -Department $newDept
            Write-Host "Dział został zmieniony."
        } else {
            Write-Host "Dział bez zmian."
        }
        $newName = Read-Host "Podaj nową nazwę (Enter, aby pominąć)"
        if ($newName) { Set-ADUser -Identity $sam -Name $newName }
        Write-Host "Zmiany zapisane."
    } else {
        Write-Host "Tworzenie nowego użytkownika..."
        $name = Read-Host "Podaj nazwę"
        $pass = Read-Host "Podaj hasło"
        $email = Read-Host "Podaj adres e-mail"
        $phone = Read-Host "Podaj numer telefonu"
        $dept = Read-Host "Podaj dział"
        New-ADUser -SamAccountName $sam -Name $name -AccountPassword (ConvertTo-SecureString $pass -AsPlainText -Force) -EmailAddress $email -telephoneNumber $phone -Department $dept -Enabled $true
        Write-Host "Użytkownik utworzony."
    }
    Pause
}

function Remove-User {
    $sam = Read-Host "Podaj login użytkownika do usunięcia"
    $user = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
    if ($user) {
        $confirm = Read-Host "Czy na pewno chcesz usunąć użytkownika $sam? (T/N)"
        if ($confirm -eq "T") {
            Remove-ADUser -Identity $sam
            Write-Host "Użytkownik usunięty."
        } else {
            Write-Host "Anulowano."
        }
    } else {
        Write-Host "Nie znaleziono użytkownika."
    }
    Pause
}

function Add-UserToGroup {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $fragment = Read-Host "Wpisz fragment nazwy grupy (np. 'HR' lub 'admin')"

    # Pobierz tylko grupy, których nazwa zawiera wpisany fragment (ignorując wielkość liter)
    $groups = @(Get-ADGroup -Filter * | Where-Object { $_.Name -like "*$fragment*" } | Select-Object -Property Name)

    if ($groups.Count -eq 0) {
        Write-Host "Nie znaleziono żadnych grup pasujących do podanego fragmentu."
    } else {
        Write-Host "Wybierz grupę z listy:"
        for ($i = 0; $i -lt $groups.Count; $i++) {
            Write-Host "$($i + 1). $($groups[$i].Name)"
        }
        $choice = Read-Host "Podaj numer grupy"

        if (($choice -match '^\d+$') -and ([int]$choice -ge 1) -and ([int]$choice -le $groups.Count)) {
            $selectedGroup = $groups[[int]$choice - 1].Name
            Add-ADGroupMember -Identity $selectedGroup -Members $sam
            Write-Host "Użytkownik dodany do grupy $selectedGroup."
        } else {
            Write-Host "Nieprawidłowy wybór."
        }
    }
    Pause
}

function Remove-UserFromGroup {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $fragment = Read-Host "Wpisz fragment nazwy grupy (np. 'HR' lub 'admin')"

    # Pobierz tylko grupy, których nazwa zawiera wpisany fragment (ignorując wielkość liter)
    $groups = @(Get-ADGroup -Filter * | Where-Object { $_.Name -like "*$fragment*" } | Select-Object -Property Name)

    if ($groups.Count -eq 0) {
        Write-Host "Nie znaleziono żadnych grup pasujących do podanego fragmentu."
    } else {
        Write-Host "Wybierz grupę z listy:"
        for ($i = 0; $i -lt $groups.Count; $i++) {
            Write-Host "$($i + 1). $($groups[$i].Name)"
        }
        $choice = Read-Host "Podaj numer grupy"

        if (($choice -match '^\d+$') -and ([int]$choice -ge 1) -and ([int]$choice -le $groups.Count)) {
            $selectedGroup = $groups[[int]$choice - 1].Name
            Remove-ADGroupMember -Identity $selectedGroup -Members $sam -Confirm:$false
            Write-Host "Użytkownik został usunięty z grupy $selectedGroup."
        } else {
            Write-Host "Nieprawidłowy wybór."
        }
    }
    Pause
}

function Reset-UserPassword {
    $sam = Read-Host "Podaj login użytkownika"
    $pass = Read-Host "Podaj nowe hasło"
    Set-ADAccountPassword -Identity $sam -NewPassword (ConvertTo-SecureString $pass -AsPlainText -Force)
    Write-Host "Hasło zresetowane."
    Pause
}

function Unlock-UserAccount {
    $sam = Read-Host "Podaj login użytkownika"
    Unlock-ADAccount -Identity $sam
    Write-Host "Konto odblokowane."
    Pause
}

function Check-UserGroups {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $groups = Get-ADUser -Identity $sam -Properties MemberOf | Select-Object -ExpandProperty MemberOf
    if ($groups) {
        Write-Host "Użytkownik $sam należy do następujących grup:"
        foreach ($group in $groups) {
            $groupName = (Get-ADGroup -Identity $group).Name
            Write-Host "- $groupName"
        }
    } else {
        Write-Host "Użytkownik nie należy do żadnej grupy."
    }
    Pause
}

function Show-UserLogonHistory {
    $sam = Read-Host "Podaj login użytkownika"
    $user = Get-ADUser -Identity $sam
    $dc = (Get-ADDomainController -Discover).Name
    $events = Get-WinEvent -ComputerName $dc -FilterHashtable @{
        LogName='Security'
        ID=4624
    } | Where-Object { $_.Properties[5].Value -eq $user.SamAccountName }
    $events | Select-Object TimeCreated, Properties | Format-Table
    Pause
}

function Set-UserOU {
    $sam = Read-Host "Podaj login użytkownika"
    $ou = Read-Host "Podaj ścieżkę OU (np. 'OU=Pracownicy,DC=mojadomena,DC=pl')"
    Move-ADObject -Identity (Get-ADUser -Identity $sam).DistinguishedName -TargetPath $ou
    Write-Host "Użytkownik przeniesiony do OU."
    Pause
}

function Bulk-AddToGroup {
    $csvPath = Read-Host "Podaj ścieżkę do pliku CSV z loginami"
    $group = Read-Host "Podaj nazwę grupy"
    $users = Import-Csv $csvPath
    foreach ($u in $users) {
        Add-ADGroupMember -Identity $group -Members $u.SamAccountName
        Write-Host "Dodano $($u.SamAccountName) do grupy $group"
    }
    Pause
}

function Export-UsersToCSV {
    $csvPath = Read-Host "Podaj ścieżkę do pliku docelowego CSV"
    Get-ADUser -Filter * | Select-Object Name, SamAccountName, Enabled | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Eksportowano użytkowników do $csvPath"
    Pause
}


function User-Management-Menu {
    do {
        Clear-Host
        Write-Host "      === Menu Zarządzania Użytkownikami ==="
        Write-Host "      1. Lista użytkowników (z wyborem OU)"
        Write-Host "      2. Dodawanie/modyfikacja użytkownika (e-mail, telefon, dział)"
        Write-Host "      3. Dodanie użytkownika do grupy (z filtrowaniem grup)"
        Write-Host "      4. Usunięcie użytkownika z grupy (z filtrowaniem grup)"
        Write-Host "      5. Sprawdzenie członkostwa użytkownika w grupach"
        Write-Host "      6. Zmiana hasła użytkownika"
        Write-Host "      0. Wyjście" -ForegroundColor Red
        $choice = Read-Host "Wybierz opcję (1-6 lub 0 aby wyjść)"

        switch ($choice) {
            1 { List-Users }
            2 { AddOrModify-User }
            3 { Add-UserToGroup }
            4 { Remove-UserFromGroup }
            5 { Check-UserGroups }
            6 { Change-UserPassword }
            0 { Write-Host "Wyjście " }
            default { Write-Host "Nieprawidłowy wybór." }
        }
        if ($choice -ne "0") { Pause }
    } while ($choice -ne "0")
}

function Change-UserPassword {
    $sam = Read-Host "Podaj login użytkownika (SamAccountName)"
    $newPass = Read-Host "Podaj nowe hasło"
    Set-ADAccountPassword -Identity $sam -NewPassword (ConvertTo-SecureString $newPass -AsPlainText -Force) -Reset
    Write-Host "Hasło zostało zmienione."
    Pause
}

do {
    Show-Menu
    $choice = Read-Host "Wybierz opcję (1-11 lub 0 aby zakończyć)"
    switch ($choice) {
    #    "1" { List-Users }
    #    "2" { AddOrModify-User }
    #    "3" { Remove-User }
    #    "4" { Add-UserToGroup }
    #    "5" { Remove-UserFromGroup }
    #    "6" { Reset-UserPassword }
        "1" { User-Management-Menu}   
        "7" { Unlock-UserAccount } 
        "8" { Show-UserLogonHistory }
        "9" { Set-UserOU }
        "10" { Bulk-AddToGroup }
        "11" { Export-UsersToCSV }
        "12" {User-Management-Menu }
        "0" { exit }
        default { Write-Host "Nieprawidłowy wybór."; Pause }
    }
} while ($true)

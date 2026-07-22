# pascom Client als Flatpak

Der offizielle pascom Linux-Client wird nur als Ubuntu-Tarball ausgeliefert und
läuft auf anderen Distributionen nicht zuverlässig — unter Fedora scheiterte
zuletzt vor allem die Telefonie. Dieses Repository paketiert ihn als Flatpak,
womit er distributionsunabhängig funktioniert, **inklusive Softphone-Anrufen**.

> **Kein offizielles pascom-Projekt.** Dieses Repository enthält nur
> Paketierungs-Dateien, keine pascom-Software. Der Client wird beim Build direkt
> von pascom heruntergeladen, ist proprietär und unterliegt den Bedingungen von
> pascom. "pascom" ist eine Marke der pascom GmbH & Co. KG.

## Was funktioniert

Getestet auf Fedora 44 mit GNOME (Wayland, PipeWire), Client 120.R5110. Das
Paket ist nicht auf eine Distribution oder Desktop-Umgebung zugeschnitten —
unter KDE Plasma, Xfce und Cinnamon sollte es ebenso laufen, dort aber
ungetestet. Rückmeldungen dazu sind willkommen.

| Funktion | Status |
|---|---|
| Chat, Kontakte, Präsenz | ✅ |
| Softphone-Anrufe (Audio) | ✅ ohne Aussetzer, MOS 4.2 |
| Emoji im Chat | ✅ (braucht den Fix aus diesem Repo) |
| Video und Bildschirmfreigabe | ✅ öffnet sich im Browser |
| Login über den Browser | ✅ |
| Dateien anhängen | ✅ Zugriff aufs ganze Home über den Portal-Dialog |
| Benachrichtigungen | ✅ |
| Jabra-Headset-Tasten | ❓ ungetestet, mangels Hardware |

## Installation

Voraussetzung sind `flatpak` und `flatpak-builder`:

| Distribution | Befehl |
|---|---|
| Fedora, RHEL, Rocky | `sudo dnf install flatpak flatpak-builder` |
| Debian, Ubuntu, Mint | `sudo apt install flatpak flatpak-builder` |
| Arch, Manjaro, EndeavourOS | `sudo pacman -S flatpak flatpak-builder` |
| openSUSE | `sudo zypper install flatpak flatpak-builder` |

Unter Debian und Ubuntu ist nach der Erstinstallation von Flatpak eine
Neuanmeldung nötig, damit die Anwendung im Menü auftaucht.

```bash
# Flathub-Remote und Runtime, falls noch nicht vorhanden
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08

# Bauen und installieren
git clone https://github.com/schwEDV/flatpak-pascom-client.git
cd flatpak-pascom-client
flatpak-builder --force-clean --user --install build-dir net.pascom.pascom_Client.json
```

Der Build lädt rund 95 MB von pascom und kompiliert Kerberos aus Quellcode,
das dauert ein paar Minuten. Danach steht "pascom Client" im Anwendungsmenü,
oder direkt:

```bash
flatpak run net.pascom.pascom_Client
```

Beim ersten Start öffnet der Login einen Browser — nach der Anmeldung springt
die Sitzung automatisch zurück in den Client.

## Auf eine neue Client-Version aktualisieren

Das Manifest ist bewusst auf eine feste Client-Version gepinnt, damit ein
Update bei pascom nicht unbemerkt den Build verändert. Kommt eine neue Version
heraus, meldet das der wöchentliche CI-Lauf. Zum Aktualisieren:

```bash
# neue Download-URL ermitteln
curl -s -r 0-0 -o /dev/null -D- https://my.pascom.net/update/client/cloud/linux | grep -i ^location

# Tarball ziehen und Prüfsumme bilden
curl -sLO <die-eben-ermittelte-url> && sha256sum pascom_Client-*-linux.tar.bz2
```

Beides im Manifest unter `url` und `sha256` eintragen, dann neu bauen.

## Bekannte Einschränkungen

- **Automatische Updates sind deaktiviert.** Der Client kann sich im Flatpak
  nicht selbst aktualisieren und meldet beim Start eine "nicht unterstützte
  Distribution". Neue Versionen kommen über den Weg oben.
- **Jabra-Headset-Tasten ungetestet.** Rufannahme über die Headset-Taste
  konnte mangels Gerät nicht geprüft werden. Normales Headset-Audio, auch über
  Bluetooth, ist davon nicht betroffen.
- **Unter GNOME braucht das Tray-Icon eine Erweiterung.** GNOME zeigt
  Tray-Icons nicht von sich aus; der laufende Client ist dann im Panel
  unsichtbar und taucht mangels Background-Portal auch nicht unter
  "Hintergrund-Apps" auf. Abhilfe: Paket
  `gnome-shell-extension-appindicator` installieren (heißt auf den meisten
  Distributionen so, sonst über [extensions.gnome.org](https://extensions.gnome.org/extension/615/appindicator-support/)),
  in den Erweiterungen aktivieren, neu anmelden. Betrifft alle
  Tray-Anwendungen unter GNOME.
  **KDE Plasma, Xfce und Cinnamon** zeigen das Icon direkt an.

## Weitergabe

Das gebaute Flatpak-Bundle darf **nicht weitergegeben** werden. Die
[AGB von pascom](https://www.pascom.net/download/agbDE.pdf) untersagen es
ausdrücklich, die Software Dritten "entgeltlich oder unentgeltlich zur
Verfügung zu stellen" (Abschnitt D § 3 Abs. 4 bzw. § 5 Abs. 7). Deshalb
enthält dieses Repository auch keine pascom-Software, sondern nur das Rezept,
mit dem sich jede Person den Client selbst baut — der Download kommt dabei
direkt von pascom.

Eine Anfrage an pascom, ob eine Weitergabe des Bundles bzw. eine offizielle
Bereitstellung möglich wäre, ist angedacht. Bis dahin gilt: selbst bauen.

## Technische Details

Warum das Manifest aussieht, wie es aussieht — Bibliothekskonflikte, der
Audio-Stack, die Sandbox-Berechtigungen und die Messwerte der Tests stehen in
[DEVELOPMENT.md](DEVELOPMENT.md).

Verwandtes Projekt: [foundata/oci-pascom-client](https://github.com/foundata/oci-pascom-client)
paketiert denselben Client stattdessen als Podman-Container. Deren
`DEVELOPMENT.md` ist eine sehr gründliche Analyse des Tarballs und lohnt sich
bei jedem Problem als Gegenlektüre.

## Lizenz

Die Paketierungs-Dateien in diesem Repository stehen unter der
[MIT-Lizenz](LICENSE). Das gilt **nicht** für den pascom Client selbst — der
ist proprietäre Software von pascom und wird hier weder verteilt noch neu
lizenziert.

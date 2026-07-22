# pascom Client Flatpak

Community-Flatpak-Paketierung des proprietären pascom Clients (Linux UC/Telefonie-Client) für Fedora und andere Distros.

> **Kein offizielles pascom-Projekt.** Dieses Repository enthält ausschließlich
> Paketierungs-Dateien. Die eigentliche Client-Software wird beim Build direkt von
> pascom heruntergeladen, ist proprietär und unterliegt den Lizenzbedingungen von
> pascom. "pascom" ist eine Marke der pascom GmbH & Co. KG.

## Build

```bash
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08

flatpak-builder --force-clean --user --install build-dir net.pascom.pascom_Client.json
flatpak run net.pascom.pascom_Client
```

## Warum dieses Manifest so aussieht

Das offizielle pascom-Linux-Tarball ist ein Qt6.10.1-Vollbundle mit eigenem
`AppRun`-Startskript. Es bringt eigenes `libssl.so.3`/`libcrypto.so.3` mit
(nur bis `OPENSSL_3.1.0`), aber **kein** `libcurl`. `libjabra.so.1`
(Headset-Vendor-Lib) braucht `libcurl.so.4` vom System/von der Runtime.

Das führte lokal (außerhalb von Flatpak) zu Versionskonflikten: Das
mitgelieferte `AppRun` setzt `LD_LIBRARY_PATH` so, dass das alte, mitgelieferte
`libssl.so.3` vor der System-Version geladen wird, obwohl `libcurl` gegen die
neuere System-`libssl` gelinkt ist → `OPENSSL_3.2.0`/`3.5.0`-Symbolfehler.

**Lösung im Manifest:**
- `lib/libssl.so*` und `lib/libcrypto.so*` aus dem Bundle werden beim Build
  entfernt (`rm -f` in den `build-commands`) → die Runtime-Versionen greifen.
- `pascom-apprun.sh` ersetzt das Original-`AppRun` (fester Pfad `/app/pascom_Client`
  statt `SCRIPT_DIR`-Ermittlung, kein Ubuntu-20-Sonderfall mehr, da `lib-ubuntu20/`
  im Build entfernt wird).
- **`org.freedesktop.Platform` liefert seit Jahren kein Kerberos mehr**
  (bewusst entfernt, siehe Mozilla-Bugzilla #1673437). Das Runtime-`libcurl`
  ist aber mit GSSAPI/Kerberos-Support gebaut → `libgssapi_krb5.so.2` fehlt
  zur Laufzeit. Fix: eigenes `mit-krb5`-Modul baut MIT-Kerberos 1.21.3 aus
  Quellcode und installiert die Libs nach `/app/lib`.

## Bekannte offene Punkte / TODO

- **`--device=all`** in `finish-args` ist aktuell die grobe Lösung für
  `libjabra.so.1` (Jabra-Headset via USB-HID). Ungetestet, ob ein engeres
  `--device=dri` + gezielte udev-Regel reicht.
- **Archiv-Source zeigt auf `https://my.pascom.net/update/client/cloud/linux`**
  (immer die neueste Version). Der `sha256` im Manifest ist gegen die Version
  vom 22.07.2026 gepinnt (Hash `0fdf586a...`). **Bei jedem pascom-Update muss
  der Hash manuell neu gezogen werden**, sonst schlägt der Build mit einem
  Prüfsummenfehler fehl (das ist beabsichtigtes Verhalten, kein Bug).
- **Lizenz** in `net.pascom.pascom_Client.metainfo.xml` ist aktuell nur
  `LicenseRef-proprietary` als Platzhalter — falls pascom irgendwo eine
  EULA/Lizenzdatei mitliefert, sollte die verlinkt werden.
- **`app-id: net.pascom.pascom_Client`** verwendet den Reverse-DNS-Namespace
  von pascom selbst. Falls die Distribution ohne Autorisierung von pascom
  erfolgt (z.B. eigenes Community-Repo statt Flathub), sollte das ggf. auf
  einen eigenen Namespace geändert werden (App-ID, `.desktop`-Dateiname,
  `.metainfo.xml`-Dateiname, `launchable`-Referenz betroffen).
- **GTK3-Theme** (`QT_QPA_PLATFORMTHEME=gtk3`) ungetestet, ob die
  `org.gtk.Gtk3theme`-Extension automatisch mitkommt oder explizit als
  `add-extension` deklariert werden muss.
- **StartupWMClass**: Original-Client setzt je nach X11/Wayland eine
  unterschiedliche Fensterklasse (`pascom_Client` vs. `net.pascom.pascom_Client`),
  siehe `create-starter.sh` im Original-Tarball. Aktuelle `.desktop`-Datei
  geht von der Wayland-Variante aus — ggf. unter X11 kein Icon im Panel.

## Dateien

- `net.pascom.pascom_Client.json` — Flatpak-Manifest
- `pascom-apprun.sh` — angepasstes Start-Skript (ersetzt Original-`AppRun`)
- `net.pascom.pascom_Client.desktop` — Desktop-Entry
- `net.pascom.pascom_Client.metainfo.xml` — AppStream-Metadaten

## Lizenz

Die Paketierungs-Dateien in diesem Repository stehen unter der [MIT-Lizenz](LICENSE).
Das gilt **nicht** für den pascom Client selbst — der ist proprietäre Software von pascom
und wird von diesem Repository weder verteilt noch neu lizenziert.

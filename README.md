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

## Version aktualisieren

Das Manifest pinnt eine konkrete Client-Version über die versionsspezifische
Archiv-URL (Redirect-Ziel von `https://my.pascom.net/update/client/cloud/linux`).
Aktuell: **120.R5110**. Für einen Versions-Bump:

```bash
# 1. aktuelles Redirect-Ziel ermitteln (HEAD folgt dem Redirect still, daher ranged GET)
curl -s -r 0-0 -o /dev/null -D- https://my.pascom.net/update/client/cloud/linux | grep -i ^location

# 2. Tarball ziehen und Hash bilden
curl -sLO <redirect-ziel-url> && sha256sum pascom_Client-*-linux.tar.bz2
```

`url` und `sha256` im Manifest eintragen. Der wöchentliche CI-Lauf vergleicht das
Redirect-Ziel gegen die gepinnte URL und meldet neue Versionen.

## Getestet: Softphone-Audio (PJSIP)

Das war der kritische Punkt. Ein verwandtes Projekt
([foundata/oci-pascom-client](https://github.com/foundata/oci-pascom-client),
Container-Ansatz statt Flatpak) dokumentiert, dass ein früherer nativer
Fedora-Versuch (Fedora 41, siehe [pascom-Forum-Thread](https://forum.pascom.net/t/stand-linux-client-abseits-von-ubuntu-hier-fedora/11687))
genau hier gescheitert ist: Der Client hat **zwei getrennte Audio-Pfade** —
Qt Multimedia (PulseAudio direkt, für Töne/Video) und PJSIP (ALSA **direkt**,
für Softphone-Anrufe). PJSIP erwartet das Ubuntu-ALSA-Layout; auf nativem
Fedora mit PipeWire schlug die Geräte-Enumeration fehl ("cannot find card",
"no speakers have been detected").

**Im Flatpak tritt das Problem nicht auf**, weil `org.freedesktop.Platform`
die nötige ALSA→PulseAudio-Bridge bereits mitbringt:
`libasound_module_pcm_pulse.so` plus `/etc/alsa/conf.d/99-pulseaudio-default.conf`,
das `pcm.!default` *und* `ctl.!default` auf `type pulse` setzt. PJSIP öffnet
`default` und landet damit automatisch beim Flatpak-PulseAudio-Socket
(`PULSE_SERVER=unix:/run/flatpak/pulse/native`). Das Äquivalent zu Ubuntus
`libasound2-plugins` ist also bereits da — eine eigene `asound.conf` ist nicht
nötig.

Verifiziert mit einem echten Softphone-Anruf (Client 120.R5110, Runtime 24.08,
Fedora 44 / PipeWire / Wayland): Media floss bidirektional, `codec=opus`,
268 rx / 269 tx Pakete, **0 Paketverlust in beide Richtungen**, MOS 4.21
(R-Faktor 85.5), Jitter 18,7 ms rx / 5,5 ms tx. Keine PJSIP-Fehler im Log.

## Bekannte offene Punkte / TODO

- **`--device=all`** in `finish-args` deckt zwei Dinge ab: `libjabra.so.1`
  (Jabra-Headset-Steuerung via USB-HID) und die Kamera für Videoanrufe.
  Eine Einschränkung auf `--device=dri` würde die Kamera mit abschneiden;
  der saubere Weg wäre `--device=camera` (Camera-Portal) plus eine gezielte
  udev-/HID-Freigabe für Jabra. **Beides ist hier mangels Hardware nicht
  testbar** — ohne Jabra-Headset lässt sich nicht verifizieren, was
  `libjabra` an Zugriff wirklich braucht. Bleibt deshalb bewusst grob.
  foundata hat die HID-Filterung im Container-Ansatz aus denselben Gründen
  ausgeklammert (siehe deren "Gotchas" zu Hotplug/udev/HID-Filterung) —
  plain Headset-Audio (auch Bluetooth) funktioniert laut deren Tests
  ohne HID-Passthrough, nur die Geräteknöpfe/LEDs brauchen es.
- **Lizenz** in `net.pascom.pascom_Client.metainfo.xml` ist aktuell nur
  `LicenseRef-proprietary` als Platzhalter — falls pascom irgendwo eine
  EULA/Lizenzdatei mitliefert, sollte die verlinkt werden. foundata weist
  zusätzlich darauf hin, dass das gebaute Image/Paket nicht weiterverteilt
  werden darf, da nichts Proprietäres im Repo landen soll — relevant auch
  für dieses Flatpak-Repo (Tarball wird zur Build-Zeit von pascom-Servern
  geladen, nicht im Git-Repo gespeichert; `pascom_Client-*.tar.bz2` ist
  in `.gitignore`).
- **`app-id: net.pascom.pascom_Client`** verwendet den Reverse-DNS-Namespace
  von pascom selbst. Falls die Distribution ohne Autorisierung von pascom
  erfolgt (z.B. eigenes Community-Repo statt Flathub), sollte das ggf. auf
  einen eigenen Namespace geändert werden (App-ID, `.desktop`-Dateiname,
  `.metainfo.xml`-Dateiname, `launchable`-Referenz betroffen).
- **GTK3-Theme** (`QT_QPA_PLATFORMTHEME=gtk3`) ungetestet, ob die
  `org.gtk.Gtk3theme`-Extension automatisch mitkommt oder explizit als
  `add-extension` deklariert werden muss. foundata nutzt stattdessen
  `QT_QPA_PLATFORMTHEME=xdgdesktopportal` (der Client bringt dieses Qt-Plugin
  mit) für Datei-Dialoge/Login-Browser über den Portal-Mechanismus — evtl.
  die bessere Wahl auch fürs Flatpak, statt GTK3.
- **Browser-Login (OAuth-Callback):** foundata dokumentiert, dass der
  Cloud-Login einen Browser öffnet und die Identity-Provider-Weiterleitung
  auf `http://localhost:3008/...` geht (temporärer OAuth-Callback-Server im
  Client). Im Flatpak-Sandbox-Kontext noch ungetestet, ob das mit den
  aktuellen `finish-args` (`--share=network`) funktioniert oder ob zusätzlich
  Portal-Handling für's Öffnen der Login-URL nötig ist (bei foundata über
  `xdg-desktop-portal`/`org.freedesktop.portal.OpenURI` gelöst, siehe deren
  "Browser-based login" Sektion).
- **StartupWMClass**: Original-Client setzt je nach X11/Wayland eine
  unterschiedliche Fensterklasse (`pascom_Client` vs. `net.pascom.pascom_Client`),
  von foundata unabhängig bestätigt. Aktuelle `.desktop`-Datei geht von der
  Wayland-Variante aus — ggf. unter X11 kein Icon im Panel.

## Referenz

[foundata/oci-pascom-client](https://github.com/foundata/oci-pascom-client) —
verwandtes Projekt, das denselben Client stattdessen in einem Ubuntu-24.04-
Podman-Container paketiert (bewusste Entscheidung gegen Flatpak wegen der
Bundled/System-Linking-Fragilität). Deren `DEVELOPMENT.md` ist eine sehr
detaillierte Analyse des Tarball-Inhalts, aller System-Abhängigkeiten,
Audio-/Display-/Portal-/Networking-Design-Entscheidungen und Gotchas —
lohnt sich bei jedem Problem hier als erste Anlaufstelle zum Gegenlesen,
auch wenn der Lösungsweg (Container vs. Flatpak) ein anderer ist.

## Dateien

- `net.pascom.pascom_Client.json` — Flatpak-Manifest
- `pascom-apprun.sh` — angepasstes Start-Skript (ersetzt Original-`AppRun`)
- `net.pascom.pascom_Client.desktop` — Desktop-Entry
- `net.pascom.pascom_Client.metainfo.xml` — AppStream-Metadaten

## Lizenz

Die Paketierungs-Dateien in diesem Repository stehen unter der [MIT-Lizenz](LICENSE).
Das gilt **nicht** für den pascom Client selbst — der ist proprietäre Software von pascom
und wird von diesem Repository weder verteilt noch neu lizenziert.

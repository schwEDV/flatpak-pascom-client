# Technische Details

Hintergrund zum Manifest: welche Probleme der Vendor-Tarball macht, wie sie
gelöst sind und was davon getestet wurde. Für Installation und Bedienung siehe
[README.md](README.md).

## Ausgangslage

Das offizielle pascom-Linux-Tarball ist ein Qt-6.10.1-Vollbundle mit eigenem
`AppRun`-Startskript, gebaut für Ubuntu. Es bringt eigene Kopien vieler
Bibliotheken mit — was auf anderen Distributionen zu Konflikten mit den
Systembibliotheken führt.

## Die drei Eingriffe im Manifest

### 1. OpenSSL-Konflikt

Das Bundle liefert `libssl.so.3`/`libcrypto.so.3` mit (Symbole nur bis
`OPENSSL_3.1.0`), aber **kein** `libcurl`. `libjabra.so.1` (Headset-Vendor-Lib)
braucht `libcurl.so.4` vom System. Das mitgelieferte `AppRun` setzt
`LD_LIBRARY_PATH` so, dass das alte gebundelte `libssl` vor der System-Version
geladen wird — während `libcurl` gegen die neuere System-`libssl` gelinkt ist.
Ergebnis: `OPENSSL_3.2.0`/`3.5.0`-Symbolfehler.

Lösung: `lib/libssl.so*` und `lib/libcrypto.so*` werden in den `build-commands`
gelöscht, damit die Runtime-Versionen greifen. Ebenso fliegt `lib-ubuntu20/`
raus, das im Flatpak keinen Zweck hat.

### 2. Fehlendes Kerberos

`org.freedesktop.Platform` liefert seit Jahren kein Kerberos mehr (bewusst
entfernt, siehe Mozilla-Bugzilla #1673437). Das Runtime-`libcurl` ist aber mit
GSSAPI-Support gebaut, also fehlt zur Laufzeit `libgssapi_krb5.so.2`.

Lösung: ein eigenes `mit-krb5`-Modul baut MIT Kerberos 1.21.3 aus Quellcode
nach `/app/lib`. Es muss im Manifest **vor** dem `pascom-client`-Modul stehen.

### 3. Startskript

`pascom-apprun.sh` ersetzt das Original-`AppRun`: fester Pfad
`/app/pascom_Client` statt `SCRIPT_DIR`-Ermittlung, kein Ubuntu-20-Sonderfall,
und es setzt die Qt- und fontconfig-Variablen. Es wird als
`/app/bin/pascom-apprun` installiert und ist `command` im Manifest sowie
`Exec=` in der `.desktop`-Datei.

### Fensterklasse unter X11

Der Original-Client setzt je nach Session eine andere Fensterklasse — sein
`create-starter.sh` schreibt unter Wayland `StartupWMClass=net.pascom.pascom_Client`,
unter X11 dagegen `pascom_Client`. Eine `.desktop`-Datei kann aber nur einen
Wert enthalten; passt er nicht, ordnet die Taskleiste das Fenster keiner
Anwendung zu und zeigt kein Icon.

Gelöst über `RESOURCE_NAME` im Startskript: Die Variable wertet ausschließlich
Qts xcb-Plugin aus und setzt dort den `res_name`-Teil von `WM_CLASS`. Unter
Wayland ist sie wirkungslos, kann also bedingungslos gesetzt werden. Damit
stimmt die Klasse in beiden Sitzungsarten mit der `.desktop`-Datei überein.

Nachmessen lässt sich das ohne X11-Sitzung, indem man den Client über Xwayland
startet:

```bash
flatpak run --env=QT_QPA_PLATFORM=xcb net.pascom.pascom_Client &
for id in $(xprop -root _NET_CLIENT_LIST | grep -oE "0x[0-9a-f]+"); do
  xprop -id $id WM_CLASS 2>/dev/null | sed 's/.*= //'
done | grep -i pascom
```

Ohne die Variable liefert das `"pascom_Client", "pascom"`, mit ihr
`"net.pascom.pascom_Client", "pascom"`.

Achtung beim Erweitern: Das `pascom-client`-Modul kopiert den entpackten
Tarball nach `/app/pascom_Client/`, wodurch auch die als `type: file`
eingebundenen Repo-Dateien dort landen und anschließend per `rm -f` wieder
entfernt werden. Neue Dateien müssen in diese Zeile aufgenommen werden.

## Audio: warum PJSIP im Flatpak funktioniert

Das war der kritische Punkt. Ein früherer nativer Fedora-Versuch (Fedora 41,
siehe [Forum-Thread](https://forum.pascom.net/t/stand-linux-client-abseits-von-ubuntu-hier-fedora/11687))
scheiterte genau hier, und foundata dokumentiert dasselbe für den
Container-Ansatz.

Der Client hat **zwei getrennte Audio-Pfade**:

- **Qt Multimedia** → PulseAudio direkt, für Töne und Video
- **PJSIP** → ALSA **direkt**, für Softphone-Anrufe

PJSIP erwartet das Ubuntu-ALSA-Layout. Auf nativem Fedora mit PipeWire schlug
die Geräte-Enumeration fehl (`cannot find card`, `no speakers have been
detected`). Dass der Client "pulse" als Gerät anzeigt, beweist nur Pfad 1 —
für Pfad 2 sagt es nichts.

**Im Flatpak tritt das Problem nicht auf**, weil `org.freedesktop.Platform` die
nötige ALSA→PulseAudio-Bridge bereits mitbringt: `libasound_module_pcm_pulse.so`
plus `/etc/alsa/conf.d/99-pulseaudio-default.conf`, das `pcm.!default` *und*
`ctl.!default` auf `type pulse` setzt. PJSIP öffnet `default` und landet damit
automatisch beim Flatpak-PulseAudio-Socket
(`PULSE_SERVER=unix:/run/flatpak/pulse/native`). Das Äquivalent zu Ubuntus
`libasound2-plugins` ist also schon da — eine eigene `asound.conf` braucht es
nicht.

Verifiziert mit einem echten Softphone-Anruf (Client 120.R5110, Runtime 24.08,
Fedora 44 / PipeWire / Wayland). Aus `_stats.call` im Log:

```
codec=opus  rtcp.rx.pkt=268  rtcp.tx.pkt=269  rtcp.rx.loss=0  rtcp.tx.lost=0
rtcp.rx.mos=4.21  rtcp.tx.mos=4.21  r_factor=85.5  emodel.delay_ms=108
```

Keine PJSIP-Fehler im Log, Media floss bidirektional.

## Video und Bildschirmfreigabe laufen im Browser

Beides funktioniert, aber **nicht in der Sandbox**: Der Client öffnet
Konferenzen im Host-Browser, die Übertragung ist eine WebRTC-Webanwendung.
Während eines laufenden Calls hatte kein Prozess `/dev/video*` geöffnet; im Log
erscheinen `publishCameraStreamModel` und `publishScreenStreamModel` jeweils mit
`peer connection state: connected`.

Konsequenz: Kamera- und ScreenCast-Portal-Zugriff der Sandbox sind für
Videoanrufe irrelevant, der Browser bringt seine eigenen Berechtigungen mit.
`--filesystem=xdg-run/pipewire-0` bleibt nur drin, weil es die Qt-Startmeldung
`Failed to connect to pipewire instance` beseitigt — funktional hängt daran
nichts Nachgewiesenes.

## Qt-Platformtheme: `xdgdesktopportal` statt `gtk3`

Die Sandbox hat nur `--filesystem=xdg-download`. Der GTK3-Dialog läuft *innerhalb*
der Sandbox und würde deshalb beim Anhängen einer Datei nur den Downloads-Ordner
anbieten. Der Portal-Dialog läuft auf dem Host und gibt über das Document-Portal
gezielt die ausgewählte Datei frei — ohne die Sandbox aufzubohren.

Zusätzlich liest das Portal-Theme `org.freedesktop.appearance` (Color-Scheme,
Accent-Color) vom Host. Die `org.gtk.Gtk3theme`-Extension ist nicht gemountet,
das Host-Theme wäre in der Sandbox also ohnehin nicht verfügbar gewesen.

## Emoji: COLRv1 vs. Bitmap

Fedora liefert "Noto Color Emoji" als COLRv1-Datei (`Noto-COLRv1.ttf`). Flatpak
blendet die Host-Fonts unter `/run/host/fonts` ein, wo fontconfig sie gegenüber
der Bitmap-Variante der Runtime bevorzugt. Das Qt des Clients rastert COLRv1
nicht — und weil der Font die Glyphe als vorhanden meldet, greift auch kein
Fallback. Im Chat blieb schlicht *nichts* stehen, nicht einmal Ersatzkästchen.

`fontconfig-emoji.conf` sortiert die COLRv1-Datei per `rejectfont` aus und wird
über `FONTCONFIG_FILE` im Startskript aktiviert. Damit greift
`NotoColorEmoji.ttf` aus der Runtime. Der Glob braucht einen echten Pfad-Präfix;
ein führendes `*` matcht in fontconfig nicht über Verzeichnisgrenzen.

## Sandbox-Berechtigungen

| Berechtigung | Begründung |
|---|---|
| `--socket=pulseaudio` | Audio inkl. PJSIP über die ALSA-Bridge |
| `--socket=wayland`, `--socket=x11` | Anzeige |
| `--share=network` | Server-Verbindung, OAuth-Callback auf `localhost:3008` |
| `--share=ipc` | Singleton-Erkennung des Clients |
| `--device=all` | nur noch wegen `libjabra.so.1` (USB-HID) |
| `--filesystem=xdg-download` | Standard-Ablage für Downloads |
| `--filesystem=xdg-run/pipewire-0` | unterdrückt eine Qt-Startmeldung, sonst ohne Funktion |
| `--talk-name=org.freedesktop.Notifications` | Benachrichtigungen |
| `--talk-name=org.kde.StatusNotifierWatcher` | Tray-Icon (siehe unten) |
| `--talk-name=org.freedesktop.ScreenSaver`, `org.gnome.ScreenSaver` | Bildschirmsperre während Videoanrufen verhindern |
| `--system-talk-name=org.freedesktop.login1` | `PrepareForSleep`, um nach dem Standby die SIP-Registrierung wiederherzustellen |

Die Liste der D-Bus-Dienste ist vollständig: Im Binary tauchen genau
`org.freedesktop.login1`, `org.freedesktop.Notifications`,
`org.freedesktop.ScreenSaver` und `org.gnome.ScreenSaver` auf, dazu der
StatusNotifierWatcher aus den Qt-Bibliotheken. `org.freedesktop.secrets` wird
nicht verwendet. `com.canonical.AppMenu.Registrar` taucht nur in `libQt6Gui`
auf, also in Qts generischer Implementierung: Der Client selbst enthält weder
`QMenuBar` noch `dbusmenu`-Aufrufe, er ist eine reine QML-Anwendung ohne
Menüleiste. Das globale Menü ist damit gegenstandslos — unabhängig von der
Desktop-Umgebung, nicht nur unter GNOME.

Nichts an der Paketierung ist auf eine bestimmte Desktop-Umgebung
zugeschnitten: `org.kde.StatusNotifierWatcher` ist unter KDE der native
Tray-Dienst (dort ohne Zusatz-Extension), `org.freedesktop.ScreenSaver`
implementiert Plasma ebenfalls, und `xdgdesktopportal` liefert über
`xdg-desktop-portal-kde` native Plasma-Dialoge. Getestet ist bislang aber nur
GNOME.

Ermitteln lässt sich das direkt am entpackten Build:

```bash
strings -n 8 build-dir/files/pascom_Client/pascom_Client \
  | grep -oE "org\.(freedesktop|gnome|kde)\.[A-Za-z0-9.]+" | sort -u
```

Ohne `org.kde.StatusNotifierWatcher` erscheint **kein Tray-Icon**, und zwar
ohne jede Fehlermeldung: Qt meldet das Item beim Watcher an, der Aufruf wird
von der Bus-Policy der Sandbox stillschweigend verworfen, die Anwendung läuft
weiter. Das sieht wie ein GNOME-Problem aus, ist aber eines der Paketierung.
Prüfen lässt es sich am Watcher selbst:

```bash
gdbus call --session --dest org.kde.StatusNotifierWatcher \
  --object-path /StatusNotifierWatcher \
  --method org.freedesktop.DBus.Properties.Get \
    org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems
```

Die zurückgegebenen Bus-Namen lassen sich über `busctl --user status <name>`
einem Prozess zuordnen — bei Flatpak-Anwendungen ist das der zugehörige
`xdg-dbus-proxy`, erkennbar an der Startzeit. Zusätzlich muss unter GNOME die
AppIndicator-Extension laufen, sonst gibt es gar keinen Watcher.

`--device=all` ist die gröbste Stelle. Der saubere Weg wäre eine gezielte
udev-/HID-Freigabe, das lässt sich ohne Jabra-Hardware aber nicht verifizieren.
foundata hat die HID-Filterung im Container-Ansatz aus denselben Gründen
ausgeklammert; plain Headset-Audio funktioniert laut deren Tests ohne
HID-Passthrough, nur Geräteknöpfe und LEDs brauchen es.

## Diagnose

Der Client loggt nach stdout **und** in eine SQLite-DB unter
`~/.var/app/net.pascom.pascom_Client/data/pascom Client/log.db` (Tabelle `log`;
`timestamp` als ms-Epoch, `level` 1=Warn/2=Error/4=Info). Die DB enthält auch
die Historie über Neustarts hinweg. Nützliche Kategorien:

- `service.DesktopAudioController` — Audio-Geräteauswahl
- `service.MdSoftphone`, `controller.SoftPhoneController`, `pc.MdAccount` — SIP
- `_stats.call` — RTCP-Statistik pro Anruf
- `publishCameraStreamModel`, `publishScreenStreamModel` — WebRTC

**Singleton beachten:** Der Client erkennt eine laufende Instanz per IPC und
aktiviert nur deren Fenster (`main: Client is already running`). Nach einem
Rebuild startet ein `flatpak run` sonst noch den alten Build — vorher
`flatpak kill net.pascom.pascom_Client`.

## Versions-Pinning und CI

Die Source-URL im Manifest zeigt auf das versionsspezifische Release-Archiv
(`https://download.pascom.net/release-archive/client/cloud/pascom_Client-<version>-linux.tar.bz2`),
nicht auf den "immer neueste Version"-Redirect. Sonst wäre der Build bei jedem
stillen pascom-Update an der Prüfsumme gescheitert.

Das Redirect-Ziel ist nur bei einem ranged GET sichtbar — ein normales `curl -I`
folgt ihm still und zeigt keinen `Location`-Header.

Der GitHub-Actions-Workflow baut bei Push und PR und vergleicht zusätzlich
wöchentlich das aktuelle Redirect-Ziel gegen die gepinnte URL. Weicht es ab,
schlägt der Job mit dem Hinweis fehl, dass `url` und `sha256` aktualisiert
werden müssen.

## Entschieden: App-ID bleibt `net.pascom.pascom_Client`

Die App-ID nutzt den Reverse-DNS-Namespace von pascom selbst. Das wäre ein
Problem, sobald gebaute Pakete verteilt würden — passiert aber nicht, siehe
Abschnitt zur Weitergabe in der [README](README.md#weitergabe): Jede Person
baut selbst, der Download kommt von pascom. Bis sich daran etwas ändert oder
pascom sich anders äußert, bleibt die ID.

Sollte sie doch gewechselt werden, sind vier Stellen gleichzeitig betroffen:
`app-id` im Manifest, Dateiname und `Icon=` der `.desktop`, Dateiname und
`<id>` der `.metainfo.xml` sowie die `<launchable>`-Referenz. Nebenbei
verschwände damit der einzige verbliebene `appstreamcli`-Hinweis
(Großbuchstabe in der ID), der aktuell bewusst in Kauf genommen wird.

## Offene Punkte

- **`--device=all` eingrenzen** — braucht ein Jabra-Headset zum Verifizieren,
  siehe Abschnitt zu den Sandbox-Berechtigungen.

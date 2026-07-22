#!/usr/bin/env bash
# Angepasste Variante des originalen AppRun-Skripts von pascom.
# Unterschiede zum Original:
# - fester Pfad /app/pascom_Client statt SCRIPT_DIR-Ermittlung
# - kein Ubuntu-20-Sonderfall mehr (lib-ubuntu20 wurde im Manifest entfernt)
# - GIO_LAUNCH_DESKTOP-Erkennung bleibt, da vom Runtime-Root bereitgestellt

APP_DIR="/app/pascom_Client"

export LD_LIBRARY_PATH="${APP_DIR}/lib${LD_LIBRARY_PATH+:${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH}}"
export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-xdgdesktopportal}"
export QT_PLATFORMTHEME="${QT_PLATFORMTHEME:-xdgdesktopportal}"

if [[ ! ${GIO_LAUNCH_DESKTOP:-} ]]; then
  GIO_LAUNCH_DESKTOP=/usr/lib/$(uname -m)-linux-gnu/glib-2.0/gio-launch-desktop
  [[ -e $GIO_LAUNCH_DESKTOP ]] || GIO_LAUNCH_DESKTOP=/usr/lib/glib-2.0/gio-launch-desktop
  export GIO_LAUNCH_DESKTOP
fi

exec "${APP_DIR}/pascom_Client" "$@"

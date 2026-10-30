REMOVAL AND RECOVERY / УДАЛЕНИЕ И ВОССТАНОВЛЕНИЕ
================================================

What the installer changes (and nothing else) / Что именно меняет установщик
---------------------------------------------------------------------------
  * the package labwc-taskbar-workspace (labwc mode only). It does NOT overwrite the stock binary:
    the original /usr/bin/labwc is kept as /usr/bin/labwc.distrib (dpkg diversion) and "apt-mark hold labwc"
    is set so a labwc update cannot replace it behind your back
  * ~/.config/labwc/{rc.xml,menu.xml,autostart,themerc-override}   (first-run copies: *.orig-ws,
    files created by the installer have a *.created-by-ws marker)
  * ~/.local/bin/ws-*.sh, ~/.local/share/icons/ws-*.svg, ~/.config/ws-switcher/
  * xfce4-panel: two plugins next to the application menu (workspace button + window-menu button); the pager
    plugin is removed. Copy of the panel settings from before the change:
    ~/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml.orig-ws
  * xfwm4 mode: the number of workspaces (the old value is stored in ~/.config/ws-switcher/)
  * packages wtype / xdotool / xfce4-genmon-plugin stay installed after removal (harmless, remove them by hand if you want)

1. NORMAL REMOVAL / ОБЫЧНОЕ УДАЛЕНИЕ
------------------------------------
  cd ws-switcher                  # the folder of the bundle (works offline)
  bash install.sh --uninstall
  # then log out and in, or reboot.  Check:  bash install.sh --status

  Каждый шаг удаления независим: если один не удался, остальные всё равно выполняются.
  Не вернётся только плагин pager на панели (добавьте его вручную: ПКМ по панели -> Panel -> Items).

2. THE DESKTOP DOES NOT START AFTER AN UPDATE / РАБОЧИЙ СТОЛ НЕ ЗАГРУЖАЕТСЯ ПОСЛЕ ОБНОВЛЕНИЯ
-------------------------------------------------------------------------------------------
  Open a text console (Ctrl+Alt+F3) or log in over SSH, then:

    sudo apt-mark unhold labwc
    sudo apt-get remove -y labwc-taskbar-workspace || sudo dpkg -r labwc-taskbar-workspace
    sudo reboot

  If /usr/bin/labwc is missing afterwards:        sudo apt-get install --reinstall labwc
  If the diversion is still listed (dpkg-divert --list /usr/bin/labwc):
                                                  sudo dpkg-divert --package labwc-taskbar-workspace --remove --rename /usr/bin/labwc
  Last resort without the package system:         sudo cp /usr/bin/labwc.distrib /usr/bin/labwc

  Still no desktop?  Test with the stock labwc configuration (your files are only renamed, not deleted):
    mv ~/.config/labwc ~/.config/labwc.off ; sudo reboot
  If it starts, restore the configuration with the backups (section 4) instead of the .off folder.

3. THE PANEL BUTTONS ARE BLANK, BROKEN OR THE PANEL MISBEHAVES / КНОПКИ НА ПАНЕЛИ ПУСТЫЕ ИЛИ ПАНЕЛЬ ВЕДЁТ СЕБЯ СТРАННО
--------------------------------------------------------------------------------------------------------------
  * Buttons blank after an update of xfce4-genmon-plugin (newer versions keep their settings elsewhere):
        bash install.sh --config-only
  * Remove only the buttons: right click on the panel -> Panel -> Panel Preferences -> Items, select the
    "Generic Monitor" and the "Launcher" that sit next to the application menu, click "-".
  * Restore the whole panel layout from before the installation (later panel changes are lost):
        xfce4-panel -q ; pkill xfconfd
        cd ~/.config/xfce4/xfconf/xfce-perchannel-xml
        cp xfce4-panel.xml.orig-ws xfce4-panel.xml
        xfce4-panel &

4. MANUAL REMOVAL (install.sh is lost or broken) / РУЧНОЕ УДАЛЕНИЕ (установщика нет)
------------------------------------------------------------------------------------
  # package (labwc mode)
  sudo apt-mark unhold labwc
  sudo apt-get remove -y labwc-taskbar-workspace || sudo dpkg -r labwc-taskbar-workspace

  # configuration backups
  cd ~/.config/labwc
  for f in rc.xml menu.xml autostart themerc-override; do
      if [ -e "$f.orig-ws" ]; then mv -f "$f.orig-ws" "$f"
      elif [ -e "$f.created-by-ws" ]; then rm -f "$f" "$f.created-by-ws"; fi
  done

  # scripts and icons
  rm -f ~/.local/bin/ws-set.sh ~/.local/bin/ws-click.sh ~/.local/bin/ws-genmon.sh ~/.local/bin/ws-move-click.sh
  rm -f ~/.local/share/icons/ws-1.svg ~/.local/share/icons/ws-2.svg ~/.local/share/icons/ws-move.svg
  rm -rf ~/.config/ws-switcher

  # panel buttons: see section 3;   xfwm4 mode: set the number of workspaces back in
  # Settings -> Workspace Settings

5. AFTER SYSTEM UPDATES / ПОСЛЕ ОБНОВЛЕНИЙ СИСТЕМЫ
-------------------------------------------------
  * labwc is held. To update labwc (or if apt reports conflicts with libwlroots): remove our package first
    (section 1), run  sudo apt full-upgrade, then check:  labwc --version.  The patch is built for 0.9.8 only,
    install.sh refuses to run with any other labwc version - for a newer one rebuild the patch from source/
    or simply stay on the stock labwc (one workspace button less, everything else works).
  * If a system tool changes its syntax and a button stops working, nothing else is affected: the buttons are
    tiny scripts (wtype / xdotool / xfconf-query). Use  bash install.sh --status  and either fix the script in
    ~/.local/bin or remove the buttons (section 3).
  * The configuration the installer added to rc.xml / menu.xml uses ordinary labwc options; if a future labwc
    rejects them, labwc prints the line to its log and the stock behaviour stays.

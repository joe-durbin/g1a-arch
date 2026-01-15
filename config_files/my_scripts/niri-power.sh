 #!/bin/bash

# --- Configuration ---
# Updated --lines to 6 to accommodate the new options
FUZZEL_OPTS="--dmenu
             --width 15
             --lines 5
             --horizontal-pad 10
             --vertical-pad 10
             --inner-pad 5"

# --- Define Options ---
# Added Lock and Hibernate to the list
OPTIONS="Lock\nReboot\nShutdown\nSuspended\nHibernate"

# --- Execute ---
SELECTION=$(printf "$OPTIONS" | fuzzel $FUZZEL_OPTS)

case "$SELECTION" in
    Lock)
        swaylock
        ;;
    Reboot)
        systemctl reboot
        ;;
    Shutdown)
        systemctl poweroff
        ;;
    Suspend)
        systemctl suspend
        ;;
    Hibernate)
        systemctl hibernate
        ;;
    *)
        exit 0
        ;;
esac

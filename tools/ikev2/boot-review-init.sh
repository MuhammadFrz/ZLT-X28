#!/bin/sh /etc/rc.common
START=17
STOP=11
USE_PROCD=1
start_service() {
 [ -f /data/home-ikev2/boot-review/armed ] || return 0
 [ -f /data/home-ikev2/full-review/armed ] || return 0
 procd_open_instance
 procd_set_param command /bin/sh /data/home-ikev2/boot-review/watchdog.sh
 procd_close_instance
}

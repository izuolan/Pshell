#! /bin/sh
killall hans
nohup hans -s $VIP_GATE -p $PASSWORD -f >/dev/null 2>&1 &
ptunnel -x $PASSWORD
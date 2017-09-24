#!/bin/sh
killall hans
nohup hans -p $PASSWORD -c $IP -f >/dev/null 2>&1 &
ptunnel -p $IP -lp $MIDDLE_PORT -da 127.0.0.1 -dp $SSH_PORT -x $PASSWORD
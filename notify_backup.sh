#!/bin/bash

VIP=10.40.12.104
DEV=eth1
MYSQL_PORT=3306
BASEDIR=/etc/keepalived/script

LOG=${BASEDIR}/notify_backup.log
echo >> $LOG
function mylog()
{
    LOGCONTENT=$1
    echo `date +%Y%m%d" "%H":"%M":"%S`" "${LOGCONTENT} >> $LOG 2>&1
}
mylog "notify backup begin..."

# when starting keepalived, this vrrp instance will entering backup state first, then entering master state, skip deleting ip
KA_START_TIME=`stat /var/run/keepalived.pid | grep Modify | awk '{print $2" "$3}'`
KA_START_TIMESTAMP=`date -d "${KA_START_TIME}" +%s`
NOW_TIMESTAMP=`date +%s`
KA_AGE=$(expr ${NOW_TIMESTAMP} - ${KA_START_TIMESTAMP})
if [ ${KA_AGE} -lt 60 ]; then
    exit 0
fi

# when this mysql is master, but this vrrp entering backup state for some resons, skip deleteing ip
</dev/tcp/127.0.0.1/${MYSQL_PORT}
RETURN=$?
if [ $RETURN -eq 0 ]; then
    exit 0
fi

mylog "del vip"
/sbin/ip addr del ${VIP}/24 dev ${DEV} >> $LOG 2>&1

mylog "notify backup end."

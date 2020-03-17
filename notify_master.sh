#!/bin/bash

MANAGERDB_CONN="-h 10.40.12.21 -P 3306 -D dbfailover -u user1 -ppassword1"
SLAVEDB_CONN="-u user1 -ppassword1"
MASTER_IP=10.40.12.101
MYSQL_PORT=3306
DB_NAME=mydb1
VIP=10.40.12.104
GATEWAY=10.40.12.254
SLAVE_RELAY_TIMEOUT=600
DEV=eth1
BASEDIR=/etc/keepalived/script

LOG=${BASEDIR}/notify_master.log
STATUSLOG=${BASEDIR}/slave_status.log.`date +%Y%m%d"_"%H%M%S`
echo >> $LOG

function mylog()
{
    LOGCONTENT=$1
    echo `date +%Y%m%d" "%H":"%M":"%S`" "${LOGCONTENT} >> $LOG 2>&1
}
mylog "notify master begin..."

function exec_sql()
{
    if [ $# -ne 2 ]; then
        return 1
    fi
    DBSRV=$1
    SQL=$2
    TMPFILE=/etc/keepalived/script/tmpResult.log
    if [ ${DBSRV}"x" = dbmanagerx ]; then
        mysql ${MANAGERDB_CONN} -e "$SQL" > $TMPFILE 2>&1
    elif [ ${DBSRV}"x" = dbslavex ]; then
        mysql ${SLAVEDB_CONN} -e "$SQL" > $TMPFILE 2>&1
    else
        return 2
    fi
    sed -i '/RESULTLINE/!d' $TMPFILE
    if [ `wc -l < $TMPFILE` -ne 1 ]; then
        return 3
    else
        RESULT=`cat $TMPFILE |cut -d "#" -f 2`
        echo $RESULT
    fi
}

function get_slave_log_pos_lag()
{
    TMPFILE=/etc/keepalived/script/tmpResult.log
    mysql ${SLAVEDB_CONN} -e "show slave status\G" > $TMPFILE 2>&1
    sed -i '/Master_Log_File/!d' $TMPFILE
    READ_LOG=`cat $TMPFILE | awk -F ":" '{print $2}' | sed -n '1p'`
    EXEC_LOG=`cat $TMPFILE | awk -F ":" '{print $2}' | sed -n '2p'`
    if [ ${READ_LOG}"x" = ${EXEC_LOG}"x" ]; then 
        mysql ${SLAVEDB_CONN} -e "show slave status\G" > $TMPFILE 2>&1
        sed -i '/Read_Master_Log_Pos/!d' $TMPFILE
        READ_POS=`cat $TMPFILE | cut -d ":" -f 2`
        mysql ${SLAVEDB_CONN} -e "show slave status\G" > $TMPFILE 2>&1
        sed -i '/Exec_Master_Log_Pos/!d' $TMPFILE
        EXEC_POS=`cat $TMPFILE | cut -d ":" -f 2`
        RESULT=`expr ${READ_POS} - ${EXEC_POS}`
        echo $RESULT
    else
        echo 1000000
    fi
}

# 1. master is offline
# aviod exec this script when startup keepalived on this slave server before master server
</dev/tcp/${MASTER_IP}/${MYSQL_PORT}
RETURN=$?
if [ $RETURN -ne 0 ]; then
    mylog "1. master is offline"
else
    mylog "abort! master is online"
    exit 1
fi


# 2 no data exists within 120 seconds
SQL="select concat('RESULTLINE#',count(*)) col1 from master_arbit_info where db_name='${DB_NAME}' and create_time > DATE_SUB(now(),INTERVAL 120 second)"
RESULT=`exec_sql dbmanager "${SQL}"`
RETURN=$?
if [ $RETURN -eq 0 ]; then
    if [ $RESULT -eq 0 ]; then
        mylog "2. master_arbit_info records within 120 seconds: $RESULT"
    else
        mylog "abort! master_arbit_info records within 120 seconds: $RESULT"
        exit 1
    fi
else
    mylog "abort! func execute failed, return: $RETURN"
    exit 1
fi

# 3. data exists within 180 seconds
SQL="select concat('RESULTLINE#',count(*)) col1 from master_arbit_info where db_name='${DB_NAME}' and create_time > DATE_SUB(now(),INTERVAL 180 second)"
RESULT=`exec_sql dbmanager "${SQL}"`
RETURN=$?
if [ $RETURN -eq 0 ]; then
    if [[ $RESULT -gt 0 ]]; then
        mylog "3. master_arbit_info records within 180 seconds: $RESULT"
    else
        mylog "abort! master_arbit_info records within 180 seconds: $RESULT"
        exit 1
    fi
else
    mylog "abort! func execute failed, return: $RETURN"
    exit 1
fi


# 4. last semi status is on
SQL="select concat('RESULTLINE#',semi_status) col1 from master_arbit_info where id=(select max(id) from master_arbit_info where db_name='${DB_NAME}')"
RESULT=`exec_sql dbmanager "${SQL}"`
RETURN=$?
if [ $RETURN -eq 0 ]; then
    if [ $RESULT -eq 1 ]; then
        mylog "4. master_arbit_info last semi status: $RESULT"
    else
        mylog "abort! master_arbit_info last semi status: $RESULT"
        exit 1
    fi
else
    mylog "abort! func execute failed, return: $RETURN"
    exit 1
fi


# 5. heartbeat job run normally
SQL="select concat('RESULTLINE#',unix_timestamp(create_time) - unix_timestamp(heartbeat_time)) col1 from master_arbit_info \
where id = (select max(id) from master_arbit_info where db_name='${DB_NAME}')"
RESULT=`exec_sql dbmanager "${SQL}"`
RETURN=$?
if [ $RETURN -eq 0 ]; then
    if [[ $RESULT -le 2 ]] && [[ $RESULT -ge 0 ]]; then
        mylog "5. master_arbit_info last heartbeat_time after create_time: $RESULT"
    else
        mylog "abort! master_arbit_info last heartbeat_time after create_time: $RESULT"
        exit 1
    fi
else
    mylog "abort! func execute failed, return: $RETURN"
    exit 1
fi


# 6. check slave exec log lag behind read log
RESULT=`get_slave_log_pos_lag`
TIME_ELAPSED=0
while [[ $RESULT -ne 0 ]] && [[ ${TIME_ELAPSED} -le ${SLAVE_RELAY_TIMEOUT} ]]
do
    sleep 3
    RESULT=`get_slave_log_pos_lag`
    TIME_ELAPSED=`expr ${TIME_ELAPSED} + 3`
done
if [ $RETURN -eq 0 ]; then
    mylog "6. slave exec log lag behind read log: $RETURN"
else
    mylog "abort! slave exec log lag behind read log: $RETURN"
    exit 1
fi

# 7. check heartbeat lag between master and salve
SQL="select concat('RESULTLINE#',unix_timestamp(heartbeat_time)) col1  from master_arbit_info where id = (select max(id) from master_arbit_info where db_name='${DB_NAME}')"
MASTER_HEARTBEAT=`exec_sql dbmanager "${SQL}"`
MASTER_RETURN=$?
if [ ${MASTER_RETURN} -ne 0 ]; then
    mylog "abort! master_heartbeat func execute failed, return: ${MASTER_RETURN}"
    exit 1
fi
SQL="select concat('RESULTLINE#',unix_timestamp(create_time)) col1 from dbadmin.heartbeat where id=1"
SLAVE_HEARTBEAT=`exec_sql dbslave "${SQL}"`
SLAVE_RETURN=$?
if [ ${SLAVE_RETURN} -ne 0 ]; then
    mylog "abort! slave_heartbeat func execute failed, return: ${SLAVE_RETURN}"
    exit 1
fi
LAG=`expr ${SLAVE_HEARTBEAT} - ${MASTER_HEARTBEAT}`
if [[ $LAG -le 1 ]] && [[ $LAG -ge 0 ]]; then
    mylog "7. heartbeat lag between master and slave: ${LAG}"
else
    mylog "abort! heartbeat lag between master and slave: ${LAG}"
    exit 1
fi

mysql ${SLAVEDB_CONN} -e "show slave status\G" > ${STATUSLOG} 2>&1

mylog "switch to master"
mysql ${SLAVEDB_CONN} -e "stop slave; reset slave all; reset master; set global event_scheduler=1; set global read_only=0; " >> $LOG 2>&1

mylog "add vip"
/sbin/ip addr add ${VIP}/24 dev ${DEV} >> $LOG 2>&1
arping -I ${DEV} -c 1 ${VIP} >> $LOG 2>&1
arping -I ${DEV} -c 1 -s ${VIP} ${GATEWAY} >> $LOG 2>&1
mylog "notify master end"

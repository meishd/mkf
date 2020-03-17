# -*- coding: utf-8 -*-

import pymysql.cursors
from DBUtils.PooledDB import PooledDB
from apscheduler.schedulers.blocking import BlockingScheduler
import threading
import time
import logging

logging.basicConfig(level = logging.WARN,format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

g_pool_dic = {}
g_dbname_list = []

managerdb_pool = PooledDB(pymysql,
                            maxconnections=100,
                            mincached=10,
                            maxcached=50,
                            blocking=True,
                            host='dbmanater_ip',
                            port=3306,
                            db='dbfailover',
                            user='user1',
                            passwd='password1',
                            setsession=[])

def check_targetdb_pool():
    # check pool in g_pool_dic
    for db_name in list(g_pool_dic.keys()):
        try:
            connect = g_pool_dic[db_name].connection()
            cursor = connect.cursor()
            sql = "select count(*) from dbadmin.heartbeat where id=1"
            cursor.execute(sql)
            rows=cursor.fetchall()
            cursor.close()
            connect.close()
        except:
            del g_pool_dic[db_name]
    # add pool to g_pool_dic which is not in
    connect = managerdb_pool.connection()
    cursor = connect.cursor()
    sql = "select db_name,ip,port,user_name from master_info where status=0"
    cursor.execute(sql)
    rows = cursor.fetchall()
    for row in rows:
        if not g_pool_dic.get(row[0]):
            try:
                g_pool_dic[row[0]] = PooledDB(pymysql,
                                             maxconnections=3,
                                             mincached=1,
                                             maxcached=1,
                                             blocking=True,
                                             host=row[1],
                                             port=row[2],
                                             db='dbadmin',
                                             user=row[3],
                                             passwd='lbadmin',
                                             setsession=[])
            except:
                logger.warning("set db connection pool of " + row[0] + " failed")
    cursor.close()
    connect.close()


def get_master_arbit_info(target_db):
    if g_pool_dic.get(target_db):
        pool_target = g_pool_dic[target_db]
        try:
            connect = pool_target.connection()
            cursor = connect.cursor()
            # get semi status
            sql = "show status like 'Rpl_semi_sync_master_status'"
            cursor.execute(sql)
            semi_status_cursor = cursor.fetchall()
            if len(semi_status_cursor) == 1:
                semi_status_row = semi_status_cursor[0]
                semi_status = semi_status_row[1]
                if semi_status == 'ON':
                    semi_status = 1
                elif semi_status == 'OFF':
                    semi_status = 0
                else:
                    semi_status = 2
            else:
                print("semi_status_cursor get more than 1 row")
                semi_status = 3
            # get heartbeat_time and current_time
            sql = "select date_format(create_time,'%Y-%m-%d %H:%i:%s') heartbeat_time,date_format(now(),'%Y-%m-%d %H:%i:%s') create_time from heartbeat where id=1"
            cursor.execute(sql)
            rows = cursor.fetchall()
            heartbeat_time = rows[0][0]
            create_time = rows[0][1]
            cursor.close()
            connect.close()
            master_arbit_info_list = [target_db, semi_status, heartbeat_time, create_time]
            return master_arbit_info_list
        except:
            pass

def set_master_arbit_info(master_arbit_info_list):
    connect = managerdb_pool.connection()
    cursor = connect.cursor()
    sql = "insert into master_arbit_info(db_name,semi_status,heartbeat_time,create_time) values (%s, %s, %s, %s)"
    cursor.execute(sql, master_arbit_info_list)
    connect.commit()
    cursor.close()
    connect.close()

def get_master_dbname():
    connect = managerdb_pool.connection()
    cursor = connect.cursor()
    sql = "select db_name from master_info where status=0"
    cursor.execute(sql)
    rows = cursor.fetchall()
    g_dbname_list.clear()
    for row in rows:
        g_dbname_list.append(row[0])
    cursor.close()
    connect.close()

def load_master_arbit_info():
    for dbname in g_dbname_list:
        master_arbit_info = get_master_arbit_info(dbname)
        if master_arbit_info:
            set_master_arbit_info(master_arbit_info)

if __name__ == "__main__":
    scheduler = BlockingScheduler()
    scheduler.add_job(get_master_dbname, 'interval', seconds=10, id='get_master_dbname', max_instances=10,coalesce=True, misfire_grace_time=30)
    scheduler.add_job(check_targetdb_pool, 'interval', seconds=10, id='check_targetdb_pool',max_instances=100,coalesce=True,misfire_grace_time=30)
    scheduler.add_job(load_master_arbit_info,'interval', seconds=1, id='load_master_arbit_info',max_instances=100,coalesce=True,misfire_grace_time=30);
    scheduler.start()

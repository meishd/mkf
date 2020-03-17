项目名称：mkf (mysql keepalived failover)

部署步骤：

1.创建第三方mysql库dbfailover
执行脚本install_dbfailover.sql
将mkf需要维护的主库信息初始化至master_info

2.在被管理的主库执行install_dbtarget.sql

3.部署python数据抽取程序(可以和dbfailover同服务器)
安装python3环境
requirement:
PyMySQL==0.9.3
DBUtils==1.3
APScheduler==3.6.3

设置mkf.py中的dbmanager连接池信息：
managerdb_pool = PooledDB(host='dbmanater_ip',user='user1',passwd='password1')

启动脚本：
python mkf.py

4.在被管理的mysql主库指向脚本install_dbtarget.sql

5.在被管理的mysql主从服务器上部署keepalived
主从配置文件分别用：keepalived_master.conf、keepalived_slave.conf，需设置主从节点的物理IP
主脚本：notify_backup.sh，需设置文件头的环境变量
从脚本：notify_master.sh，需设置文件头的环境变量

完毕。

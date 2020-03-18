create database dbfailover;

use dbfailover;

create table master_info (
  db_name varchar(100) NOT NULL,
  ip varchar(12)NOT NULL,
  port int(11) NOT NULL,
  user_name varchar(100) NOT NULL,
  status int(11) DEFAULT '0' COMMENT '0: active, 1: inactive',
  update_time timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (db_name)
) ENGINE=InnoDB;

create table master_arbit_info (
  id bigint(20) NOT NULL AUTO_INCREMENT,
  db_name varchar(100) NOT NULL,
  semi_status int(11) NOT NULL,
  heartbeat_time datetime NOT NULL,
  create_time datetime NOT NULL,
  PRIMARY KEY (id),
  KEY idx_ct (create_time)
) ENGINE=InnoDB;

DELIMITER |
create event job_data_clear
on schedule every 1 hour starts now()
on completion preserve
enable
do
delete master_arbit_info where create_time < date_sub(now(), INTERVAL 1 DAY)|
DELIMITER ;

create database dbfailover;

use dbfailover;

create table master_info (
  db_name varchar(100) NOT NULL,
  ip varchar(12)NOT NULL,
  port int(11) NOT NULL,
  user_name varchar(100) NOT NULL,
  status int(11) DEFAULT '0' COMMENT '0: active, 1: inactive',
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

CREATE EVENT job_data_clear ON SCHEDULE EVERY 1 HOUR ON COMPLETION PRESERVE ENABLE DO
	DELETE FROM master_arbit_info WHERE	create_time < DATE_SUB(now(), INTERVAL 1 DAY);

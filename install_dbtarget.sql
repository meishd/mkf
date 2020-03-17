create table heartbeat (
  id int(11) NOT NULL DEFAULT '0',
  create_time datetime DEFAULT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

insert into heartbeat(id,create_time) values (1,now());

DELIMITER |
create event job_heartbeat
on schedule every 1 second starts now()
on completion preserve
enable
do
begin
update heartbeat
set create_time=now()
where id=1;
end|
DELIMITER ;

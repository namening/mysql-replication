	MySQL Replication又称“AB复制”或者“主从复制”，它主要用于mysql的实时备份和读写分离。
1、配置mysql服务
	搭建好一个3306端口的mysql，下面再搭建一个3307端口的mysql，方法如下：
	#cd /usr/local/
	#cp -r mysql mysql_2
	#cd mysql_2
	#./scripts/mysql_install_db --user=mysql --datadir=/data/mysql2
	然后初始化数据库目录，显示两个“OK”并且生成/data/mysql2目录才正确。
	复制配置文件到mysql_2目录下，并修改相关项目，如下所示：
	#cp /etc/my.cnf ./my.cnf
	#vim my.cnf
	需要修改如下参数：
log_bin = aminglinux2
basedir = /usr/local/mysql_2
datadir = /data/mysql2
port = 3307
server_id = 129
socket = /tmp/mysql2.sock
	保存配置文件后，复制启动脚步并编辑，
	#cp support-files/mysql.server /etc/init.d/mysqld2
	#vim /etc/init.d/mysqld2
	需要更改的地方有：
basedir=/usr/local/mysql2
datadir=/data/mysql2
$bindir/mysqld_safe --default-file=$basedir/my.cnf --datadir="$datadir"
--pid-file="$mysqld_pid_file_path" $other_args > /dev/null &
	第三行为启动命令，增加了--defaults参数，若不增加则不能正确找到mysql_2的配置文件。
	然后启动两个MYSQL：
	#/etc/init.d/mysqld start
	#/etc/init.d/mysqld2 start
	到此，已经在一个linux上启动了2个mysql，
	#netstat -lnp|grep mysql
2、配置Replication
	把3307端口的mysql作为主（master），而把3306的mysql作为从（slave）。先在master上创建一个库aming，如下所示：
	#mysql -uroot -S /tmp/mysql2.sock
	mysql> create database aming;
	mysql> quit
	其中，-S（大写字母）后面指定MYSQL的socket文件路径，这也是登录mysql的一种方法。因为在一台服务器上运行了两个mysql端口，所以用-S这样的方法来区分：
	然后把mysql库的数据复制给aming库，如下所示：
	#mysqldump -uroot -S /tmp/mysql2.sock mysql > /tmp/aming.sql
	#mysql -uroot -S /tmp/mysql2.sock aming < aming.sql
2.1设置主（master）
	将mysql_2的配置文件设置过相关的参数，如果你的没有设置，请添加：
	server-id=129
	log_bin=aminglinux2
	另外还有两个参数你可以选择性地使用，如下所示：
binlog-do-db=databasename1,databasename2
binlog-ignore-db=databasename1,databasename2
	其中，binlog-do-db=定义需要复制的数据库，多个数据库用英文的逗号分隔，binlog-ignore-db=定义不需要复制的数据库，这两个参数用其中一个即可。
	如果修改过配置文件，需要重启mysql服务。重启服务的方法如下：
	#/etc/init.d/mysqld2 restart
	刚安装的mysql_2的root密码为空，需要设置一下root用户的访问密码：
	#mysqladmin -uroot -S /tmp/mysql2.sock password 'aminglinux.com'
	#mysql -uroot -S /tmp/mysql2.sock -password
	enter password:
	mysql> grant relication slave on *.* to 'repl'@'127.0.0.1' identified by '123lalala';
	这里repl是为（slave）端设置的访问主（master）端的用户，也就是完成主从复制的用户，其密码为123lalala，这里的127.0.0.1为slave的IP（因为配置的master和slave都在本机）。
	mysql> flush tables with read lock;
	该操作将锁定数据库写操作。
	mysql>show master status;
	上面的操作查看master的状态
2.2设置从（slave）
	首先修改slave的配置文件my.cnf,执行如下命令：
	#vim /etc/my.cnf
	找到server_id=,设置成和master不一样的数字，若一样会导致后面的操作不成功。另外在slave上，你也可以选择性的增加如下两行，对应master上增加的两行：
replicate-do-db=databasename1,databasename2
replication-ignore-db=databasename1,databasename2
保存修改后重启slave，执行如下命令：
	#/etc/init.d/mysqld restart
	然后复制master上aming库的数据到slave上。因为master和slave都在一台服务器上，所以操作起来很简单。如果在不同的机器上，就需要远程复制了（使用scp或者rsync）。
	#mysqldump -uroot -S /tmp/mysql2.sock -p'aminglinux.com' aming > /tmp/aming.sql
	#mysql -uroot -S /tmp/mysql.sock -p123456 -e "create database aming"
	#mysql -uroot -S /tmp/mysql.sock -p123456 aming < /tmp/aming.sql
	上面的第二行中，使用了-e选项，它用来把mysql的命令写到shell命令行下，其格式为：-e"commond".-e选项很实用！
	复制完数据后，就需要在slave上配置了：
	#mysql -uroot -S /tmp/mysql.sock -p123456
mysql> stop slave;
mysql> change master to master_host='127.0.0.1',
master_port=3307,master_user='repl',
master_password='123lalala',
master_log_file='aminglinux2.000003',
master_log_pos=652867;
mysql> start slave;
	说明：change master这个命令是一条，打完逗号后可以按回车，直到你打分号才算结束。其中，master_log_file和master_log_pos是在前面使用show master status命令查到的数据。执行完这一步后，需要在master上执行下面一步（建议打开两个终端，分别连两个mysql）：
	#mysql -uroot -S /tmp/mysql2.sock -p'aminglinux.com' -e "unlock tables"
	然后在slave端查看slave的状态，执行如下命令：
	mysql>show slave status\G;
	确认一下两项参数都为Yes，如下所示：
	Slave_IO_Running:	Yes
	Slave_SQL_Running:  Yes
	还需要关注的地方有：
Seconds_Behind_Master: 0	//为主从复制延迟的时间
Last_IO_Errno: 0
Last_IO_Errno:
Last_SQL_Errno: 0
Last_SQL_Errno:
	如果主从不正常了，需要看这里的error信息。
3、测试主从
	在master上执行如下命令：
	#mysql -uroot -S /tmp/mysql2.sock -p 'aminglinux.com' aming
	mysql> select count(*) from db;
	+-----------+
	| count(*) |
	+-----------+
	|		2  |
	+-----------+
	mysql> truncate table db;
	mysql> select count(*) from db;
	+-----------+
	| count(*) |
	+-----------+
	|		0  |
	+-----------+
	这样就清空了aming.db表的数据。下面查看slave上该表的数据，执行如下命令：
	#mysql -uroot -S /tmp/mysql.sock -p123456 aming
	mysql> select count(*) from db;
	+-----------+
	| count(*) |
	+-----------+
	|		0  |
	+-----------+
	slave上该表的数据也被清空了，但好像不太明显，我们不妨在master上据需删除db表，如下所示：
	mysql> drop table db;
	再从slave查看：
	mysql> select * from db;
	ERROR 1146 (42s02): Table 'aming.db' doesn't exist
	这次很明显了，db表已经不存在。主从配置起来虽然很简单，但这种机制非常脆弱，一旦我们不小心在slave上写了数据，那么主从复制也就被破坏力。另外，如果重启master，五笔要先关闭slave，即在slave上执行slave stop命令，然后再去重启master的MYSQL服务，否则主从复制很有可能就会中断。当然重启master后，我们还需要执行start slave命令开启主从复制的服务。
	
	
	

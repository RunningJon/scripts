#!/bin/bash
# This script requires Outsourcer to be installed.  It creates an external
# table which connects to a Oracle database to get basic session information.
#
# Prerequisites:
# 1.  Outsourcer is installed
#
# 2.  dba schema is created 
# CREATE SCHEMA dba;
#
# 3.  A valid connection defined in os.ext_connection for SQL Server.
# INSERT INTO os.ext_connection
# (type, server_name, instance_name, port, database_name, user_name, pass)
# VALUES
# ('oracle', 'jonnywin', null, 1521, 'xe', 'os_test', 'os_password');
#
# Note: you can also use the Web UI to create this connection.
# 
# --get the ID you just inserted
# SELECT id 
# FROM os.ext_connection 
# WHERE type = 'oracle'
# AND server_name = 'jonnywin'
# AND port = 1521
# AND database_name = 'xe';
# 
# --in my example, the value is 1.
#
# Note that Oracle uses "$" in table names and must be escaped.  From this bash script, there are 9 backslashes.
#
psql -c "set standard_conforming_strings=on; SELECT os.fn_create_ext_table('dba.oracle_sessions', 
ARRAY['username varchar(30)','osuser varchar(30)','machine varchar(64)', 'terminal varchar(30)','program varchar(48)', 'module varchar(48)','sql_text text','logon_time timestamp', 'service_name varchar(64)'], 
1,
E'SELECT s.USERNAME, s.OSUSER, s.MACHINE, s.TERMINAL, s.PROGRAM, s.MODULE, a.sql_text, s.LOGON_TIME, s.service_name 
FROM v\\\\\\\\\$session s, v\\\\\\\\\$sqlarea a WHERE a.address = s.sql_address');"

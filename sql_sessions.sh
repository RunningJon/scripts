#!/bin/bash
# This script requires Outsourcer to be installed.  It creates an external
# table which connects to a SQL Server database to get basic session 
# information.
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
# ('sqlserver', 'jonnywin', null, null, null, 'os_test', 'os_password');
#
# --get the ID you just inserted
# SELECT id 
# FROM os.ext_connection 
# WHERE type = 'sqlserver' 
# AND server_name = 'jonnywin'
# 
# --in my example, the value is 2.
#
psql -c "SELECT os.fn_create_ext_table('dba.sql_sessions', 
ARRAY['sql_time timestamp','start_time timestamp','status varchar(30)', 'session_id smallint','sqltext text'], 
2, --os.ext_connection.id 
'SELECT getdate() as sql_time, req.start_time, req.status, req.session_id, sqltext.TEXT as sqltext 
FROM sys.dm_exec_requests req 
CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS sqltext 
order by req.start_time');"

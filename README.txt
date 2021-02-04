***********************************************************************************
** Repo is no longer maintained. **
***********************************************************************************

README file for Scripts
****************************************************************************************
Author: Jon Roberts
Date: 2014-12-10
****************************************************************************************

Scripts for maintaining Greenplum Database and HAWQ.

1.  maintain.sh
HAWQ and GPDB
- VACUUM ANALYZE all tables in pg_catalog

GPDB Only
- REINDEX the system catalog (reindexdb -s)
- ANALYZE tables with missing statistics (gp_toolkit.gp_stats_missing).  A partitioned 
  table always shows up here so I ignore those and check for partitions/inherited tables 
  with missing statistics.
- VACUUM heap tables near the transaction wraparound point
- VACUUM heap tables with bloat (gp_toolkit.gp_bloat_diag)
- VACUUM AO tables with bloat (gp_toolkit.__gp_aovisimap_hidden_info). I'm using 5% as 
  the threshold.

2.  kill_idle.sh
Kill idle sessions that have not executed anything for at least 1 hour.

3.  kill_long_running.sh
Kill long running queries that have executed for at least 1 hour.  There is typically 
room for improvement if a query executes for over an hour.

4.  sql_sessions.sh
Get session information from a remote SQL Server database.

5.  oracle_sessions.sh
Get session information from a remote Oracle database.

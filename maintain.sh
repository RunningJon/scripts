#!/bin/bash
v=`psql -t -A -c "SELECT CASE WHEN POSITION ('HAWQ' in version()) > 0 AND POSITION ('Greenplum' IN version()) > 0 THEN 'hawq' WHEN POSITION ('HAWQ' in version()) = 0 AND POSITION ('Greenplum' IN version()) > 0 THEN 'gp' ELSE 'OTHER' END;"`

if [ "$v" == "hawq" ]; then
	search_path=public,pg_catalog,hawq_toolkit

else 
	if [ "$v" == "gp" ]; then
		search_path=public,pg_catalog,gp_toolkit
	fi
fi
s=_stats_missing
stats_missing=$v$s

clear
echo "*******************************************************************************************"
echo "** VACUUM ANALYZE the pg_catalog                                                         **"
echo "**                                                                                       **"
echo "** Creating and dropping database objects will cause the catalog to grow in size so that **"
echo "** there is a read consistent view.  VACUUM is recommended on a regular basis to prevent **"
echo "** the catalog from suffering from bloat. ANALYZE is also recommended for the cost based **"
echo "** optimizer to create the best query plans possble when querying the catalog.           **"
echo "**                                                                                       **"
echo "*******************************************************************************************"
t=`date`
echo "Start: $t"
psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM ANALYZE \"' || n.nspname || '\".\"' || c.relname || '\";' FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = 'pg_catalog' AND c.relkind = 'r' | psql -e
t=`date`
echo "Finish: $t"

if [ "$v" == "gp" ]; then
	echo "*******************************************************************************************"
	echo "** REINDEX the pg_catalog                               .                                **"
	echo "**                                                                                       **"
	echo "** Reindexing the catalog indexes will help prevent bloat or poor performance when       **"
	echo "** querying the catalog.                                                                 **"
	echo "*******************************************************************************************"
	t=`date`
	echo "Start: $t"
	reindexdb -s
	t=`date`
	echo "Finish: $t"

	echo "*******************************************************************************************"
	echo "** ANALYZE all tables/partitions with missing statistics.                                **"
	echo "**                                                                                       **"
	echo "** Heap tables or partitions that don't have statistics make it difficult for the cost   **"
	echo "** based optimizer from creating the optimal plan.  This section will identify these     **"
	echo "** tables or partitions.  Note: Tables that are empty are also analyzed.                 **"
	echo "*******************************************************************************************"
	t=`date`
	echo "Start: $t"
	psql -t -A -c "SET search_path=$search_path; SELECT 'ANALYZE \"' || n.nspname || '\".\"' || c.relname || '\";' 
	FROM pg_class c
	JOIN pg_namespace n ON c.relnamespace = n.oid
	JOIN gp_stats_missing g ON g.smischema = n.nspname AND g.smitable = c.relname
	LEFT JOIN       (--top level partitioned tables
	                SELECT c.oid
	                FROM pg_class c
	                LEFT JOIN pg_inherits i ON c.oid = i.inhrelid
	                WHERE i.inhseqno IS NULL
	                ) pt ON c.oid = pt.oid
	WHERE c.relkind = 'r'
	AND pt.oid IS NULL" | psql -e 
	t=`date`
	echo "Finish: $t"

	echo "*******************************************************************************************"
	echo "** VACUUM all tables near the vacuum_freeze_min_age to prevent transaction wraparound    **"
	echo "**                                                                                       **"
	echo "** Over time, you may have some rather old tables in your database and with lots of      **"
	echo "** of transactions, you may eventually have a table that needs to be vacuumed to prevent **"
	echo "** a transaction wraparound problem.  This script uses a rather low value to identify    **"
	echo "** these heap tables very early.                                                         **"
	echo "*******************************************************************************************"
	t=`date`
	echo "Start: $t"
	vacuum_freeze_min_age=`psql -t -A -c "show vacuum_freeze_min_age;"`
	psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM \"' || n.nspname || '\".\"' || c.relname || '\";' FROM pg_class c join pg_namespace n ON c.relnamespace = n.oid WHERE age(relfrozenxid) > $vacuum_freeze_min_age AND c.relkind = 'r' | psql -e
	t=`date`
	echo "Finish: $t"

	echo "*******************************************************************************************"
	echo "** VACUUM all heap tables with bloat                                                     **"
	echo "**                                                                                       **"
	echo "** Utilize the toolkit schema to identify heap tables that have excessive bloat and need **"
	echo "** to be vacuumed.                                                                       **"
	echo "*******************************************************************************************"
	t=`date`
	echo "Start: $t"
	psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM \"' || bdinspname || '\".\"' || bdirelname || '\";' FROM gp_bloat_diag WHERE bdinspname <> 'pg_catalog'" | psql -e
	t=`date`
	echo "Finish: $t"

	echo "*******************************************************************************************"
	echo "** VACUUM all append optimized tables with bloat                                         **"
	echo "**                                                                                       **"
	echo "** Utilize the toolkit schema to identify ao tables that have excessive bloat and need   **"
	echo "** to be vacuumed.                                                                       **"
	echo "*******************************************************************************************"
	t=`date`
	echo "Start: $t"
	psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM ANALYZE \"' || schema_name || '\".\"' || table_name || '\";'
	FROM    (
        	SELECT n.nspname AS schema_name, c.relname AS table_name, c.reltuples AS num_rows, (__gp_aovisimap_hidden_info(c.oid)).total_tupcount AS ao_num_rows
       		FROM pg_appendonly a
        	JOIN pg_class c ON c.oid = a.relid
       		JOIN pg_namespace n ON c.relnamespace = n.oid
       		WHERE c.relkind = 'r' 
       		AND c.reltuples > 0
       		) AS sub
	GROUP BY schema_name, table_name, num_rows
	HAVING sum(ao_num_rows) > num_rows * 1.05" | psql -e
	t=`date`
	echo "Finish: $t"
fi


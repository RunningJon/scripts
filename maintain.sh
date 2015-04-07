#!/bin/bash
set -e

echo "*******************************************************************************************"
echo "**                                                                                       **"
echo "** Maintenance script for HAWQ and Greenplum by PivotalGuru.com                          **"
echo "**                                                                                       **"
echo "*******************************************************************************************"

# check PGDATABASE 
if [ -z $PGDATABASE ]; then
	db=$USER
fi

v=`psql -t -A -c "SELECT CASE WHEN POSITION ('HAWQ' in version()) > 0 AND POSITION ('Greenplum' IN version()) > 0 THEN 'hawq' WHEN POSITION ('HAWQ' in version()) = 0 AND POSITION ('Greenplum' IN version()) > 0 THEN 'gp' ELSE 'OTHER' END;"`

if [ "$v" == "hawq" ]; then
	search_path=public,pg_catalog,hawq_toolkit

	# get the release number of HAWQ
	r=`psql -t -A -c "SELECT REPLACE((SPLIT_PART(SUBSTR(version, POSITION ('HAWQ' IN version) + 5), ' ', 1)), '.', '') as release FROM version();"`

else 
	search_path=public,pg_catalog,gp_toolkit
fi
s=_stats_missing
stats_missing=$v$s

echo ""
echo "*******************************************************************************************"
echo "** VACUUM ANALYZE the pg_catalog                                                         **"
echo "**                                                                                       **"
echo "** Creating and dropping database objects will cause the catalog to grow in size so that **"
echo "** there is a read consistent view.  VACUUM is recommended on a regular basis to prevent **"
echo "** the catalog from suffering from bloat. ANALYZE is also recommended for the cost based **"
echo "** optimizer to create the best query plans possble when querying the catalog.           **"
echo "*******************************************************************************************"
t=`date`
echo "Start: $t"
psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM ANALYZE \"' || n.nspname || '\".\"' || c.relname || '\";' FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = 'pg_catalog' AND c.relkind = 'r'" | psql -e
t=`date`
echo "Finish: $t"

if [ "$v" == "gp" ] || ([ "$v" == "hawq" ] && [ $r -ge 1300 ]); then 

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
fi

echo "*******************************************************************************************"
echo "** ANALYZE all tables/partitions with missing statistics.                                **"
echo "*******************************************************************************************"

t=`date`
echo "Start: $t"

if [ "$v" == "hawq" ]; then
	if [ $r -ge 1300 ]; then
		analyzedb -d $db -a
	else
		psql -t -A -c "SET search_path=$search_path; select 'ANALYZE \"' || smischema || '\".\"' || smitable || '\";' from hawq_stats_missing" | psql -e
	fi
else 
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
fi

t=`date`
echo "Finish: $t"

echo "*******************************************************************************************"
echo "** VACUUM all tables near the vacuum_freeze_min_age to prevent transaction wraparound    **"
echo "*******************************************************************************************"
t=`date`
echo "Start: $t"
vacuum_freeze_min_age=`psql -t -A -c "show vacuum_freeze_min_age;"`
psql -t -A -c "SET search_path=$search_path; SELECT 'VACUUM \"' || n.nspname || '\".\"' || c.relname || '\";' FROM pg_class c join pg_namespace n ON c.relnamespace = n.oid WHERE age(relfrozenxid) > $vacuum_freeze_min_age AND c.relkind = 'r'" | psql -e
t=`date`
echo "Finish: $t"

if [ "$v" == "gp" ]; then
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


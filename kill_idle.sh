#!/bin/bash
eval `psql -A -t -c "SELECT 'kill ' || procpid FROM pg_stat_activity WHERE current_query = '<IDLE>' AND clock_timestamp() - query_start > interval '1 hour'"`

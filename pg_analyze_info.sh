#!/bin/bash

# pg_analyze_info.sh

# A small script to parse the
# output of Postgresql's ANALYZE,
# and extract information needed
# for reporting a query issue to the
# pgsql-performance mailing list

# see:
# http://www.postgresql.org/message-id/CAD3a31Uah=tszPw6hD8PKdzTpVT6bjT1KsX5ooKPZ69+4gFi+Q@mail.gmail.com
# http://wiki.postgresql.org/wiki/Guide_to_reporting_problems
# http://wiki.postgresql.org/wiki/SlowQueryQuestions

# Attempts to identify all tables and indexes referenced by analyze,
# and generate commands for psql to describe those tables.
# Reports Postgres version number
# Reports actual & estimated row counts for all tables

# Known issues:
# Will not work on tables or indexes with spaces,
# or special characters in the name.
# Doesn't yet pick up tables used in Index Scan Backward or Bitmap Heap Scan
# Doesn't yet pick up indexes used in Index Scan Backward or Index Only Scans

# By Ken Tanzer
# ken.tanzer@gmail.com, ken.tanzer@agency-software.org

# Modification and/or distribution is permitted without any restrictions

source_file=$1

if [[ ! $source_file ]] ; then
	echo usage: $0 analyze_file
	echo
	exit
fi
#D='\d '
D='\d+ '

# Get indexes
index_list=$( egrep -o 'Index Scan using [a-zA-Z0-9_-]*' $source_file  | cut -f 4 -d ' ' | sort -u ) 

# Get tables
table_list=$( 
cat <( 
# Indexed tables
egrep -o 'Index Scan using ["$a-zA-Z0-9_-]* on [a-zA-Z0-9_-]*' $source_file  | cut -f 6 -d ' '
) <(
# Scanned Tables
egrep -o 'Seq Scan on ["$a-zA-Z0-9_-]* ' $source_file | cut -f 4 -d ' '
) | sort -u )

# Header
echo \\qecho Supplemental Information for analyze file $(basename $1)
echo \\qecho
echo

# Report version
echo \\qecho ==== Postgres Version ====
echo "SELECT version();"
echo \\qecho
echo

# Server Tuning
echo \\qecho ==== Server Tuning ====
echo "SELECT name, current_setting(name), source FROM pg_settings WHERE source NOT IN ('default', 'override');"
echo \\qecho
echo

# Issue \d command for tables
echo \\qecho ==== Table Descriptions ====
for x in $table_list; do echo  "$D $x" ; done
echo \\qecho
echo

# Issue \d command for indexes
echo \\qecho ==== Index Descriptions ====
for x in $index_list; do echo "$D $x" ; done
echo \\qecho
echo

# Get actual & estimated table counts
echo "\\qecho ==== Table Counts (actual and estimated)" ====
t_arr=($table_list)
t_count=${#t_arr[@]}

while [[ "$c" -lt "$t_count" ]] ; do
	x=${t_arr[c]}
	# Strip quotes, if necessary, for relname query
	if [[ $( echo $x | cut -c 1 | grep '"') ]] ; then
		x_bare=$( echo $x | cut -f 2 -d '"')
	else
		x_bare=$x
	fi

	temp_tables+="SELECT '$x' AS table,count(*) AS actual, (SELECT reltuples FROM pg_class WHERE relname = '$x_bare') AS estimated FROM $x"
	((c++))
	if [[ "$c" != "$t_count" ]] ; then
		temp_tables+=" UNION\n"
	fi
done
temp_tables+=";"
echo -e $temp_tables
echo \\qecho
echo

# When was this file generated, and from what?
echo \\qecho ==== About this file ====
original_name=pg_analyze_info.sh
base=$(basename $0)
if [[ "$base" != "$original_name" ]] ; then
extra=" ($0)"
fi
echo \\qecho The commands to provide this output were generated from this analyze file: $1
echo \\qecho Commands were generated at $(date) by $original_name$extra
echo \\qecho The output was generated from the database at \`date\`



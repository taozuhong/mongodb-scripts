#!/bin/bash

help () {
        echo "
	\$1 = count of replica set
	\$2 = start port 27000
	\$3 = rs
	\$4 = start path for db directory ./data/rs/
	\$5 = start path for log file ./log/rs/
        "
}


# === test incoming values ===
if [ $# -lt 5 ]; then
	echo "You should define 5 incoming parameters"
        help
        exit 1
fi


# === main ===
printf "\n=== create replica set ===\n"
mkdir -p $5
port=$2
replica_count=$1
replica_name=$3
for rs in $(seq $replica_count);
do
	dir="$4rs$rs"
	log="$5mongod_$rs.log"
	port=$(($port + 1))
	mkdir -p $dir

	printf "\niter = $rs, dir = $dir, port = $port, log = $log\n";
	mongod --port $port --replSet $replica_name --dbpath $dir --oplogSize 50 --logpath $log --logappend --bind_ip localhost --fork
done


printf "\n=== init replica set ===\n"
port=$(($2 + 1))
replica_count=$(($1 - 1))
mongosh admin --port "${port}" --eval "rs.initiate();"
for rs in $(seq $replica_count)
do
	next_port=$(($port + $rs))
	mongosh admin --port "${port}" --eval "rs.add('localhost:${next_port}');"
done

printf "\nmongod in replica set started :-)"


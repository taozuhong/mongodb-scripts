#!/bin/bash

help () {
	echo "
	\$1 = count of shards
	\$2 = count of replica set
	\$3 = start path for db directory: ./data/sh/
	\$4 = start path for log file ./log/sh/
	\$5 = start server data port: 26050
	\$6 = start config port: 27000
	\$7 = mongos port: 27017
	"
}


build_shards () {
	printf "\n=== build shards servers ===\n"
	local port=$4
	local shard_count=$1
	local replica_count=$2
	local db=$3
	local log_path=$5
	for sh in $(seq $shard_count)
	do
		# replica set in shard (data servers)
		for rs in $(seq $replica_count)
		do
			local dir="${db}sh_$sh$rs";
			echo "init: $dir";
        	        local log="${log_path}mongod_sh$sh$rs.log";
			port=$(($port + 1));
			local replSet="rs$sh"
			mkdir -p $dir

			mongod --shardsvr --port $port --replSet $replSet --dbpath $dir --oplogSize 50 --logpath $log --logappend --bind_ip localhost --fork
		done
	done
}


init_shards_repl_set () {
	printf "\n=== init shards replica set ===\n"
	local port=$3
	local shard_count=$1
	local replica_count=$(($2 - 1))
	for sh in $(seq $shard_count)
	do
		port=$(($port + 1))
		mongosh admin --port "${port}" --eval "rs.initiate();"
	        for rs in $(seq $replica_count)
	        do
			local next_port=$(($port + $rs));
			mongosh admin --port "${port}" --eval "rs.add('localhost:${next_port}');"
	        done
		port=$(($port + $replica_count))
	done
 }


build_config_servers () {
	printf "\n=== build 3 config servers ===\n"
	local port=$2
	local db=$1
	local log_path=$3
	local config_count=$4
	for cfg in $(seq $config_count)
	do
		local dir="${db}cfg$cfg";
		echo "init: $dir";
		local log="${log_path}mongod_cfg$cfg.log";
		port=$(($port + 1));
		mkdir -p $dir

		mongod --configsvr --port $port --replSet $cfg_repl_set --dbpath $dir --oplogSize 50 --logpath $log --logappend --bind_ip localhost --fork
	done
}


init_config_repl_set () {
	printf "\n=== init config replica set ===\n"
	local port=$(($1 + 1))
	local config_count=$((($2 - 1)))
	mongosh admin --port "${port}" --eval "rs.initiate();"

	for cfg in $(seq $config_count)
	do
		local next_port=$(($port + $cfg));
        	mongosh admin --port "${port}" --eval "rs.add('localhost:${next_port}');"
	done
}


start_mongos_process () {
	printf "\n=== start mongos ===\n"
	local port=$1
	local config_count=$3
	local log_path="$2mongos_1.log"
	local config_db=""
	for cfg in $(seq $config_count)
	do
		port=$(($port + 1))
		config_db="${config_db}localhost:${port},"
	done
	config_db="${config_db:0:${#config_db}-1}"
	config_db="${cfg_repl_set}/${config_db}"

	echo "$config_db"
	mongos --configdb $config_db --logappend --bind_ip localhost --logpath $log_path --port $mongos_port --fork
}


init_mongos_shards () {
	printf "\n=== init mongos ===\n"
  	local shard_count=$1
  	local replica_count=$2
	local port=$3
	for sh in $(seq $shard_count)
        do
		local rs_db=""
		for rs in $(seq $replica_count)
		do
       			port=$(($port + 1))
	        	rs_db="${rs_db}localhost:${port},"
        	done
		rs_db="${rs_db:0:${#rs_db}-1}"
	        rs_db="rs${sh}/${rs_db}"
		echo "${rs_db}"
		mongosh admin --port $mongos_port --eval "sh.addShard('${rs_db}')"
        done
}


fill_test_shard_collection () {
	mongosh --port $mongos_port ./fill_test_collection.js
}


# === test incoming values ===
if [ $# -lt 7 ]; then
	echo "You should define 7 incoming parameters"
	help
	exit 1
fi


# === init env and directories ===
cfg_repl_set="cfg"
shard_count=$1
replica_count=$2
db_dir=$3
log_dir=$4
data_start_port=$5
config_start_port=$6
mongos_port=$7
# directory for data
mkdir -p $3
# directory for logs
mkdir -p $log_dir


# === mongod data replica sets ===
while [[ -z "$useShards" ]] || [[ ! $useShards =~ ^(y|n|yes|no)$ ]]
do
	read -p "===> Do you want to init Data replicaSet of 'mongod' nodes? (y/n): " useShards
done
printf "Answer: ${useShards}\n\n"
if [[ $useShards =~ ^y(es)?$ ]]; then
	build_shards $shard_count $replica_count $db_dir $data_start_port $log_dir
	init_shards_repl_set $shard_count $replica_count $data_start_port
fi


# === mongod config replica sets ===
while [[ -z "$useConfig" ]] || [[ ! $useConfig =~ ^(y|n|yes|no)$ ]]
do
         read -p "===> Do you want to init Config replicaSet of 'mongod' nodes? (y/n): " useConfig
done
printf "Answer: ${useConfig}\n\n"
if [[ $useConfig =~ ^y(es)?$ ]]; then
	build_config_servers $db_dir $config_start_port $log_dir $replica_count
	init_config_repl_set $config_start_port $replica_count
fi


# === mongos ===
while [[ -z "$useMongos" ]] || [[ ! $useMongos =~ ^(y|n|yes|no)$ ]]
do
         read -p "===> Do you want to init 'mongos'? (y/n): " useMongos
done
printf "Answer: ${useMongos}\n\n"
if [[ $useMongos =~ ^y(es)?$ ]]; then
	start_mongos_process $config_start_port $log_dir $replica_count
	init_mongos_shards $shard_count $replica_count $data_start_port
fi


# === test sharded collection ===
while [[ -z "$useTestCollection" ]] || [[ ! $useTestCollection =~ ^(y|n|yes|no)$ ]]
do
         read -p "===> Do you want to create test collection? (y/n): " useTestCollection
done
printf "Answer: ${useTestCollection}\n\n"
if [[ $useTestCollection =~ ^y(es)?$ ]]; then
        fill_test_shard_collection
fi

printf "\nmongod in shards started :-)\n"




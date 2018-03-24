#!/bin/bash

PWD=`pwd`
BOOTNODEDIR="$PWD/bootnode"
DATADIR="$PWD/data"

BOOTKEY="boot.key"
GENESISJSON="genesis.json"
ENODE=""

CN_GENBOOTNODE="genkey"
CN_BOOTNODE="bootnode"
CN_PERFIXNODE="peer"
CN_INIT="genesis_init"

NETWORKID="8765639736937780"
ADDRESS="192.168.1.77"
RPCPORT_BEGIN=8545
ETHPORT_BEGIN=31303
OLDPORT_BEGIN=31304

PEERNUM=2

makedatadir() {
	echo "Checking datadir..."
    if [ ! -d "$BOOTNODEDIR" ]; then mkdir -p $BOOTNODEDIR; fi
	count=1
	while(( $count<=$PEERNUM ))
	do
		if [ ! -d "$DATADIR/$count" ]; then mkdir -p $DATADIR/$count; fi
		let "count++"
	done


    if [ ! -f "$DATADIR/$GENESISJSON" ]
	then
	cat << EOF > "$DATADIR/$GENESISJSON"
{
 "alloc": {},
 "config": {
   "chainID": 72,
   "homesteadBlock": 0,
   "eip155Block": 0,
   "eip158Block": 0
 },
 "nonce": "0x0000000000000000",
 "difficulty": "0x0",
 "mixhash": "0x0000000000000000000000000000000000000000000000000000000000000000",
 "coinbase": "0x0000000000000000000000000000000000000000",
 "timestamp": "0x00",
 "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
 "extraData": "0x11bbe8db4e347b4e8c937c1c8370e4b5ed33adb3db69cbdb7a38e1e50b1b82fa",
 "gasLimit": "0xffffffff"
}
EOF
	fi
	echo "Ok."
}

clean() {
	echo "Cleaning ..."
	count=1
	while(( $count<=$PEERNUM ))
	do
		docker stop $CN_PERFIXNODE$count > /dev/null  2>&1
		docker stop $CN_INIT$count > /dev/null  2>&1
		
		docker rm -f $CN_PERFIXNODE$count > /dev/null  2>&1
		docker rm -f $CN_INIT$count > /dev/null  2>&1
		
		let "count++"
	done
	docker stop $CN_BOOTNODE > /dev/null  2>&1
	docker rm -f $CN_BOOTNODE > /dev/null  2>&1
	docker stop $CN_GENBOOTNODE > /dev/null  2>&1
	docker rm -f $CN_GENBOOTNODE > /dev/null  2>&1
	
	sudo rm -rf $BOOTNODEDIR > /dev/null  2>&1
	sudo rm -rf $DATADIR > /dev/null  2>&1
	echo "Ok."
}


testcontainer() {
	if [ ! -z `docker ps -a|awk '{if(match($0,"[ \t]('$1')",a))print a[1]}'` ]
	then
	    return 1
	else
	    return 0
	fi
}

genkey() {
	echo "Checking bootkey..."
	if [ ! -f "$BOOTNODEDIR/$BOOTKEY" ]
	then 
		echo "Generating bootkey..."
		testcontainer $CN_GENBOOTNODE
		if [ $? -eq 0 ] 
		then
		    docker run -v "$BOOTNODEDIR:/root/bootnode" --name $CN_GENBOOTNODE docker.io/hawyasunaga/ethereum-bootnode bootnode --genkey="/root/bootnode/$BOOTKEY"
		else
		    docker start $CN_GENBOOTNODE
		fi
	fi
	
	echo "Ok."
}

initgenesis() {
	echo "Init genesis block..."
	count=1
	while(( $count<=$PEERNUM ))
	do
		
		if [ ! -d "$DATADIR/$count/geth" ] 
		then
			docker run -v $DATADIR:/root/data --name $CN_INIT$count ethereum/client-go --datadir /root/data/$count --networkid $NETWORKID init /root/data/$GENESISJSON
			docker rm $CN_INIT$count > /dev/null  2>&1
		fi
		
		let "count++"
	done
	
	echo "Ok."
}

init() {
	makedatadir
	genkey
	initgenesis
}


startbootnode() {
	if [ ! -f "$BOOTNODEDIR/$BOOTKEY" ]; then init; fi
	echo "Checking bootnode..."
	testcontainer "bootnode"
	if [ $? -eq 1 ]
	then
		echo "Removing bootnode..."
		docker rm -f bootnode > /dev/null  2>&1
	fi
	echo "Starting bootnode..."
	docker run -itd -m 512M --privileged=true --memory-swap -1 --net=host -p 30301:30301/udp -v $BOOTNODEDIR:/root/bootnode --name bootnode docker.io/hawyasunaga/ethereum-bootnode bootnode --nodekey=/root/bootnode/boot.key
	echo "The bootnode already running."
}



startpeers() {
    echo "Starting peers..."
	ENODE=`docker logs bootnode|awk 'END{if(match($0,".*(enode:[^; ]*)\r",a))print a[1]}'`
	ENODE="${ENODE/\[::\]/${ADDRESS}}"
	echo $ENODE
	if [ -z $ENODE ]
	then
		echo "The bootnode was not started."
	else
		count=1
		while(( $count<=$PEERNUM ))
		do
			nodeName="$CN_PERFIXNODE$count"
			
			testcontainer $nodeName
			if [ $? -eq 1 ]
			then 
				echo "Removing $nodeName..."
				docker rm -f $nodeName
			fi
			
			docker run -itd -m 512M --privileged=true --memory-swap -1 -p $RPCPORT_BEGIN:8545/tcp -p $ETHPORT_BEGIN:30303/tcp -p $ETHPORT_BEGIN:30303/udp -p $OLDPORT_BEGIN:30304/udp -v $DATADIR:/root/data --name $nodeName ethereum/client-go --ipcdisable --bootnodes $ENODE --bootnodesv4 $ENODE --bootnodesv5 $ENODE --debug --datadir /root/data/$count --networkid $NETWORKID --rpc --rpcaddr "0.0.0.0" --rpccorsdomain "*" --cache=512 --verbosity 3 console
			
			let "count++"
			let "RPCPORT_BEGIN++"
			let "ETHPORT_BEGIN+=1000"
			let "OLDPORT_BEGIN+=1000"
			
			echo "Sleep 1s..."
			sleep 1s
		done
				
	fi
	echo "Ok."
}

start() {
	startbootnode
	echo "Sleep 3s..."
	sleep 3s
	startpeers
}

stop() {
	echo "Stopping peers..."
	count=1
	while(( $count<=$PEERNUM ))
	do
		
		docker stop $CN_PERFIXNODE$count > /dev/null  2>&1
		
		let "count++"
	done
	
	echo "Stopping bootnode..."
    docker stop bootnode  > /dev/null  2>&1
	echo "Ok."
}

status() {
	echo "Checking node status..."
	docker ps
}

case $@ in

	"init")
		init
	;;
	
	"start")
		start
	;;
	
	"stop")
		stop
	;;
	
	"restart")
		stop
		start
	;;
	
	"status")
		status
	;;
	
	"clean")
		clean
	;;
	
	"makedatadir")
		makedatadir
	;;
		
	"genkey")
		genkey
	;;
	
	"initgenesis")
		initgenesis
	;;
	
	"startbootnode")
		startbootnode
	;;
	
	"startpeers")
		startpeers
	;;
	
	
	
esac
	



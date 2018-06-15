#~/bin/bash
set -m

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -y)
    BYPASS="Y"
    shift
    ;;
    -t|--target)
    TARGET="$2"
    shift # past argument
    shift # past value
    ;;
    --port)
    PORT="$2"
    shift # past argument
    shift # past value
    ;;
    -s|--source)
    SOURCE="$2"
    shift # past argument
    shift # past value
    ;;
    -p|--password)
    PASSWORD="$2"
    shift # past argument
    shift # past value
    ;;
    -u|--user)
    USR="$2"
    shift # past argument
    shift # past value
    ;;
    --ssl)
    SSL="$2"
    shift # past argument
    shift # past value
    ;;
    --gtid)
    GTID="$2"
    shift # past argument
    shift # past value
    ;;
    -mm|--master-master)
    MM="$2"
    shift # past argument
    shift # past value
    ;;
    --iid)
    IID="$2"
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


echo "WARNING! This will wipe out the mysql installation on this machine."
if [[ $BYPASS != "Y" ]]
then
  read -p "Are you sure? (y/n) " -n 1 -r;
fi
echo    # (optional) move to a new line
if [[ $BYPASS == "Y" || $REPLY =~ ^[Yy]$ ]]
then
  if [ -z "$TARGET" ]
  then
    ip a | grep inet | grep -v inet6 | cut -d "/" -f1
    echo "Choose the ip address from above that is a fixed ip address on this server in the internal, private subnet for use inside the customer environment. "
    read -p "What is your choice? " -r
    echo    # (optional) move to a new line
    slave=$REPLY
  else
    slave=$TARGET
  fi
  if [ -z "$PORT" ]
  then
    PORT="12345"
  fi
  if [ -z "$SOURCE" ]
  then
    read -p "What is the corresponding ip address of the doner? " -r
    echo    # (optional) move to a new line
    doner=$REPLY
  else
    doner=$SOURCE
  fi
  if [ -z "$USR" ]
  then
    read -p "What is the user to log in as on the doner? " -r
    echo    # (optional) move to a new line
    user=$REPLY
  else
    user=$USR
  fi
  if [ -z "$PASSWORD" ]
  then
    read -p "What is the password of the $user user on the doner? " -r
    echo    # (optional) move to a new line
    pass=$REPLY
  else
    pass=$PASSWORD
  fi
  if [ -z "$SSL" ]
  then
    read -p "Establish replication using SSL? " -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]];
    then
      ssl="Y"
    else
      ssl="N"
    fi
  else
    ssl=$SSL
  fi
  if [ -z "$GTID" ]
  then
    read -p "Establish replication using GTID? " -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]];
    then
      gtid="Y"
    else
      gtid="N"
    fi
  else
    gtid=$GTID
  fi
  if [ -z "$MM" ]
  then
    read -p "Establish replication using the Master-Master pattern?\nReplication will be established from this instance back to the doner: " -r
    echo    # (optional) move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]];
    then
      if [[ $gtid == "Y" ]]; then  mm="Y"; else echo "The Master-Master pair is currently only available with gtid based replication."; mm="N"; fi
    else
      mm="N"
    fi
  else
    mm=$MM
  fi
  if [ -z "$IID" ]
  then
    if [ $(ss -tulpen | grep mysql | awk '{print $5;}' | cut -d":" -f 4 | sort -n | wc -l) -gt 1 ]; then
      echo "Currently, I see mysql running on more ports than the standard 3306:"
      ss -tulpen | grep mysql | awk '{print $5;}' | cut -d":" -f 4 | sort -n
      read -p "What is the port that the mysql instance that you want to establish replication for? " -r
      echo    # (optional) move to a new line
      if [[ $REPLY != "3306" ]];
      then
        INSTANCEID=$REPLY
      fi
    else
      read -p "I do not see mysql running on more than one port. Proceed with establishing replication on the primary instance? " -r
      echo    # (optional) move to a new line
      if [[ $REPLY != "Y" && $REPLY != "y" ]];
      then
        exit 1;
      fi
    fi
  else
    if [[ $IID != "3306" ]]
    then
      INSTANCEID=$IID
    fi
  fi

  if [ ! -f /etc/yum.repos.d/percona-release.repo ];
  then
    echo -e 'percona repo : \e[1m\e[31mNOT INSTALLED\e[0m' && yum install http://www.percona.com/downloads/percona-release/redhat/0.1-4/percona-release-0.1-4.noarch.rpm -y;
  fi && if [ $(which innobackupex) ];
  then
    echo -e 'innobackupex : \e[1m\e[32mINSTALLED\e[0m';
  else
    echo -e 'innobackupex : \e[1m\e[31mNOT INSTALLED\e[0m' && /usr/bin/yum install percona-xtrabackup -y;
  fi && if [ $(which nc) ];
  then
    echo -e 'nc : \e[1m\e[32mINSTALLED\e[0m';
  else
    echo -e 'nc : \e[1m\e[31mNOT INSTALLED\e[0m' && /usr/bin/yum install nc -y;
  fi && if [ $(which pv) ];
  then
    echo -e 'pv : \e[1m\e[32mINSTALLED\e[0m';
  else
    echo -e 'pv : \e[1m\e[31mNOT INSTALLED\e[0m' && /usr/bin/yum install pv -y;
  fi && if [ $(which expect) ];
  then
    echo -e 'expect : \e[1m\e[32mINSTALLED\e[0m';
  else
    echo -e 'expect : \e[1m\e[31mNOT INSTALLED\e[0m' && /usr/bin/yum install expect -y;
  fi
  systemctl stop mysql$INSTANCEID;
  rm -rf /var/lib/mysql$INSTANCEID/*
  su -s/bin/bash - mysql -c "cd /var/lib/mysql$INSTANCEID/; nc -l $PORT | pv | xbstream -x ./" &
  if [ -z "$INSTANCEID" ];
  then
    ./ssh-expect $pass ssh $user@$doner  'innobackupex --binlog-info=ON "${HOME}" --stream=xbstream 2>output.txt | nc -w 60 '"$slave"' '"$PORT"
  else
    MASTER_PORT=", MASTER_PORT=$INSTANCEID"
    mysqluser=$(grep user ~/.my.cnf | cut -d"=" -f2 | xargs)
    mysqlpass=$(grep password ~/.my.cnf | cut -d"=" -f2 | xargs)
    ./ssh-expect $pass ssh $user@$doner 'innobackupex --defaults-file=/etc/my'"$INSTANCEID"'.cnf --socket=/var/lib/mysql'"$INSTANCEID"'/mysql.sock --stream=xbstream --user='"$mysqluser"' --password='"$mysqlpass"' /var/lib/mysql'"$INSTANCEID"' 2>output.txt | nc -w 60 '"$slave"' '"$PORT"
  fi
  sleep 10; #needed to let the files finish writing before the next step
  su -s/bin/bash - mysql -c "innobackupex --apply-log /var/lib/mysql$INSTANCEID/"
  ./ssh-expect $pass scp $user@$doner:~/output.txt ./
  echo
  echo "getting the binlog on $doner"
  filename=`grep "MySQL binlog position" output.txt | cut -d"'" -f2`
  echo
  echo "getting the binlog position on $doner"
  position=`grep "MySQL binlog position" output.txt | cut -d"'" -f4`
  echo
  echo "getting the gtid binlog position on $doner"
  ./ssh-expect $pass ssh -t $user@$doner "mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e \"select binlog_gtid_pos('$filename', $position);\" > gtid.out"
  ./ssh-expect $pass scp $user@$doner:~/gtid.out ./
  gtidpos=`tail -n1 gtid.out`
  password=`pwgen 13 1`
  systemctl start mysql$INSTANCEID
  if [[ $ssl =~ [Yy] ]];
  then
    REQUIRE_SSL= " REQUIRE SSL"
    MASTER_SSL=", MASTER_SSL=1"
  fi
  if [[ $gtid =~ [Yy] ]];
  then
    MASTER_POSITION="master_use_gtid=slave_pos"
  else
    MASTER_POSTION="MASTER_LOG_FILE='$filename', MASTER_LOG_POS=$position"
  fi
  echo
  echo "adding the grant for the replication user on $doner"
  ./ssh-expect $pass ssh $user@$doner "mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e \"GRANT REPLICATION SLAVE ON *.* TO 'repl'@'$slave' identified by '$password'$REQUIRE_SSL; FLUSH PRIVILEGES;\""
  echo
  echo "setting the gtid_slave_pos on $slave"
  mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "SET GLOBAL gtid_slave_pos = '$gtidpos';"
  echo
  echo "setting the slave settings on $slave"
  mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "CHANGE MASTER TO master_host='$doner', master_user='repl', MASTER_PASSWORD='$password', $MASTER_POSITION $MASTER_SSL $MASTER_PORT;"
  echo
  echo "starting the slave on $slave"
  mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "start slave;"
  if [[ $mm =~ [Yy] ]];
  then
    echo
    echo "getting the binlog on $slave"
    filename=`mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "show master status\G" | grep File | awk '{print $2;}'`
    echo $filename
    echo
    echo "getting the binlog postion on $slave"
    position=`mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "show master status\G" | grep Position | awk '{print $2;}'`
    echo  "$position"
    echo
    echo "getting the current gtid binlog postion on $slave"
    gtidpos=`mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "select binlog_gtid_pos('$filename', $position)\G" | tail -n1 | cut -d":" -f2`
    echo "$gtidpos"
    if [[ $gtid =~ [Yy] ]];
    then
      if [[ $gtidpos = *[!\ ]*  ]]
      then
        MASTER_POSITION="master_use_gtid=slave_pos"
      else
        MASTER_POSITION="master_use_gtid=current_pos"
      fi
    else
      MASTER_POSTION="MASTER_LOG_FILE='$filename', MASTER_LOG_POS=$position"
    fi
    echo
    echo "adding the grant for the replication user on $slave"
    mysql --socket=/var/lib/mysql${INSTANCEID}/mysql.sock -e "GRANT REPLICATION SLAVE ON *.* TO 'repl'@'$doner' identified by '$password'$REQUIRE_SSL; FLUSH PRIVILEGES;"
    echo
    echo "stopping the slave on $doner"
    ./ssh-expect $pass ssh $user@$doner "mysql --socket=/var/lib/mysql$INSTANCEID/mysql.sock -e \"stop slave;\""
    if [[ $gtidpos = *[!\ ]* ]]
    then
      echo "setting the gtid_slave_pos on $doner"
      ./ssh-expect $pass ssh $user@$doner "mysql --socket=/var/lib/mysql$INSTANCEID/mysql.sock -e \"SET GLOBAL gtid_slave_pos = '$gtidpos';\""
    fi
    echo
    echo "changing slave settings on $doner"
    ./ssh-expect $pass ssh $user@$doner "mysql --socket=/var/lib/mysql$INSTANCEID/mysql.sock -e \"CHANGE MASTER TO master_host='$slave', master_user='repl', MASTER_PASSWORD='$password', $MASTER_POSITION $MASTER_SSL $MASTER_PORT; start slave;\""
  fi
  exit 0;
else
  exit 1;
fi



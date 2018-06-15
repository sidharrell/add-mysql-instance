#!/bin/bash
echo "Currently, I see mysql running on ports:"
ss -tulpen | grep mysql | awk '{print $5;}' | cut -d":" -f 4 | sort -n
ID=$((`ss -tulpen | grep mysql | awk '{print $5;}' | cut -d":" -f 4 | sort -n | tail -n1`+1))
echo; echo "Are you trying to spin up instance #$ID on port $ID?"
echo "Speak now, or clean up after me later."
if [[ $BYPASS != "Y" ]]
then
  read -p "Are you sure? (y/n) " -n 1 -r;
fi
echo    # (optional) move to a new line
if [[ $BYPASS == "Y" || $REPLY =~ ^[Yy]$ ]]
then
  cp /usr/lib/systemd/system/mariadb.service /etc/systemd/system/mysql${ID}.service
  sed -i "/^ExecStart=/c ExecStart=\/usr\/sbin\/mysqld\ --defaults-file=\/etc\/my${ID}\.cnf" /etc/systemd/system/mysql${ID}.service
  cp /etc/my.cnf /etc/my${ID}.cnf
  cp -r /etc/my.cnf.d /etc/my${ID}.cnf.d
  sed -i "/^!includedir/c !includedir /etc/my${ID}.cnf.d" /etc/my${ID}.cnf
  sed -i "/^\[mysqld]/c \[mysqld]\nsocket\ =\ \/var\/lib\/mysql${ID}\/mysql\.sock\ndatadir\ =\ \/var\/lib\/mysql${ID}\/\ninnodb_data_home_dir\ =\ \/var\/lib\/mysql${ID}\/\ninnodb_log_group_home_dir\ =\ \/var\/lib\/mysql${ID}/\nport=$ID" /etc/my${ID}.cnf.d/server.cnf 
  systemctl daemon-reload
  mkdir /var/lib/mysql${ID}
  chown mysql. /var/lib/mysql${ID}
  mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql${ID}
  systemctl enable mysql${ID}
  systemctl start mysql${ID}
  exit 0;
else
  exit 1;
fi

#!/bin/bash
# Created by Ramesh Sivaraman, Percona LLC

BUILD=$(pwd)
SKIP_RQG_AND_BUILD_EXTRACT=0
sst_method="rsync"

# Ubuntu mysqld runtime provisioning
if [ "$(uname -v | grep 'Ubuntu')" != "" ]; then
  if [ "$(dpkg -l | grep 'libaio1')" == "" ]; then
    sudo apt-get install libaio1 
  fi
  if [ "$(dpkg -l | grep 'libjemalloc1')" == "" ]; then
    sudo apt-get install libjemalloc1
  fi
  if [ ! -r /lib/x86_64-linux-gnu/libssl.so.6 ]; then
    sudo ln -s /lib/x86_64-linux-gnu/libssl.so.1.0.0 /lib/x86_64-linux-gnu/libssl.so.6
  fi
  if [ ! -r /lib/x86_64-linux-gnu/libcrypto.so.6 ]; then
    sudo ln -s /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /lib/x86_64-linux-gnu/libcrypto.so.6
  fi
fi

if [[ $sst_method == "xtrabackup" ]];then
  PXB_BASE=`ls -1td percona-xtrabackup* | grep -v ".tar" | head -n1`
  if [ ! -z $PXB_BASE ];then
    export PATH="$BUILD/$PXB_BASE/bin:$PATH"
  else
    wget http://jenkins.percona.com/job/percona-xtrabackup-2.4-binary-tarball/label_exp=centos5-64/lastSuccessfulBuild/artifact/*zip*/archive.zip
    unzip archive.zip
    tar -xzf archive/TARGET/*.tar.gz 
    PXB_BASE=`ls -1td percona-xtrabackup* | grep -v ".tar" | head -n1`
    export PATH="$BUILD/$PXB_BASE/bin:$PATH"
  fi
fi

echo -e "Adding scripts: ./start_pxc | ./stop_pxc | ./node_cl | ./wipe"

if [ ! -r $BUILD/mysql-test/mysql-test-run.pl ]; then
  echo -e "mysql test suite is not available, please check.."
fi

ADDR="127.0.0.1"
RPORT=$(( RANDOM%21 + 10 ))
RBASE="$(( RPORT*1000 ))"
LADDR="$ADDR:$(( RBASE + 8 ))"
SUSER=root
SPASS=
node0="${BUILD}/node0"
keyring_node0="${BUILD}/keyring_node0"

KEY_RING_CHECK=0
if [ "$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)" != "5.7" ]; then
  mkdir -p $node0 $keyring_node0
elif [ "$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)" == "5.7" ]; then
  KEY_RING_CHECK=1
fi

echo -e "#!/bin/bash" > ./start_pxc
echo -e "NODES=\$1"  >> ./start_pxc
echo -e "PXC_MYEXTRA=\"\"" >> ./start_pxc
echo -e "PXC_START_TIMEOUT=300"  >> ./start_pxc
echo -e "KEY_RING_CHECK=$KEY_RING_CHECK"  >> ./start_pxc
echo -e "BUILD=\$(pwd)\n"  >> ./start_pxc
echo -e "echo 'Starting PXC nodes..'\n" >> ./start_pxc

echo -e "if [ -z \$NODES ]; then"  >> ./start_pxc
echo -e "  echo \"+----------------------------------------------------------------+\""  >> ./start_pxc
echo -e "  echo \"| ** Triggered default startup. Starting single node cluster  ** |\""  >> ./start_pxc
echo -e "  echo \"+----------------------------------------------------------------+\""  >> ./start_pxc
echo -e "  echo \"|  To start multiple nodes please execute script as;             |\""  >> ./start_pxc
echo -e "  echo \"|  $./start_pxc.sh 2                                             |\""  >> ./start_pxc
echo -e "  echo \"|  This would lead to start 2 node cluster                       |\""  >> ./start_pxc
echo -e "  echo \"+----------------------------------------------------------------+\""  >> ./start_pxc
echo -e "  NODES=0"  >> ./start_pxc
echo -e "else"  >> ./start_pxc
echo -e "  let NODES=NODES-1" >> ./start_pxc
echo -e "fi"  >> ./start_pxc


echo -e "if [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.7\" ]; then" >> ./start_pxc
echo -e "  MID=\"${BUILD}/bin/mysqld --no-defaults --initialize-insecure --basedir=${BUILD}\"" >> ./start_pxc
echo -e "elif [ \"$(${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1)\" == \"5.6\" ]; then" >> ./start_pxc
echo -e "  MID=\"${BUILD}/scripts/mysql_install_db --no-defaults --basedir=${BUILD}\"" >> ./start_pxc
echo -e "fi\n" >> ./start_pxc

if [ $KEY_RING_CHECK -eq 1 ]; then
  KEY_RING_OPTIONS="--early-plugin-load=keyring_file.so --keyring_file_data=$keyring_node0/keyring"
fi

echo -e "if [ ! -d \${BUILD}/node0 ]; then" >> ./start_pxc
echo -e "  \${MID} --datadir=\${BUILD}/node0  > \${BUILD}/startup_node0.err 2>&1 || exit 1;" >> ./start_pxc
echo -e "fi\n" >> ./start_pxc

echo -e "\${BUILD}/bin/mysqld --no-defaults --defaults-group-suffix=.1 \\" >> ./start_pxc
echo -e "    --basedir=\${BUILD} --datadir=\${BUILD}/node0 \\" >> ./start_pxc
echo -e "    --loose-debug-sync-timeout=600  \\" >> ./start_pxc
echo -e "    --innodb_file_per_table \$PXC_MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \\" >> ./start_pxc
echo -e "    --wsrep-provider=\${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo -e "    --wsrep_cluster_address=gcomm:// \\" >> ./start_pxc
echo -e "    --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc
echo -e "    --wsrep_provider_options=gmcast.listen_addr=tcp://$LADDR \\" >> ./start_pxc
echo -e "    --wsrep_sst_method=rsync --wsrep_sst_auth=$SUSER:$SPASS \\" >> ./start_pxc
echo -e "    --wsrep_node_address=$ADDR --innodb_flush_method=O_DIRECT \\" >> ./start_pxc
echo -e "    --core-file  --sql-mode=no_engine_substitution \\" >> ./start_pxc
echo -e "    --secure-file-priv= --loose-innodb-status-file=1 \\" >> ./start_pxc
echo -e "    --log-error=\${BUILD}/node0/node1.err $KEY_RING_OPTIONS \\" >> ./start_pxc
echo -e "    --socket=\${BUILD}/node0/socket.sock --log-output=none \\" >> ./start_pxc
echo -e "    --port=$RBASE --server-id=1 --wsrep_slave_threads=2 > \${BUILD}/node0/node0.err 2>&1 &\n" >> ./start_pxc

echo -e "for X in \$(seq 0 \${PXC_START_TIMEOUT}); do" >> ./start_pxc
echo -e "  sleep 1" >> ./start_pxc
echo -e "  if \${BUILD}/bin/mysqladmin -uroot -S\${BUILD}/node0/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo -e "    break" >> ./start_pxc
echo -e "  fi" >> ./start_pxc
echo -e "done\n\n" >> ./start_pxc

echo -e "echo -e \"\${BUILD}/bin/mysqladmin -uroot -S\${BUILD}/node0/socket.sock shutdown\" > ./stop_pxc" >> ./start_pxc
echo -e "echo -e \"echo 'Server on socket \${BUILD}/node0/socket.sock with datadir \${BUILD}/node0 halted'\" >> ./stop_pxc" >> ./start_pxc
echo -e "echo -e \"if [ -r ./stop_pxc ]; then ./stop_pxc 2>/dev/null 1>&2; fi\" > ./wipe" >> ./start_pxc
echo -e "echo -e \"if [ -d \${BUILD}/node0.PREV ]; then rm -Rf \${BUILD}/node0.PREV.older; mv \${BUILD}/node0.PREV \${BUILD}/node0.PREV.older; fi;mv \${BUILD}/node0 \${BUILD}/node0.PREV\" >> ./wipe" >> ./start_pxc
echo -e "echo -e \"\$BUILD/bin/mysql -A -uroot -S\${BUILD}/node0/socket.sock --prompt \\\"node0> \\\"\" > ./0_node_cli" >> ./start_pxc

echo -e "WSREP_CLUSTER="gcomm://$LADDR"" >> ./start_pxc
echo -e "RBASE=$RBASE\n" >> ./start_pxc

echo -e "function start_multi_node(){" >> ./start_pxc
echo -e "  for i in \`seq 1 \$NODES\`;do" >> ./start_pxc
echo -e "    RBASE1=\"\$(( RBASE + ( 100 * \$i ) ))\"" >> ./start_pxc
echo -e "    LADDR1=\"$ADDR:\$(( RBASE1 + 8 ))\"" >> ./start_pxc
echo -e "    WSREP_CLUSTER="\$WSREP_CLUSTER,gcomm://\$LADDR1"" >> ./start_pxc
echo -e "    node1=\"${BUILD}/node\$i\"" >> ./start_pxc
echo -e "    keyring_node1=\"${BUILD}/keyring_node\$i\"\n" >> ./start_pxc

echo -e "    if [ \"\$(\${BUILD}/bin/mysqld --version | grep -oe '5\.[567]' | head -n1 )\" != \"5.7\" ]; then" >> ./start_pxc
echo -e "      mkdir -p \$node1 \$keyring_node1" >> ./start_pxc
echo -e "    fi" >> ./start_pxc

echo -e "    if [ ! -d \$node1 ]; then" >> ./start_pxc
echo -e "      \${MID} --datadir=\$node1  > \${BUILD}/startup_node\$i.err 2>&1 || exit 1;" >> ./start_pxc
echo -e "    fi\n" >> ./start_pxc

echo -e "    if [ \$KEY_RING_CHECK -eq 1 ]; then" >> ./start_pxc
echo -e "      KEY_RING_OPTIONS=\"--early-plugin-load=keyring_file.so --keyring_file_data=\$keyring_node1/keyring\"" >> ./start_pxc
echo -e "    fi" >> ./start_pxc

echo -e "    \${BUILD}/bin/mysqld --no-defaults --defaults-group-suffix=.1 \\" >> ./start_pxc
echo -e "      --basedir=\${BUILD} --datadir=\$node1 \\" >> ./start_pxc
echo -e "      --loose-debug-sync-timeout=600  \\" >> ./start_pxc
echo -e "      --innodb_file_per_table \$PXC_MYEXTRA --innodb_autoinc_lock_mode=2 --innodb_locks_unsafe_for_binlog=1 \\" >> ./start_pxc
echo -e "      --wsrep-provider=\${BUILD}/lib/libgalera_smm.so \\" >> ./start_pxc
echo -e "      --wsrep_cluster_address=\$WSREP_CLUSTER \\" >> ./start_pxc
echo -e "      --wsrep_node_incoming_address=$ADDR \\" >> ./start_pxc
echo -e "      --wsrep_provider_options=gmcast.listen_addr=tcp://\$LADDR1 \\" >> ./start_pxc
echo -e "      --wsrep_sst_method=rsync --wsrep_sst_auth=$SUSER:$SPASS \\" >> ./start_pxc
echo -e "      --wsrep_node_address=$ADDR --innodb_flush_method=O_DIRECT \\" >> ./start_pxc
echo -e "      --core-file  --sql-mode=no_engine_substitution \\" >> ./start_pxc
echo -e "      --secure-file-priv= --loose-innodb-status-file=1 \\" >> ./start_pxc
echo -e "      --log-error=\$node1/node\$i.err \$KEY_RING_OPTIONS \\" >> ./start_pxc
echo -e "      --socket=\$node1/socket.sock --log-output=none \\" >> ./start_pxc
echo -e "      --port=\$RBASE1 --server-id=1 --wsrep_slave_threads=2 > \$node1/node\$i.err 2>&1 &\n" >> ./start_pxc

echo -e "    for X in \$(seq 0 \${PXC_START_TIMEOUT}); do" >> ./start_pxc
echo -e "      sleep 1" >> ./start_pxc
echo -e "      if \${BUILD}/bin/mysqladmin -uroot -S\$node1/socket.sock ping > /dev/null 2>&1; then" >> ./start_pxc
echo -e "        break" >> ./start_pxc
echo -e "      fi" >> ./start_pxc
echo -e "    done" >> ./start_pxc

echo -e "    echo -e \"\${BUILD}/bin/mysqladmin -uroot -S\$node1/socket.sock shutdown\" >> ./stop_pxc "  >> ./start_pxc
echo -e "    echo -e \"echo 'Server on socket \$node1/socket.sock with datadir \$node1 halted'\" >> ./stop_pxc"  >> ./start_pxc
echo -e "    echo -e \"if [ -d \$node1.PREV ]; then rm -Rf \$node1.PREV.older; mv \$node1.PREV \$node1.PREV.older; fi;mv \$node1 \$node1.PREV\" >> ./wipe"  >> ./start_pxc
echo -e "    echo -e \"\$BUILD/bin/mysql -A -uroot -S\$node1/socket.sock --prompt \\\"node\$i> \\\"\" > \${BUILD}/\$i\\_node_cli "  >> ./start_pxc
echo -e "    chmod +x  \${BUILD}/\$i\\_node_cli  "  >> ./start_pxc

echo -e "  done\n" >> ./start_pxc
echo -e "}\n" >> ./start_pxc

echo -e "start_multi_node" >> ./start_pxc
echo -e "chmod +x ./start_pxc ./stop_pxc ./*node_cli ./wipe" >> ./start_pxc

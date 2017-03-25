#!/bin/bash

# Backup Accounts
# Backup MySQL (message index)
# Backup LDAP

FILES=/etc/zbackup/*.conf

[ -d "/usr/share/zbackup" ] || mkdir /usr/share/zbackup
[ -d "/etc/zbackup" ] || mkdir /etc/zbackup

function _help {
    echo "@ zbackup params"
    echo "-i install"
    echo "-e execute"
    echo "-l list all configured"
    echo "-z zabbix auto discovery LLD"
    echo "-c check zabbix routine"
}

function _check_dependencies {
    #check zmbkpose
    if [ ! -f "/usr/bin/zmbkpose" ];then
        #check git
        git clone https://github.com/bggo/Zmbkpose.git /tmp/zmbkpose
        cd /tmp/zmbkpose
        chmod +x install.sh
        ./install.sh
        exit 0
    fi
}

function install_zbackup {
    echo "Installing at /usr/bin"
    cp -f $0 /usr/bin/zbackup.sh
    ln -s /usr/bin/zbackup.sh /usr/bin/zbackup 2> /dev/null
    if [ -f "conf/zimbra.conf" ];then
        cp -f conf/zimbra.conf /etc/zbackup/zimbra.conf.example 2> /dev/null
    fi
    echo "Done!"
}

function zabbix_auto_discovery {
    file="/tmp/file_zabbix_zimbra"
    echo -e "{" > $file
    echo -e "\t\"data\":[" >> $file
    first=1
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES
    do
        if [ $first == 0 ];then
            echo -e "\t," >> $file
        fi
        first=0
        i=`echo $f | rev | cut -d'/' -f 1 | rev`
        echo -e "\t{\"{#ZBACKUP}\":\"$i\"}" >> $file
    done
    echo -e "\t]" >> $file
    echo -e "}" >> $file
    cat $file
    rm -f $file
    IFS=$SAVEIFS
}

function zbackup_check_status {
    cat /usr/share/zbackup/$* | cut -d, -f2  
}

function zbackup_check_lastrun {
    lr=`cat /usr/share/zbackup/$* | cut -d, -f1`
    now=`date +%s`
    echo `expr $now - $lr`
}

function list_backups {
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES
    do
        echo "$f"
    done
    IFS=$SAVEIFS
}

function backup_mysql {
    #MYSQL BACKUP
    if [ ! `whoami` == "zimbra" ];then
        echo "Not zimbra user"
        exit 2;
    fi
    source ~/bin/zmshutil
    zmsetvars 
    /opt/zimbra/common/bin/mysqldump --user=root --password=$mysql_root_password --socket=$mysql_socket --all-databases --single-transaction --flush-logs > $dest/mysql_$day.sql
    cd $dest/
    gzip -f $dest/mysql_$day.sql
}

function backup_ldap {
    if [ ! `whoami` == "zimbra" ];then
        echo "Not zimbra user"
        exit 2;
    fi
    #LDAP BACKUP
    /opt/zimbra/libexec/zmslapcat -c /tmp/ldap.$day 
    mv /tmp/ldap.$day/ldap-config.bak $dest/ldap-config.$day.bak
    /opt/zimbra/libexec/zmslapcat /tmp/ldap.$day
    mv /tmp/ldap.$day/ldap.bak $dest/ldap.$day.bak 
    rm -rf /tmp/ldap.$day
}

function reset_variables {
    unset mail
    unset name
    unset domain
    unset dest
    unset orig
    unset before
    unset after
    unset history
    unset ext_ids
    unset full
    unset incremental
    unset forceumount
}

function do_backup {
    #set variables
    reset_variables
    source $1
    routine=`echo $1 | rev | cut -d'/' -f 1 | rev`
    log_file="/tmp/$routine.log"
    #check dependencies
    _check_dependencies
    #pre requisites
    [ -d "$dest" ] || mkdir -p $dest
    #check if already running
    testrunning=`ps aux|grep zmbkpose|grep -v grep`
    if [ "$testrunning" == "" ];then
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Init backup $routine" > $log_file
    else
        if [ ! -z ${mail+x} ];then 
            echo "Backup Zimbra already running @ $(date +%d/%m/%Y) - $(date +%H:%M)" | mail -s "Backup Zimbra ($name/Already running)" $mail
        fi
        exit 0
    fi
    #check if force umount
    if [ "$forceumount" == "y" ];then
        umount $dest 2> /dev/null
        sleep 10
    fi
    #before
    if [ ! -z ${before+x} ];then 
        $before
        if [ ! $? -eq 0 ]; then
             echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Error executing before command" >> $log_file 
             if [ ! -z ${mail+x} ];then 
                cat $log_file | mail -s "Backup Zimbra ($name/Error)" $mail
             fi
             echo "$(date +%s),999" > /usr/share/zbackup/$routine
             exit 0
        fi
        sleep 10
    fi
    #check if have to umount $dest
    if [ ! -z ${ext_ids+x} ];then 
        umount $dest 2> /dev/null
        sleep 2
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Mounting volume" >> $log_file 
        for i in "${ext_ids[@]}"
        do
            mount $i $dest 2> /dev/null
            if [ $? -eq 0 ]; then
                echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Mounted $i" >> $log_file
            fi
        done
        #check if mounted
        mountpoint $dest
        if [ ! $? -eq 0 ]; then
            echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Not mounted - Error" >> $log_file
            echo "$(date +%s),9991" > /usr/share/zbackup/$routine
            exit 0
        fi
    fi
    
    #delete
    if [ ! -z ${history+x} ];then
      su - zimbra -c "/usr/bin/zmbkpose -d $history"
    fi

    #check if full or incremental and do ACCOUNTS BACKUP
    day=`date +%w`
    if [[ " ${full[*]} " == *" $day "* ]]; then
        #full
        su - zimbra -c "/usr/bin/zmbkpose -f"
    fi
    if [[ " ${incremental[*]} " == *" $day "* ]]; then
        #incremental
        su - zimbra -c "/usr/bin/zmbkpose -i"
    fi

    su - zimbra -c "/usr/bin/zbackup -a"

    #umount after backup
    if [ ! -z ${ext_ids+x} ];then 
        sleep 7
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Umounting volume" >> $log_file 
        umount $dest 2> /dev/null
    fi
    #run after

    if [ ! -z ${after+x} ];then 
        $after
        if [ ! $? -eq 0 ]; then
             echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Error executing after command" >> $log_file 
             if [ ! -z ${mail+x} ];then 
                cat $log_file | mail -s "Backup Zimbra ($name/Error)" $mail
             fi
             echo "$(date +%s),9992" > /usr/share/zbackup/$routine
             exit 0
        fi
        sleep 10
    fi

    if [ "$zmbkposestatus" == "0" ];then
        #backup ok
        status="OK"
    else
        #backup com erro
        status="ERROR"
    fi

    #saving status of zabbix
    echo "$(date +%s),$zmbkposestatus" > /usr/share/zbackup/$routine
    #done backup
    echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Backup ended" >> $log_file

    #send e-mail
    if [ ! -z ${mail+x} ];then
        echo "$(date +%d/%m/%Y) - $(date +%H:%M) @ Sending e-mail" >> $log_file
        cat $log_file | mail -s "Backup ($name/$status)" $mail
    fi

    #auto-update
    wget "https://raw.githubusercontent.com/khony/backup-zbackup/master/zbackup.sh" -O /tmp/zbackup.sh
    if [ $? -eq 0 ]; then
        chmod +x /tmp/zbackup.sh > /dev/null
        /tmp/zbackup.sh -i > /dev/null
    fi
}

function execute_backup {
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in $FILES;do
        do_backup "$f"
    done
    IFS=$SAVEIFS
}

while getopts zeailhs:c:d: option
do
        case "${option}"
        in
                a) # backup mysql and ldap
                  backup_mysql
                  backup_ldap
                  exit 0
                  ;;
                z) # zabbix auto discovery
                  zabbix_auto_discovery
                  exit 0
                  ;;
                s) #zabbix check routine
                  zbackup_check_status ${OPTARG}
                  exit 0
                  ;;
                c) #zabbix check last run
                  zbackup_check_lastrun ${OPTARG}
                  exit 0
                  ;;
                i) #install rbackup
                  install_zbackup
                  ;;
                l) #list backups
                  list_backups
                  exit 0
                  ;;
                d) #dir of backups
                  FILES="${OPTARGS}"
                  execute_backup
                  exit 0
                  ;;
                e) #do backups
                  execute_backup
                  exit 0
                  ;;
                h)
                  _help
                  ;;
                \?) #do backups
                  echo "-h for help"
                  execute_backup
                  exit 0
                  ;;
        esac
done
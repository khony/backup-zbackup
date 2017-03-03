#===== do disaster recovery =====
su - zimbra
source ~/bin/zmshutil
zmsetvars
#mysql
/opt/zimbra/common/bin/mysqldump --user=root --password=$mysql_root_password --socket=$mysql_socket \
  --all-databases --single-transaction --flush-logs > bkp_mysql.sql
#ldap
/opt/zimbra/libexec/zmslapcat -c /opt/zimbra/backup
/opt/zimbra/libexec/zmslapcat /opt/zimbra/backup

#===== recovery =====
su - zimbra 
mv /opt/zimbra/conf/localconfig.xml /opt/zimbra/conf/localconfig.xml.original
#copy localconfig.xml
cp /tmp/localconfig.xml /opt/zimbra/conf/localconfig.xml 
#carregar variaveis
source ~/bin/zmshutil ; zmsetvars
#ldap
ldap stop
cd /opt/zimbra/data/ldap
mv mdb mdb.old
mkdir -p mdb/db
cd /opt/zimbra/data/ldap
mv config config.bak
mkdir config
/opt/zimbra/common/sbin/slapadd -q -n 0 -F /opt/zimbra/data/ldap/config -cv -l /tmp/ldap-config.bak
/opt/zimbra/common/sbin/slapadd -q -b "" -F /opt/zimbra/data/ldap/config -cv -l /backup/ldap.bak
#mysql
>> matar processos que estejam rodando do mysql
cd /opt/zimbra/db
mv data data_old
/opt/zimbra/libexec/zmmyinit --sql_root_pw $mysql_root_password
#trocar senha do usuario zimbra
zmmypasswd A5An.VFBV1aHE10ADbkDT7hcVG8t
mysql --user=root --password=$mysql_root_password < /backup/mysql_3.sql
#certificados
zmlocalconfig -e ssl_allow_accept_untrusted_certs=true
zmlocalconfig -e ssl_allow_untrusted_certs=true
/opt/zimbra/bin/zmcertmgr createca -new
/opt/zimbra/bin/zmcertmgr deployca
/opt/zimbra/bin/zmcertmgr createcrt -new -days 3650
/opt/zimbra/bin/zmcertmgr deploycrt self
/opt/zimbra/bin/zmcertmgr deployca -locally

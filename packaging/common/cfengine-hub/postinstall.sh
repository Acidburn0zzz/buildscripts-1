INSTLOG=/var/log/CFEngineHub-Install.log
exec > $INSTLOG 2>&1
set -x

#
# Make sure the cfapache user has a home folder and populate it
#
MP_APACHE_USER=cfapache
if [ -d "$PREFIX/$MP_APACHE_USER" ];
then
	echo "cfapache folder already exists, deleting it"
	rm -rf $PREFIX/$MP_APACHE_USER
fi
/usr/sbin/usermod -d $PREFIX/$MP_APACHE_USER $MP_APACHE_USER
mkdir -p $PREFIX/$MP_APACHE_USER/.ssh
chown -R $MP_APACHE_USER:$MP_APACHE_USER $PREFIX/$MP_APACHE_USER
echo "Host *
StrictHostKeyChecking no
UserKnownHostsFile=/dev/null" >> $PREFIX/$MP_APACHE_USER/.ssh/config

#
# Generate a host key
#
if [ ! -f $PREFIX/ppkeys/localhost.priv ]; then
    $PREFIX/bin/cf-key >/dev/null || :
fi

if [ ! -f $PREFIX/masterfiles/promises.cf ]; then
    /bin/cp -R $PREFIX/share/NovaBase/masterfiles $PREFIX/
    touch $PREFIX/masterfiles/cf_promises_validated
    find $PREFIX/masterfiles -type d -exec chmod 700 {} \;
    find $PREFIX/masterfiles -type f -exec chmod 600 {} \;
fi

#
# Copy the stock package modules for the new installations
#
(
  if ! [ -d $PREFIX/modules/packages ]; then
    mkdir -p $PREFIX/modules/packages
  fi
  if cd $PREFIX/share/NovaBase/modules/packages; then
    for module in *; do
      if ! [ -f $PREFIX/modules/packages/$module ]; then
        cp $module $PREFIX/modules/packages
      fi
    done
  fi
)

if [ -f $PREFIX/lib/php/mcrypt.so ]; then
  /bin/rm -f $PREFIX/lib/php/mcrypt.*
fi

if [ -f $PREFIX/lib/php/curl.so ]; then
  /bin/rm -f $PREFIX/lib/php/curl.*
fi

#
#Copy necessary Files and permissions
#
cp $PREFIX/lib/php/*.ini $PREFIX/httpd/php/lib
cp $PREFIX/lib/php/*.so $PREFIX/httpd/php/lib/php/extensions/no-debug-non-zts-20131226

#Change keys in files
if [ -f $PREFIX/CF_CLIENT_SECRET_KEY.tmp ]; then
  UUID=$(tr -d '\n\r' < $PREFIX/CF_CLIENT_SECRET_KEY.tmp)
else
  UUID=$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
fi
sed -i s/CFE_SESSION_KEY/"$UUID"/ $PREFIX/share/GUI/application/config/config.php
sed -i s/CFE_CLIENT_SECRET_KEY/"$UUID"/ $PREFIX/share/GUI/application/config/appsettings.php
sed -i s/CFE_CLIENT_SECRET_KEY/"$UUID"/ $PREFIX/share/db/ootb_settings.sql

cp -r $PREFIX/share/GUI/* $PREFIX/httpd/htdocs
mkdir -p $PREFIX/httpd/htdocs/tmp
mv $PREFIX/httpd/htdocs/Apache-htaccess $PREFIX/httpd/htdocs/.htaccess
chmod 755 $PREFIX/httpd
chown -R root:root $PREFIX/httpd/htdocs
chmod a+rx $PREFIX/httpd/htdocs/api/dc-scripts/*.sh
chmod a+rx $PREFIX/httpd/htdocs/api/dc-scripts/*.pl

# plugins directory, empty by default
mkdir -p ${PREFIX}/plugins
chown -R root:root ${PREFIX}/plugins
chmod 700 ${PREFIX}/plugins

#these directories should be write able by apache
chown root:$MP_APACHE_USER $PREFIX/httpd/logs
chmod 775 $PREFIX/httpd/logs
chown $MP_APACHE_USER:$MP_APACHE_USER $PREFIX/httpd/htdocs/tmp
chown -R $MP_APACHE_USER:$MP_APACHE_USER $PREFIX/httpd/htdocs/api/static
chown $MP_APACHE_USER:$MP_APACHE_USER $PREFIX/httpd/htdocs/application/logs

#
# Do all the prelimenary Design Center setup only on the first install of cfengine package
#
if ! is_upgrade; then
  # This folder is required for Design Center and Mission Portal to talk to each other
  DCWORKDIR=/opt/cfengine
  $PREFIX/design-center/bin/cf-sketch --inputs=$PREFIX/design-center --installsource=$PREFIX/share/NovaBase/sketches/cfsketches.json --install-all
  mkdir -p $DCWORKDIR/userworkdir/admin/.ssh
  mkdir -p $DCWORKDIR/stage_backup
  mkdir -p $DCWORKDIR/dc-scripts
  mkdir -p $DCWORKDIR/masterfiles_staging
  mkdir -p $DCWORKDIR/masterfiles.git

  touch $DCWORKDIR/userworkdir/admin/.ssh/id_rsa.pvt
  chmod 600 $DCWORKDIR/userworkdir/admin/.ssh/id_rsa.pvt

  cat > $DCWORKDIR/dc-scripts/params.sh <<EOHIPPUS
#!/bin/bash
ROOT="$DCWORKDIR/masterfiles_staging"
GIT_URL="$DCWORKDIR/masterfiles.git"
GIT_BRANCH="master"
GIT_WORKING_BRANCH="CF_WORKING_BRANCH"
GIT_EMAIL="default-committer@your-cfe-site.com"
GIT_AUTHOR="Default Committer"
PKEY="$DCWORKDIR/userworkdir/admin/.ssh/id_rsa.pvt"
SCRIPT_DIR="$PREFIX/httpd/htdocs/api/dc-scripts"
VCS_TYPE="GIT"
export PATH="\${PATH}:$PREFIX/bin"
export PKEY="\${PKEY}"
export GIT_SSH="\${SCRIPT_DIR}/ssh-wrapper.sh"
EOHIPPUS

  # The runfile key in the below JSON is not needed anymore, all the
  # values in it are OK by default, especially the runfile location,
  # which is the first element of repolist plus `/meta/api-runfile.cf`.

  cat > $DCWORKDIR/userworkdir/admin/api-config.json <<EOHIPPUS
{
  "log":"STDERR",
  "log_level":"3",
  "repolist":["sketches"],
  "recognized_sources":["$PREFIX/design-center/sketches"],
  "constdata":"$PREFIX/design-center/tools/cf-sketch/constdata.conf",
  "vardata":"$DCWORKDIR/userworkdir/admin/masterfiles/sketches/meta/vardata.conf",
  "runfile": {"location":"$DCWORKDIR/userworkdir/admin/masterfiles/sketches/meta/api-runfile.cf"}
}
EOHIPPUS

  chmod 700 $DCWORKDIR/dc-scripts/params.sh

  chown -R $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR/userworkdir
  chown -R $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR/dc-scripts
  chown -R $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR/stage_backup
  chown -R $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR/masterfiles.git

  chown $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR
  cp -R $PREFIX/masterfiles/* $DCWORKDIR/masterfiles_staging
  chown -R $MP_APACHE_USER:$MP_APACHE_USER $DCWORKDIR/masterfiles_staging

  chmod 700 $DCWORKDIR/stage_backup
  chmod -R 700 $DCWORKDIR/userworkdir

  GIT=$PREFIX/bin/git
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT init")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT config user.email admin@cfengine.com")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT config user.name admin")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "(echo '/cf_promises_*'; echo '.*.sw[po]'; echo '*~'; echo '\\#*#') >.gitignore")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT add .gitignore")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT commit -m 'Ignore cf_promise_*'")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT add *")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT commit -m 'Initial pristine masterfiles'")

  (cd $DCWORKDIR/ && su $MP_APACHE_USER -c "$GIT clone --no-hardlinks --bare $DCWORKDIR/masterfiles_staging $DCWORKDIR/masterfiles.git")
  find "$DCWORKDIR/masterfiles.git" -type d -exec chmod 700 {} \;
  find "$DCWORKDIR/masterfiles.git" -type f -exec chmod 600 {} \;

  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT branch CF_WORKING_BRANCH")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT remote rm origin")
  (cd $DCWORKDIR/masterfiles_staging && su $MP_APACHE_USER -c "$GIT remote add origin $DCWORKDIR/masterfiles.git")

  if [ ! -f /usr/bin/curl ]; then
    ln -sf $PREFIX/bin/curl /usr/bin/curl
  fi
fi

if [ -f $PREFIX/bin/cf-twin ]; then
    /bin/rm $PREFIX/bin/cf-twin
fi
/bin/cp $PREFIX/bin/cf-agent $PREFIX/bin/cf-twin

#
#MAN PAGE RELATED
#
MAN_CONFIG=""
MAN_PATH=""
case "`package_type`" in
  rpm)
    if [ -f /etc/SuSE-release ];
    then
      # SuSE
      MAN_CONFIG="/etc/manpath.config"
      MAN_PATH="MANDATORY_MANPATH"
    else
      # RH/CentOS
      MAN_CONFIG="/etc/man.config"
      MAN_PATH="MANPATH"
    fi
    ;;
  deb)
    MAN_CONFIG="/etc/manpath.config"
    MAN_PATH="MANDATORY_MANPATH"
    ;;
  *)
    echo "Unknown manpath, should not happen!"
    ;;
esac

if [ -f "$MAN_CONFIG" ];
then
  MAN=`cat "$MAN_CONFIG"| grep cfengine`
  if [ -z "$MAN" ]; then
    echo "$MAN_PATH     $PREFIX/share/man" >> "$MAN_CONFIG"
  fi
fi

for i in cf-agent cf-promises cf-key cf-execd cf-serverd cf-monitord cf-runagent cf-hub;
do
  if [ -f $PREFIX/bin/$i -a -d /usr/local/sbin ]; then
    ln -sf $PREFIX/bin/$i /usr/local/sbin/$i || true
  fi
  if [ -f /usr/share/man/man8/$i.8.gz ]; then
    rm -f /usr/share/man/man8/$i.8.gz
  fi
  $PREFIX/bin/$i -M > /usr/share/man/man8/$i.8 && gzip /usr/share/man/man8/$i.8
done

#
# Generate a certificate for Mission Portal
# The certificate will be named $(hostname -f).cert and the corresponding key should be named $(hostname -f).key.
#
CFENGINE_MP_DEFAULT_CERT_LOCATION="$PREFIX/httpd/ssl/certs"
CFENGINE_MP_DEFAULT_KEY_LOCATION="$PREFIX/httpd/ssl/private"
CFENGINE_OPENSSL="$PREFIX/bin/openssl"
mkdir -p $CFENGINE_MP_DEFAULT_CERT_LOCATION
mkdir -p $CFENGINE_MP_DEFAULT_KEY_LOCATION
CFENGINE_LOCALHOST=$(hostname -f)
CFENGINE_MP_CERT=$CFENGINE_MP_DEFAULT_CERT_LOCATION/$CFENGINE_LOCALHOST.cert
CFENGINE_MP_KEY=$CFENGINE_MP_DEFAULT_KEY_LOCATION/$CFENGINE_LOCALHOST.key
if [ ! -f $CFENGINE_MP_CERT ]; then
  $CFENGINE_OPENSSL req -new -newkey rsa:2048 -days 3650 -nodes -x509 -utf8 -sha256 -subj "/CN=$CFENGINE_LOCALHOST" -keyout $CFENGINE_MP_KEY  -out $CFENGINE_MP_CERT -config $PREFIX/ssl/openssl.cnf
fi
#
# Modify the Apache configuration with the corresponding key and certificate
#
sed -i -e s:INSERT_CERT_HERE:$CFENGINE_MP_CERT:g $PREFIX/httpd/conf/extra/httpd-ssl.conf
sed -i -e s:INSERT_CERT_KEY_HERE:$CFENGINE_MP_KEY:g $PREFIX/httpd/conf/extra/httpd-ssl.conf

#POSTGRES RELATED
#
if [ ! -d $PREFIX/state/pg/data ]; then

  mkdir -p $PREFIX/state/pg/data
  chown -R cfpostgres $PREFIX/state/pg
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/initdb -D $PREFIX/state/pg/data")
  touch /var/log/postgresql.log
  chown cfpostgres /var/log/postgresql.log

  # Generating a new postgresql.conf if enough total memory is present
  #
  # If total memory is lower than 3GB, we use the default pgsql conf file
  # If total memory is beyond 64GB, we use a shared_buffers of 16G
  # Otherwise, we use a shared_buffers equal to 25% of total memory
  total=`cat /proc/meminfo |grep "^MemTotal:.*[0-9]\+ kB"|awk '{print $2}'`

  echo "$total" | grep -q '^[0-9]\+$'
  if [ $? -ne 0 ] ;then
    echo "Error calculating total memory for setting postgresql shared_buffers";
  else
    upper=$(( 64 * 1024 * 1024 ))  #in KB
    lower=$(( 3 * 1024 * 1024 ))   #in KB

    if [ "$total" -gt "$lower" ]; then
      maint="2GB"
      if [ "$total" -ge "$upper" ]; then
        shared="16GB"
        effect="11GB"        #70% of 16G
      else
        shared=$(( $total * 25 / 100 / 1024 ))   #in MB
        shared="$shared""MB"
        effect=$(( $total * 70 / 100 / 1024 ))   #in MB
        effect="$effect""MB"
      fi
      sed -i -e "s/^.effective_cache_size.*/effective_cache_size=$effect/" $PREFIX/share/postgresql/postgresql.conf.cfengine
      sed -i -e "s/^shared_buffers.*/shared_buffers=$shared/" $PREFIX/share/postgresql/postgresql.conf.cfengine
      sed -i -e "s/^maintenance_work_mem.*/maintenance_work_mem=$maint/" $PREFIX/share/postgresql/postgresql.conf.cfengine
      cp $PREFIX/share/postgresql/postgresql.conf.cfengine $PREFIX/state/pg/data/postgresql.conf
      chown cfpostgres $PREFIX/state/pg/data/postgresql.conf
    else
      echo "Warning: not enough total memory needed to set shared_buffers=2GB"
    fi
  fi
fi

(cd /tmp && su cfpostgres -c "$PREFIX/bin/pg_ctl -w -D $PREFIX/state/pg/data -l /var/log/postgresql.log start")

#make sure that server is up and listening
TRYNO=1
LISTENING=no
echo -n "pinging pgsql server"
while [ $TRYNO -le 10 ]
do
  echo -n .
  ALIVE=$(cd /tmp && su cfpostgres -c "$PREFIX/bin/psql -l 1>/dev/null 2>/dev/null")

  if [ $? -eq 0 ];then
    LISTENING=yes
    break
  fi

  sleep 1
  TRYNO=`expr $TRYNO + 1`
done
echo done

if [ "$LISTENING" = "no" ]
then
  echo "Couldnot create necessary database and users, make sure Postgres server is running.."
else
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/createdb -E SQL_ASCII --lc-collate=C --lc-ctype=C -T template0 cfdb")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb -f $PREFIX/share/db/schema.sql")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/createuser -S -D -R -w $MP_APACHE_USER")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/createuser -d -a -w root")

  #create database for MISSION PORTAL
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/createdb -E SQL_ASCII --lc-collate=C --lc-ctype=C -T template0 cfmp")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfmp -f $PREFIX/share/GUI/phpcfenginenova/create_cfmppostgres_user.sql")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfmp -f $PREFIX/share/GUI/phpcfenginenova/pgschema.sql")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfmp -f $PREFIX/share/GUI/phpcfenginenova/ootb_import.sql")

  #import stored function for MP into cfdb
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb -f $PREFIX/share/GUI/phpcfenginenova/cfdb_import.sql")

  #create database for hub internal data
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/createdb -E SQL_ASCII --lc-collate=C --lc-ctype=C -T template0 cfsettings")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfsettings -f $PREFIX/share/db/schema_settings.sql")
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfsettings -f $PREFIX/share/db/ootb_settings.sql")

  #revoke create permission on public schema for cfdb database
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb") << EOF
    REVOKE CREATE ON SCHEMA public FROM public;
EOF

  #grant permission for apache user to use the cfdb database
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb") << EOF
    GRANT ALL ON DATABASE cfdb TO $MP_APACHE_USER;
EOF

  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb") << EOF
    GRANT SELECT, DELETE ON ALL TABLES IN SCHEMA PUBLIC TO $MP_APACHE_USER;
EOF

  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfdb") << EOF
    ALTER DEFAULT PRIVILEGES FOR ROLE root,cfpostgres IN SCHEMA PUBLIC GRANT SELECT ON TABLES TO PUBLIC;
EOF

  #grant permission for apache user to use the cfsettings database
  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfsettings") << EOF
    GRANT ALL ON DATABASE cfsettings TO $MP_APACHE_USER;
EOF

  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfsettings") << EOF
    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $MP_APACHE_USER;
EOF

  (cd /tmp && su cfpostgres -c "$PREFIX/bin/psql cfsettings") << EOF
    ALTER DEFAULT PRIVILEGES FOR ROLE root,cfpostgres IN SCHEMA PUBLIC GRANT SELECT ON TABLES TO PUBLIC;
EOF

fi

#
# Apache related
#
mkdir -p $PREFIX/config

#
#REDIS RELATED
#
cat > $PREFIX/config/redis.conf << EOF
daemonize yes
pidfile $PREFIX/redis-server.pid
unixsocket /tmp/redis.sock
unixsocketperm 755
bind 127.0.0.1
EOF

##
# Start Apache server
#
$PREFIX/httpd/bin/apachectl start

#Mission portal
#
CFE_ROBOT_PWD=$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
$PREFIX/httpd/php/bin/php $PREFIX/httpd/htdocs/index.php cli_tasks create_cfe_robot_user $CFE_ROBOT_PWD

# Shut down Apache and Postgres again, because we may need them to start through
# systemd later.
$PREFIX/httpd/bin/apachectl stop
(cd /tmp && su cfpostgres -c "$PREFIX/bin/pg_ctl stop -D $PREFIX/state/pg/data -m smart")

#
# Delete temporarily stored key.
#
rm -f $PREFIX/CF_CLIENT_SECRET_KEY.tmp

#
# Register CFEngine initscript, if not yet.
#
if ! is_upgrade; then
  if [ -x /bin/systemctl ]; then
    /bin/systemctl enable cfengine3 > /dev/null 2>&1
  else
    case "`os_type`" in
      redhat)
        chkconfig --add cfengine3
        ;;
      debian)
        update-rc.d cfengine3 defaults
        ;;
    esac
  fi
fi

# Do not test for existence of $PREFIX/policy_server.dat, since we want the
# web service to start. The script should take care of detecting that we are
# not bootstrapped.
if ! [ -f "$PREFIX/UPGRADED_FROM.txt" ] || egrep '3\.([0-6]|7\.0)' "$PREFIX/UPGRADED_FROM.txt" > /dev/null; then
  # Versions <= 3.7.0 are unreliable in their daemon killing. Kill them one
  # more time now that we have upgraded.
  platform_service cfengine3 stop
fi
platform_service cfengine3 start

rm -f "$PREFIX/UPGRADED_FROM.txt"

exit 0

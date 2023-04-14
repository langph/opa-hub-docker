#!/bin/bash
function waitForContainer {
    local container=$1
    
    until [ "`docker inspect -f {{.State.Running}} $container`" == "true" ]; do
        echo Waiting for container $container to start
        sleep 5
    done;
    echo $container is running
    
    until [ "`docker inspect -f {{.State.Health.Status}} $container`" == "healthy" ]; do
        echo Waiting for container $container to register as healthy
        sleep 5
    done;
    echo $container is healthy
}

echo Starting MySQL container
if ! docker run --name opa-mysql-full -e MYSQL_ROOT_PASSWORD=Passw0rd -e MYSQL_ALLOW_EMPTY_PASSWORD=true -p 3306:3306 -e  MYSQL_USER=opa -e  MYSQL_PASSWORD=Passw0rd1 -v /share/CACHEDEV1_DATA/AppSettings/mysql/conf.d:/etc/mysql/conf.d --health-cmd="mysqladmin --password=Passw0rd ping --silent" -d mysql:5.7.41; then
    exit 1
fi

echo Starting Weblogic container
if ! docker run --name opa-weblogic-full -v /share/CACHEDEV1_DATA/AppSettings/weblogic/properties:/u01/oracle/properties -p 7001:7001 -e ADMINISTRATION_PORT_ENABLED=false --link opa-mysql-full:opa-mysql-full --health-cmd="curl -f http://10.0.1.100:7001/console || exit 1" -d container-registry.oracle.com/middleware/weblogic:12.2.1.4; then
    exit 1
fi

waitForContainer opa-mysql-full
waitForContainer opa-weblogic-full
echo All containers running

echo Installing OPA
if ! ( docker cp opa opa-weblogic-full:/u01/oracle/opa \
    && docker exec --privileged --user root opa-weblogic-full chown 1000:0 -R /u01/oracle/opa \
    && docker exec --user root opa-weblogic-full chmod +x -R /u01/oracle/opa/bin/install.sh \
    && docker exec opa-weblogic-full /u01/oracle/opa/bin/install.sh install -non-secure-cookie -no-ssl -name=dev -dbconn=opa-mysql-full:3306 -dbuser=root -dbpass=Passw0rd -hubpass=Passw0rd -key=12345678 -wladmin=AdminServer -wladminurl=t3://localhost:7001 -target=AdminServer -wldomain=/u01/oracle/user_projects/domains/base_domain -wlstdir=/u01/oracle/wlserver/common/bin ); then
    exit 1
fi

echo Your hub is now ready at http://localhost:7001/dev/opa-hub
echo WARNING: Take note of the generated admin password and encryption key in the log above.

# docker cp opa-weblogic-full:/u01/oracle/opa/bin/install.log ./

# docker exec -i -t opa-weblogic-full /bin/bash
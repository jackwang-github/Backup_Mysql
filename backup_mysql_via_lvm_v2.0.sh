#!/bin/bash
export PATH=/mysql/mysql5.7/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/openssh/bin:/root/bin

MYSQL_LOGIN_PATH="master"
SNAP_SIZE="10G"
VG_PATH="/dev/datavg"
MYSQL_LV="/dev/datavg/datalv"
SNAP_LV="mysql_snap"
BACKUP_DIR="/backup_mysql"
LOG_FILE="/root/bak.log"
EXPIRED_DAYS=1

MOUNT_POINT=/`hostname`_`date +"%Y%m%d%H%M%S"`
logger()
{ if [[ $# -ne 2 ]];then 
    echo "Parameter error"
    return 1
  elif [[ $1 == "ERROR" ]];then
    echo "`date +"%Y-%m-%d %H:%M:%S"`:ERROR-$2" >> ${LOG_FILE}
  elif [[ $1 == "INFO" ]];then
    echo "`date +"%Y-%m-%d %H:%M:%S"`:INFO-$2" >> ${LOG_FILE}
  else
    echo "Parameter error"
    return 1
 fi 
 return 0
}

snaper()
{ if [[ $# -ne 1 ]];then 
    echo "Parameter error"
    return 1 
  elif [[ $1 == "CREATE" ]];then
     lvremove ${VG_PATH}/${SNAP_LV} -y &>/dev/null
     lvcreate -L ${SNAP_SIZE} -s -p r -n ${SNAP_LV} ${MYSQL_LV} &>/dev/null
     if [[ $? -eq 0 ]];then
        logger INFO "take snap success"
     else
        logger ERROR "take snap failed"
        return 1
     fi
  elif [[ $1 == "REMOVE" ]];then
     umount ${MOUNT_POINT}
     lvremove ${VG_PATH}/${SNAP_LV} -y &>/dev/null
     if [[ $? -eq 0 ]];then
       rm -rf ${MOUNT_POINT}
       logger INFO  "remove snapshot success"
     else
       logger ERROR "remove snapshot failed"
       return 1
     fi
 fi 
 return 0
}

table_locker()
{ if [[ $# -ne 1 ]];then 
    echo "Parameter error"
    return 1 
  elif [[ $1 == "LOCK" ]];then
     mysql --login-path=${MYSQL_LOGIN_PATH} -e 'flush tables  with read lock;flush logs'
     if [[ $? -eq 0 ]];then
        logger INFO "table locked success"
     else
        logger ERROR "table lock failed"
        return 1
     fi
  elif [[ $1 == "UNLOCK" ]];then
     mysql --login-path=${MYSQL_LOGIN_PATH} -e 'unlock tables'
     if [[ $? -eq 0 ]];then
       logger INFO  "table unlocked success"
     else
       logger ERROR "table unlock failed"
       return 1
     fi
 fi
 return 0
}

archive()
{ mount ${VG_PATH}/${SNAP_LV} ${MOUNT_POINT} -o ro
  #filename=`hostname`_`date +"%Y%m%d%H%M%S"`.tar.gz
  tar -czf ${BACKUP_DIR}${MOUNT_POINT}.tar.gz ${MOUNT_POINT}
  if [[ $? -eq 0 ]]; then
    logger INFO  "achive backup file success,file path: ${BACKUP_DIR}${MOUNT_POINT}.tar.gz"
  else
    logger ERROR  "achive backup file failed"
    return 1
fi
return 0
}

clear_expired_files()
{ logger INFO "start clear expired backupfile,details as flow:"
  find ${BACKUP_DIR} -type f -mtime ${EXPIRED_DAYS} -name "*.tar.gz"|xargs -ti rm -f {} &>>${LOG_FILE}
  logger INFO "expired backupfile clear end"
}

#start
echo -e "===>`date +"%Y-%m-%d %H:%M:%S"` Start Backup<===" >> ${LOG_FILE}
mkdir -p ${MOUNT_POINT} ${BACKUP_DIR}
table_locker LOCK
if [[ $? -eq 0 ]] ;then
  snaper CREATE
  if [[ $? -eq 0 ]];then
    table_locker UNLOCK
    archive
    if [[ $? -eq 0 ]];then
      clear_expired_files
    fi
    snaper REMOVE
  else
   table_locker UNLOCK
  fi
fi
echo -e "===>`date +"%Y-%m-%d %H:%M:%S"` Backup End<===\n" >> ${LOG_FILE}

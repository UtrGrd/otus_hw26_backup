# OTUS ДЗ №26. Резервное копирование. #
-----------------------------------------------------------------------
## Домашнее задание ##

1. Настроить стенд Vagrant с двумя виртуальными машинами: _backup_server_ и _client_

2. Настроить удаленный бекап каталога `/etc` c сервера client при помощи borgbackup. Резервные копии должны соответствовать следующим критериям:

-   Директория для резервных копий `/var/backup`. Это должна быть отдельная точка монтирования. В данном случае для демонстрации размер не принципиален, достаточно будет и 2GB.
-   Репозиторий для резервных копий должен быть зашифрован ключом или паролем - на ваше усмотрение
-   Имя бекапа должно содержать информацию о времени снятия бекапа
-   Глубина бекапа должна быть год, хранить можно по последней копии на конец месяца, кроме последних трех. Последние три месяца должны содержать копии на каждый день. Т.е. должна быть правильно настроена политика удаления старых бэкапов

-   Резервная копия снимается каждые 5 минут. Такой частый запуск в целях демонстрации.
-   Написан скрипт для снятия резервных копий. Скрипт запускается из соответствующей Cron джобы, либо systemd timer-а - на ваше усмотрение.
-   Настроено логирование процесса бекапа. Для упрощения можно весь вывод перенаправлять в logger с соответствующим тегом. Если настроите не в syslog, то обязательна ротация логов

Запустите стенд на 30 минут. Убедитесь что резервные копии снимаются. Остановите бэкап, удалите (или переместите) директорию /etc и восстановите ее из бекапа.  
Для сдачи домашнего задания ожидаем настроенные стенд, логи процесса бэкапа и описание процесса восстановления.

-----------------------------------------------------------------------
## Результат ##

Для поднятия стенда использовать команду ```vagrant up```

Установка вручную происходит следующим образом:

Установим borgbackup на обе машины:  
```
yum install -y epel-release
yum install -y borgbackup
```

На сервере создаем пользователя borg:  
```
useradd -m borg
echo password | passwd borg --stdin
```
Разрешаем вход ssh по паролю:  
```
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd
```

Монтируем директорию /var/backup:  
```
mkfs.xfs -q /dev/sdb  
mkdir -p /var/backup
mount /dev/sdb /var/backup 
chown -R borg:borg /var/backup
```  

На клиенте настраиваем вход по ssh-ключам и копируем ключ на сервер:  
```
ssh-keygen -b 2048 -t rsa -q -N '' -f ~/.ssh/id_rsa
ssh-copy-id borg@192.168.11.101
```

Инициализируем с клиента репозиторий для бэкапов:  
```
borg init -e repokey borg@192.168.11.101:/var/backup/repo
```  

Создадим первый бэкап вручную для проверки:  
```
borg create ssh://borg@192.168.11.101:/var/backup/repo::"FirstBackup-{now:%Y-%m-%d_%H:%M:%S}" /etc
```  

Создадим скрипт для автоматического создания резервных копий  
```
[root@client ~]# cat /root/backup.sh

    #!/bin/bash
    export BORG_RSH="ssh -i /root/.ssh/id_rsa"
    export BORG_REPO=ssh://borg@192.168.11.101/var/backup/repo
    export BORG_PASSPHRASE='password'
    LOG="/var/log/borg_backup.log"
    [ -f "$LOG" ] || touch "$LOG"
    exec &> >(tee -i ""$LOG")
    exec 2>&1
    echo "Starting backup"
    borg create --verbose --list --stats ::'{now:%Y-%m-%d_%H:%M:%S}' /etc                            

    echo "Pruning repository"
    borg prune --list --keep-daily 90 --keep-monthly 12
```

Добавим ротацию лога /var/log/borg_backup.log:  

```
[root@client ~]# cat /etc/logrotate.d/borg_backup.conf  

    /var/log/borg_backup.log {
      rotate 5
      missingok
      notifempty
      compress
      size 1M
      daily
      create 0644 root root
      postrotate
        service rsyslog restart > /dev/null
      endscript
    }
```
Добавим задачу в cron:  
```
crontab -l | { cat; echo "*/5 * * * * /root/backup.sh"; } | crontab -
```  

Запустим мониторинг логфайла:  
```
[root@client ~]# tail -f /var/log/borg_backup.log
                       Original size      Compressed size    Deduplicated size
This archive:               28.43 MB             13.43 MB             31.60 kB
All archives:               56.87 MB             26.86 MB             11.83 MB

                       Unique chunks         Total chunks
Chunk index:                    1281                 3390
------------------------------------------------------------------------------
Pruning repository
Keeping archive: 2022-11-20_09:35:02                  Sun, 2022-11-20 09:35:03 [1f35d7648b3461de408a59f9f12358d12963585c9a23ce5f8f4d9b7e5aeff7cb]
Pruning archive: 2022-11-20_09:30:02                  Sun, 2022-11-20 09:30:02 [806029e4f8a2b277adc13f9c9847c54dddcd5492540254c28918edf932f97c67] (1/1)
tail: /var/log/borg_backup.log: file truncated
Creating archive at "ssh://borg@192.168.11.101/var/backup/repo::2022-11-20_09:40:01"
------------------------------------------------------------------------------
Archive name: 2022-11-20_09:40:01
Archive fingerprint: 4cefaef11b0ea6529b8633162bfc838f6faea1cf66e6cba1c96e00bee6696299
Time (start): Sun, 2022-11-20 09:40:02
Time (end):   Sun, 2022-11-20 09:40:02
Duration: 0.42 seconds
Number of files: 1699
Utilization of max. archive size: 0%
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:               28.43 MB             13.43 MB             46.21 kB
All archives:               56.87 MB             26.86 MB             11.84 MB

                       Unique chunks         Total chunks
Chunk index:                    1282                 3390
------------------------------------------------------------------------------
Pruning repository
Keeping archive: 2022-11-20_09:40:01                  Sun, 2022-11-20 09:40:02 [4cefaef11b0ea6529b8633162bfc838f6faea1cf66e6cba1c96e00bee6696299]
Pruning archive: 2022-11-20_09:35:02                  Sun, 2022-11-20 09:35:03 [1f35d7648b3461de408a59f9f12358d12963585c9a23ce5f8f4d9b7e5aeff7cb] (1/1)
tail: /var/log/borg_backup.log: file truncated
Creating archive at "ssh://borg@192.168.11.101/var/backup/repo::2022-11-20_09:45:01"
------------------------------------------------------------------------------
Archive name: 2022-11-20_09:45:01
Archive fingerprint: 00bf962bce2c13bdba44b8fc6a37ce6f2064a7d7226617345a9ebbb870178b24
Time (start): Sun, 2022-11-20 09:45:02
Time (end):   Sun, 2022-11-20 09:45:03
Duration: 0.46 seconds
Number of files: 1699
Utilization of max. archive size: 0%
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:               28.43 MB             13.43 MB                581 B
All archives:               56.87 MB             26.86 MB             11.80 MB

                       Unique chunks         Total chunks
Chunk index:                    1280                 3390
------------------------------------------------------------------------------
Pruning repository
Keeping archive: 2022-11-20_09:45:01                  Sun, 2022-11-20 09:45:02 [00bf962bce2c13bdba44b8fc6a37ce6f2064a7d7226617345a9ebbb870178b24]
Pruning archive: 2022-11-20_09:40:01                  Sun, 2022-11-20 09:40:02 [4cefaef11b0ea6529b8633162bfc838f6faea1cf66e6cba1c96e00bee6696299] (1/1)
tail: /var/log/borg_backup.log: file truncated
Creating archive at "ssh://borg@192.168.11.101/var/backup/repo::2022-11-20_09:50:02"
------------------------------------------------------------------------------
Archive name: 2022-11-20_09:50:02
Archive fingerprint: 2e82dbd81caf65edb658d2403bf7e58df09b1cb8f7f012561ec6f19c93eec0ad
Time (start): Sun, 2022-11-20 09:50:02
Time (end):   Sun, 2022-11-20 09:50:03
Duration: 0.42 seconds
Number of files: 1699
Utilization of max. archive size: 0%
------------------------------------------------------------------------------
                       Original size      Compressed size    Deduplicated size
This archive:               28.43 MB             13.43 MB                580 B
All archives:               56.87 MB             26.86 MB             11.80 MB

                       Unique chunks         Total chunks
Chunk index:                    1280                 3390
------------------------------------------------------------------------------
Pruning repository
Keeping archive: 2022-11-20_09:50:02                  Sun, 2022-11-20 09:50:02 [2e82dbd81caf65edb658d2403bf7e58df09b1cb8f7f012561ec6f19c93eec0ad]
Pruning archive: 2022-11-20_09:45:01                  Sun, 2022-11-20 09:45:02 [00bf962bce2c13bdba44b8fc6a37ce6f2064a7d7226617345a9ebbb870178b24] (1/1)
```

Резервные копии успешно создаются.

Проверим восстановление из бэкапа:  
```
mkdir borg_restore  
cd borg_restore
```
Узнаем имя последнего архива:  
```
[root@client borg_restore]# borg list ssh://borg@192.168.11.101/var/backup/repo
2022-11-20_10:40:02                  Sun, 2022-11-20 10:40:03 [2c5f46d3fc418f0b2b31d12e22b89ac11cd608aaf80d5127205271d7614ca602]
```

Восстановим архив:  
```
borg extract ssh://borg@192.168.11.101/var/backup/repo::2022-11-20_10:40:02
```

#!/bin/bash
export BORG_RSH="ssh -i /root/.ssh/id_rsa"
export BORG_REPO=ssh://borg@192.168.11.101/var/backup/repo
export BORG_PASSPHRASE='password'
LOG="/var/log/borg_backup.log"
[ -f "$LOG" ] || touch "$LOG"
exec &> >(tee -i "$LOG")
exec 2>&1
echo "Starting backup"
borg create --verbose --stats ::'{now:%Y-%m-%d_%H:%M:%S}' /etc

echo "Pruning repository"
borg prune --list --keep-daily 90 --keep-monthly 12

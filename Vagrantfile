# frozen_string_literal: true
# -*- mode: ruby -*-
# vim: set ft=ruby :
home = ENV['HOME']
ENV['LC_ALL'] = 'en_US.UTF-8'

MACHINES = {
  server: {
    box_name: 'centos/7',
    ip_addr: '192.168.11.101',
  },
  client: {
    box_name: 'centos/7',
    ip_addr: '192.168.11.112',
  }
}.freeze

Vagrant.configure('2') do |config|
  MACHINES.each do |boxname, boxconfig|
    config.vm.define boxname do |box|
      box.vm.box = boxconfig[:box_name]
      box.vm.host_name = boxname.to_s
      box.vm.network 'private_network', ip: boxconfig[:ip_addr]

      box.vm.provider :virtualbox do |vb|
        vb.customize ['modifyvm', :id, '--memory', '1024']
      end

      box.vm.provision 'shell', inline: <<-SHELL
        yum install -y epel-release
        yum install -y borgbackup nano sshpass
      SHELL
    end
  end
  config.vm.define 'server' do |server|
  server.vm.provider :virtualbox do |vb|
    filename='./.vagrant/machines/server/virtualbox/sata24.vdi'
    unless File.exist?(filename)
      vb.customize ['createhd', '--filename', filename, '--variant', 'Fixed', '--size', 2048]
      needsController =  true
    end

    if needsController == true
      vb.customize ["storagectl", :id, "--name", "SATA", "--add", "sata" ]
      vb.customize ['storageattach', :id,  '--storagectl', 'SATA', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', filename]
    end
  end

    server.vm.provision 'shell', inline: <<-SERVERSHELL
        useradd -m borg
        echo password | passwd borg --stdin
        sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
        systemctl restart sshd
        mkdir -p /var/backup
        mkfs.xfs -q /dev/sdb
        mount /dev/sdb /var/backup
        chown -R borg:borg /var/backup
    SERVERSHELL
  end
  config.vm.define 'client' do |client|
    client.vm.provision 'shell', inline: <<-CLIENTSHELL
        ssh-keygen -b 2048 -t rsa -q -N '' -f ~/.ssh/id_rsa
        sshpass -ppassword ssh-copy-id -o StrictHostKeyChecking=no borg@192.168.11.101
        borg init -e none borg@192.168.11.101:/var/backup/repo
        borg create borg@192.168.11.101:/var/backup/repo::"FirstBackup-{now:%Y-%m-%d_%H:%M:%S}" /etc
        cp /vagrant/backup.sh /root/
        crontab -l | { cat; echo "*/5 * * * * /root/backup.sh"; } | crontab -
    CLIENTSHELL
  end
end

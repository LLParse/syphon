# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -*- mode: ruby -*-
# vi: set ft=ruby :

SLAVES=2
NET_PREFIX="192.168.3."
# APT_CACHE="192.168.1.101"

NODES={"master" => NET_PREFIX + "5"}
(0..SLAVES-1).each do |i| NODES["slave#{i}"] = NET_PREFIX + (6 + i).to_s end

if (defined? APT_CACHE) then NODES["apt-cache"] = APT_CACHE end

# create hosts
File.open('hosts', 'w') do |file|
  file.write("127.0.0.1\tlocalhost\n")
  file.write("\n# cluster nodes\n")
  NODES.each do |name, ip| file.write("#{ip}\t#{name}\n") end
end

# copy ssh key
SSH_KEY=File.expand_path("~/.ssh/id_rsa.pub")
if (File.exists?(SSH_KEY))
  FileUtils.cp(SSH_KEY, 'ssh_key.pub')
end

Vagrant.configure(2) do |config|
  config.vm.box = "trusty64"
  config.vm.box_url = "https://cloud-images.ubuntu.com/vagrant/trusty/current/trusty-server-cloudimg-amd64-vagrant-disk1.box"
  config.vm.synced_folder ".", "/vagrant"
  # Uncomment the following code if you're unable to access internet
  config.vm.provider "virtualbox" do |v|
    v.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    v.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end

  config.vm.define "master" do |master|
    master.vm.provider "virtualbox" do |v|
      v.memory = 1024
    end

    master.vm.hostname = "master"
    master.vm.network :private_network, ip: NODES["master"]
    # Mesos master port forwarding
    master.vm.network "forwarded_port", guest: 5050, host: 5050
    # Marathon port forwarding
    master.vm.network "forwarded_port", guest: 8080, host: 8080
    # Kafka scheduler port forwarding
    master.vm.network "forwarded_port", guest: 8888, host: 8888
    # Docker registry port forwarding
    master.vm.network "forwarded_port", guest: 5000, host: 5000
    # Zookeeper port forwarding
    master.vm.network "forwarded_port", guest: 2181, host: 2181

    master.vm.provision "shell", path: "init.sh", args: "master"
  end

  (0..SLAVES-1).each do |i|
    config.vm.define "slave#{i}" do |slave|
      slave.vm.provider "virtualbox" do |v|
        v.memory = 2048
        v.cpus = 2
      end

      slave.vm.hostname = "slave#{i}"
      slave.vm.network :private_network, ip: NODES[slave.vm.hostname]
      slave.vm.network "forwarded_port", guest: 5051, host: 5051, auto_correct: true
      slave.vm.provision "shell", path: "init.sh", args: "slave"
    end
  end
end
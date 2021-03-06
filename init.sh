#!/bin/bash

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

install_mesos() {
    mode=$1 # master | slave
    apt-get -qy install mesos

    echo "zk://master:2181/mesos" > /etc/mesos/zk

    ip=$(cat /etc/hosts | grep `hostname` | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
    echo "0.0.0.0" > "/etc/mesos-$mode/ip"
    echo 'docker,mesos' > /etc/mesos-slave/containerizers
    echo '5mins' > /etc/mesos-slave/executor_registration_timeout

    if [ $mode == "master" ]; then
        ln -s /lib/init/upstart-job /etc/init.d/mesos-master
        service mesos-master start
    else
        apt-get -qy remove zookeeper
        ln -s /lib/init/upstart-job /etc/init.d/mesos-slave
        service mesos-slave start
    fi
}

if [[ $1 != "master" && $1 != "slave" ]]; then
    echo "Usage: $0 master|slave"
    exit 1
fi
mode=$1

cd /vagrant

# name resolution
cp hosts /etc/hosts

# ssh key
key="ssh_key.pub"
if [ -f $key ]; then
    cat $key >> /home/vagrant/.ssh/authorized_keys
fi

# disable ipv6
echo -e "\nnet.ipv6.conf.all.disable_ipv6 = 1\n" >> /etc/sysctl.conf
sysctl -p

# use apt-cacher if present
apt_cache=$(cat hosts | grep apt-cache)
if [ -n "$apt_cache" ]; then
    echo "Using apt-cacher http://apt-cache:3142"
    echo "Acquire::http::Proxy \"http://apt-cache:3142\";" > /etc/apt/apt.conf.d/90-apt-proxy.conf
fi

# add mesosphere repo
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv E56151BF
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
CODENAME=$(lsb_release -cs)
echo "deb http://repos.mesosphere.io/${DISTRO} ${CODENAME} main" | tee /etc/apt/sources.list.d/mesosphere.list

apt-get -qy update
apt-get install -qy vim zip mc curl openjdk-7-jre scala git

apt-get install -y linux-image-generic-lts-trusty
wget -qO- https://get.docker.com/ | sh

service docker stop
docker -d --insecure-registry master:5000  1> ~/docker.out 2> ~/docker.err &

install_mesos $mode

if [[ "$mode" = "master" ]]; then
    export MESOS_NATIVE_JAVA_LIBRARY=/usr/local/lib/libmesos.so

    # Building and running Marathon
    wget http://downloads.mesosphere.com/marathon/v0.9.0/marathon-0.9.0.tgz -O /opt/marathon-0.9.0.tgz
    tar xzf /opt/marathon-0.9.0.tgz -C /opt
    cd /opt/marathon-0.9.0
    ./bin/start --master zk://master:2181/mesos --zk zk://master:2181/marathon --task_launch_timeout 300000 1> marathon.out 2> marathon.err &

    # Running Docker Registry
    docker run -d --net=host registry

    # Building and running Syphon Docker image
    cd /vagrant
    docker build -t elodina/syphon .

    # Publishing Syphon Docker image in Docker Registry
    apt-get install -y gawk
    latest=`docker images | grep elodina/syphon | grep latest | gawk 'match($0, /latest[ \t]+?([[:alnum:]]+)/, arr) {print arr[1]}'`
    docker tag ${latest} master:5000/elodina/syphon
    docker push master:5000/elodina/syphon

    docker run --net=host -i -t elodina/syphon ./marathon_deploy --master zk://master:2181/mesos --docker.registry.url master:5000 --marathon.url http://master:8080 --topics test_src --task.threads 1 --artifacts.host master --artifacts.port 8888 --ssl.cert cert.pem --ssl.key=key.pem --ssl.cacert=server.crt --consumer.config=consumer.properties --target.url=https://10.1.16.228:31002/ --api.key testkey --api.user johnsnow
fi
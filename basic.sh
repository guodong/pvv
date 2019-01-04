#!/bin/bash
# clean
docker rm -f h1 h2 s1 s2 s3

# hosts
docker run -ti -d --name h1 --net none --privileged snlab/dovs
docker run -ti -d --name h2 --net none --privileged snlab/dovs

# switches
docker run -ti -d --name s1 --net none --privileged snlab/dovs-quagga
docker run -ti -d --name s2 --net none --privileged snlab/dovs-quagga
docker run -ti -d --name s3 --net none --privileged snlab/dovs-quagga

# get network namespace
h1ns=$(docker inspect --format '{{.State.Pid}}' h1)
h2ns=$(docker inspect --format '{{.State.Pid}}' h2)
s1ns=$(docker inspect --format '{{.State.Pid}}' s1)
s2ns=$(docker inspect --format '{{.State.Pid}}' s2)
s3ns=$(docker inspect --format '{{.State.Pid}}' s3)

# and links
nsenter -t $h1ns -n ip link add eth0 type veth peer name eth0 netns $s1ns
nsenter -t $s1ns -n ip link add eth1 type veth peer name eth1 netns $s3ns
nsenter -t $s1ns -n ip link add eth2 type veth peer name eth0 netns $s2ns
nsenter -t $s2ns -n ip link add eth1 type veth peer name eth0 netns $s3ns
nsenter -t $s3ns -n ip link add eth2 type veth peer name eth0 netns $h2ns

# configure ip
nsenter -t $h1ns -n ifconfig eth0 10.0.0.1/24
nsenter -t $h2ns -n ifconfig eth0 10.0.1.1/24
nsenter -t $s1ns -n ifconfig eth0 10.0.0.254/24
nsenter -t $s1ns -n ifconfig eth1 10.0.2.1/24
nsenter -t $s1ns -n ifconfig eth2 10.0.3.1/24
nsenter -t $s2ns -n ifconfig eth0 10.0.3.2/24
nsenter -t $s2ns -n ifconfig eth1 10.0.4.1/24
nsenter -t $s3ns -n ifconfig eth0 10.0.4.2/24
nsenter -t $s3ns -n ifconfig eth1 10.0.2.6/24
nsenter -t $s3ns -n ifconfig eth2 10.0.1.254/24

# configure host gateway
nsenter -t $h1ns -n route add default gw 10.0.0.254
nsenter -t $h2ns -n route add default gw 10.0.1.254

# configure quagga
nsenter -t $s1ns -m bash -c "echo $'interface eth0\ninterface eth1\ninterface eth2\nrouter ospf\n network 10.0.0.0/24 area 0\nnetwork 10.0.2.0/24 area 0\n network 10.0.3.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s1ns -m bash -c "echo $'interface eth0\n ip address 10.0.0.254/24' >> /etc/quagga/zebra.conf"
nsenter -t $s1ns -m bash -c "echo $'interface eth1\n ip address 10.0.2.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s1ns -m bash -c "echo $'interface eth2\n ip address 10.0.3.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s2ns -m bash -c "echo $'interface eth0\ninterface eth1\nrouter ospf\n network 10.0.3.0/24 area 0\n network 10.0.4.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s2ns -m bash -c "echo $'interface eth0\n ip address 10.0.3.2/24' >> /etc/quagga/zebra.conf"
nsenter -t $s2ns -m bash -c "echo $'interface eth1\n ip address 10.0.4.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface eth0\ninterface eth1\ninterface eth2\nrouter ospf\n network 10.0.1.0/24 area 0\nnetwork 10.0.4.0/24 area 0\n network 10.0.2.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s3ns -m bash -c "echo $'interface eth0\n ip address 10.0.4.2/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface eth1\n ip address 10.0.2.6/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface eth2\n ip address 10.0.1.254/24' >> /etc/quagga/zebra.conf"

# start quagga
nsenter -t $s1ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf
nsenter -t $s1ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf
nsenter -t $s2ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf
nsenter -t $s2ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf
nsenter -t $s3ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf
nsenter -t $s3ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf


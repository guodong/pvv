#!/bin/bash
# clean
docker rm -f h1 h2 s1 s2 s3

# hosts
docker run -ti -d --name h1 --net none --privileged snlab/dovs
docker run -ti -d --name h2 --net none --privileged snlab/dovs

# switches
docker run -ti -d --name s1 --privileged snlab/dovs-quagga
docker run -ti -d --name s2 --privileged snlab/dovs-quagga
docker run -ti -d --name s3 --privileged snlab/dovs-quagga

# get network namespace
h1ns=$(docker inspect --format '{{.State.Pid}}' h1)
h2ns=$(docker inspect --format '{{.State.Pid}}' h2)
s1ns=$(docker inspect --format '{{.State.Pid}}' s1)
s2ns=$(docker inspect --format '{{.State.Pid}}' s2)
s3ns=$(docker inspect --format '{{.State.Pid}}' s3)

# and links
nsenter -t $h1ns -n ip link add e0 type veth peer name e0 netns $s1ns
nsenter -t $s1ns -n ip link add e1 type veth peer name e1 netns $s3ns
nsenter -t $s1ns -n ip link add e2 type veth peer name e0 netns $s2ns
nsenter -t $s2ns -n ip link add e1 type veth peer name e0 netns $s3ns
nsenter -t $s3ns -n ip link add e2 type veth peer name e0 netns $h2ns

# configure ovs
docker exec s1 service openvswitch-switch start
docker exec s1 ovs-vsctl add-br s
docker exec s1 ovs-vsctl add-port s e0
docker exec s1 ovs-vsctl add-port s e1
docker exec s1 ovs-vsctl add-port s e2
docker exec s1 ovs-vsctl add-port s i0 -- set interface i0 type=internal
docker exec s1 ovs-vsctl add-port s i1 -- set interface i1 type=internal
docker exec s1 ovs-vsctl add-port s i2 -- set interface i2 type=internal
docker exec s1 ifconfig i0 10.0.0.254/24
docker exec s1 ifconfig i1 10.0.2.1/24
docker exec s1 ifconfig i2 10.0.3.1/24

docker exec s2 service openvswitch-switch start
docker exec s2 ovs-vsctl add-br s
docker exec s2 ovs-vsctl add-port s e0
docker exec s2 ovs-vsctl add-port s e1
docker exec s2 ovs-vsctl add-port s i0 -- set interface i0 type=internal
docker exec s2 ovs-vsctl add-port s i1 -- set interface i1 type=internal
docker exec s2 ifconfig i0 10.0.3.2/24
docker exec s2 ifconfig i1 10.0.4.1/24
docker exec s2 ifconfig e0 0.0.0.0
docker exec s2 ifconfig e1 0.0.0.0

docker exec s3 service openvswitch-switch start
docker exec s3 ovs-vsctl add-br s
docker exec s3 ovs-vsctl add-port s e0
docker exec s3 ovs-vsctl add-port s e1
docker exec s3 ovs-vsctl add-port s e2
docker exec s3 ovs-vsctl add-port s i0 -- set interface i0 type=internal
docker exec s3 ovs-vsctl add-port s i1 -- set interface i1 type=internal
docker exec s3 ovs-vsctl add-port s i2 -- set interface i2 type=internal
docker exec s3 ifconfig i0 10.0.4.2/24
docker exec s3 ifconfig i1 10.0.2.2/24
docker exec s3 ifconfig i2 10.0.1.254/24
docker exec s3 ifconfig e0 0.0.0.0
docker exec s3 ifconfig e1 0.0.0.0
docker exec s3 ifconfig e2 0.0.0.0

# bring up ethx ports
docker exec s1 ifconfig e0 0.0.0.0
docker exec s1 ifconfig e1 0.0.0.0
docker exec s1 ifconfig e2 0.0.0.0
docker exec s2 ifconfig e0 0.0.0.0
docker exec s2 ifconfig e1 0.0.0.0
docker exec s3 ifconfig e0 0.0.0.0
docker exec s3 ifconfig e1 0.0.0.0
docker exec s3 ifconfig e2 0.0.0.0

# configure host network
nsenter -t $h1ns -n ifconfig e0 10.0.0.1/24
nsenter -t $h2ns -n ifconfig e0 10.0.1.1/24
nsenter -t $h1ns -n route add default gw 10.0.0.254
nsenter -t $h2ns -n route add default gw 10.0.1.254

# configure host iface mac
docker exec h1 ifconfig e0 hw ether 00:00:00:00:00:01
docker exec h2 ifconfig e0 hw ether 00:00:00:00:00:02

# configure quagga
nsenter -t $s1ns -m bash -c "echo $'interface i0\ninterface i1\ninterface i2\nrouter ospf\n network 10.0.0.0/24 area 0\nnetwork 10.0.2.0/24 area 0\n network 10.0.3.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s1ns -m bash -c "echo $'interface i0\n ip address 10.0.0.254/24' >> /etc/quagga/zebra.conf"
nsenter -t $s1ns -m bash -c "echo $'interface i1\n ip address 10.0.2.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s1ns -m bash -c "echo $'interface i2\n ip address 10.0.3.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s2ns -m bash -c "echo $'interface i0\ninterface i1\nrouter ospf\n network 10.0.3.0/24 area 0\n network 10.0.4.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s2ns -m bash -c "echo $'interface i0\n ip address 10.0.3.2/24' >> /etc/quagga/zebra.conf"
nsenter -t $s2ns -m bash -c "echo $'interface i1\n ip address 10.0.4.1/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface i0\ninterface i1\ninterface i2\nrouter ospf\n network 10.0.1.0/24 area 0\nnetwork 10.0.4.0/24 area 0\n network 10.0.2.0/24 area 0' >> /etc/quagga/ospfd.conf"
nsenter -t $s3ns -m bash -c "echo $'interface i0\n ip address 10.0.4.2/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface i1\n ip address 10.0.2.2/24' >> /etc/quagga/zebra.conf"
nsenter -t $s3ns -m bash -c "echo $'interface i2\n ip address 10.0.1.254/24' >> /etc/quagga/zebra.conf"

# start quagga
nsenter -t $s1ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf --fpm_format protobuf
nsenter -t $s1ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf
nsenter -t $s2ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf --fpm_format protobuf
nsenter -t $s2ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf
nsenter -t $s3ns -m -p -n -i zebra -d -f /etc/quagga/zebra.conf --fpm_format protobuf
nsenter -t $s3ns -m -p -n -i ospfd -d -f /etc/quagga/ospfd.conf

# set flow rules
docker exec s1 ovs-ofctl del-flows s
docker exec s1 ovs-ofctl add-flow s ip,in_port=1,ip_proto=89,actions=output:4
docker exec s1 ovs-ofctl add-flow s arp,in_port=1,arp_tpa=10.0.0.254,actions=output:4
docker exec s1 ovs-ofctl add-flow s in_port=4,actions=output:1
docker exec s1 ovs-ofctl add-flow s ip,in_port=2,ip_proto=89,actions=output:5
docker exec s1 ovs-ofctl add-flow s arp,in_port=2,arp_tpa=10.0.2.1,actions=output:5
docker exec s1 ovs-ofctl add-flow s in_port=5,actions=output:2
docker exec s1 ovs-ofctl add-flow s ip,in_port=3,ip_proto=89,actions=output:6
docker exec s1 ovs-ofctl add-flow s arp,in_port=3,arp_tpa=10.0.3.1,actions=output:6
docker exec s1 ovs-ofctl add-flow s in_port=6,actions=output:3

docker exec s2 ovs-ofctl del-flows s
docker exec s2 ovs-ofctl add-flow s ip,in_port=1,ip_proto=89,actions=output:3
docker exec s2 ovs-ofctl add-flow s arp,in_port=1,arp_tpa=10.0.3.2,actions=output:3
docker exec s2 ovs-ofctl add-flow s in_port=3,actions=output:1
docker exec s2 ovs-ofctl add-flow s ip,in_port=2,ip_proto=89,actions=output:4
docker exec s2 ovs-ofctl add-flow s arp,in_port=2,arp_tpa=10.0.4.1,actions=output:4
docker exec s2 ovs-ofctl add-flow s in_port=4,actions=output:2

docker exec s3 ovs-ofctl del-flows s
docker exec s3 ovs-ofctl add-flow s ip,in_port=1,ip_proto=89,actions=output:4
docker exec s3 ovs-ofctl add-flow s arp,in_port=1,arp_tpa=10.0.4.2,actions=output:4
docker exec s3 ovs-ofctl add-flow s in_port=4,actions=output:1
docker exec s3 ovs-ofctl add-flow s ip,in_port=2,ip_proto=89,actions=output:5
docker exec s3 ovs-ofctl add-flow s arp,in_port=2,arp_tpa=10.0.2.2,actions=output:5
docker exec s3 ovs-ofctl add-flow s in_port=5,actions=output:2
docker exec s3 ovs-ofctl add-flow s ip,in_port=3,ip_proto=89,actions=output:6
docker exec s3 ovs-ofctl add-flow s arp,in_port=3,arp_tpa=10.0.1.254,actions=output:6
docker exec s3 ovs-ofctl add-flow s in_port=6,actions=output:3

# copy fpmserver
docker cp fpmserver s1:/
docker cp fpmserver s2:/
docker cp fpmserver s3:/

# start fpmserver
docker exec s1 /fpmserver/main.py &
docker exec s2 /fpmserver/main.py &
docker exec s3 /fpmserver/main.py &



# configure openflow app
docker exec s1 ovs-ofctl add-group s group_id:1,type=ff,bucket=watch_port=2,actions=output:2,bucket=watch_port=3,actions=resubmit\(,100\) -O OpenFlow11
docker exec s1 ovs-ofctl add-flow s table=1,ip,nw_dst=10.0.1.0/24,actions=mod_dl_dst:00:00:00:00:00:02,group:1 -O OpenFlow11
docker exec s1 ovs-ofctl add-flow s table=1,ip,nw_dst=10.0.0.0/24,actions=mod_dl_dst:00:00:00:00:00:01,output:1
docker exec s2 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)
docker exec s3 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)



# configure openflow app
docker exec s1 ovs-ofctl add-group s group_id:1,type=ff,bucket=watch_port=3,actions=output:3,bucket=watch_port=2,actions=resubmit\(,100\) -O OpenFlow11
docker exec s1 ovs-ofctl add-flow s table=1,ip,nw_dst=10.0.1.0/24,actions=mod_dl_dst:00:00:00:00:00:02,group:1 -O OpenFlow11
docker exec s1 ovs-ofctl add-flow s table=1,ip,nw_dst=10.0.0.0/24,actions=mod_dl_dst:00:00:00:00:00:01,output:1
docker exec s2 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)
docker exec s3 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)



docker exec s1 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)
docker exec s2 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)
docker exec s3 ovs-ofctl add-flow s table=1,actions=resubmit\(,100\)








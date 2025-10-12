#!/bin/bash

ansible-playbook -i ./inventory/hosts.yml site.yml -e '{
  "super_user": "altlinux",
  "host_1": "89.208.208.109",
  "host_2": "89.208.228.250",
  "host_3": "89.208.228.216",
  "host_registry": "89.208.208.139",
  "cluster_vip": "89.208.208.200",
  "cluster_domain": "k8s-ha.local",
  "pod_network_cidr": "10.244.0.0/16",
  "service_cidr": "10.96.0.0/12",
  "registry_port": "5000"
}'
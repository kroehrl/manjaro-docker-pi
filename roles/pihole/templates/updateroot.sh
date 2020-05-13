#!/bin/bash

if wget -O root.hints https://www.internic.net/domain/named.root ; then
    rm {{ unbound_root_hints }}/root.hints
    mv root.hints {{ unbound_root_hints }}/
    cd {{ pihole_compose_dir }}
    docker-compose restart
fi
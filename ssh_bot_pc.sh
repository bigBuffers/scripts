#!/usr/bin/env bash
ssh -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no -L 5910:localhost:5901 -qA sqin@255.3.53.95 -o "proxycommand ssh -W %h:%p sqin@sw-ipp-drivefarm-oregon-gp-052.nvidia.com"

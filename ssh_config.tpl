# SSH Configuration for AWS Instances
# Usage: ssh -F ssh_config web OR ssh -F ssh_config monitor

Host web
    HostName ${web_ip}
    User ${user}
    IdentityFile ${key_file}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host monitor
    HostName ${monitor_ip}
    User ${user}
    IdentityFile ${key_file}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

# Direct connection examples:
# ssh -F ssh_config web
# ssh -F ssh_config monitor
#
# Or use direct commands:
# ssh -i ${key_file} ${user}@${web_ip}
# ssh -i ${key_file} ${user}@${monitor_ip}
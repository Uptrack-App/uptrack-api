#!/usr/bin/expect -f

# Setup SSH key authentication for Node C
set timeout 30

set node_ip "147.93.146.35"
set password "REMOVED_PASSWORD"
set pubkey "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com"

puts "🔑 Setting up SSH key for Node C ($node_ip)...\n"

# First, copy the public key
spawn ssh-copy-id -i ~/.ssh/id_ed25519.pub root@$node_ip

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
    }
    "password:" {
        send "$password\r"
    }
}

expect eof

puts "\n✅ SSH key setup complete! You can now login with:"
puts "   ssh root@$node_ip\n"

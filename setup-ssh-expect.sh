#!/usr/bin/expect -f

set timeout 30
set node_ip "147.93.146.35"
set password "REMOVED_PASSWORD"

puts "🔑 Setting up SSH key for Node C...\n"

# SSH into the server and setup the key
spawn ssh root@$node_ip

expect {
    "Are you sure you want to continue connecting" {
        send "yes\r"
        exp_continue
    }
    "password:" {
        send "$password\r"
    }
}

expect "root@*:~#"

send "mkdir -p ~/.ssh && chmod 700 ~/.ssh\r"
expect "root@*:~#"

send "echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXfwtx9sZyrufYfJ1NvYIJSn3WG36jhY/j4gzyHGoMs giahoangth@gmail.com' >> ~/.ssh/authorized_keys\r"
expect "root@*:~#"

send "chmod 600 ~/.ssh/authorized_keys\r"
expect "root@*:~#"

send "exit\r"
expect eof

puts "\n✅ SSH key installed successfully!\n"
puts "Testing connection without password...\n"

# Test the connection
spawn ssh root@$node_ip "echo 'SSH key working!'"
expect {
    "SSH key working!" {
        puts "✅ Success! You can now ssh without password.\n"
    }
    timeout {
        puts "❌ Timeout - something went wrong\n"
    }
}

expect eof

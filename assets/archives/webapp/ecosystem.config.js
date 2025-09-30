module.exports = {
  apps: [{
    name: 'ecommerce-webapp',
    script: './node_modules/.bin/next',
    args: 'start -p 3000',
    instances: 1,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/webapp/error.log',
    out_file: '/var/log/webapp/access.log',
    log_file: '/var/log/webapp/combined.log',
    time: true,
    max_restarts: 10,
    min_uptime: '10s'
  }]
}
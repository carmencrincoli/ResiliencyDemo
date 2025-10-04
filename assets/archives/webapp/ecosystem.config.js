module.exports = {
  apps: [{
    name: 'ecommerce-webapp',
    script: './node_modules/.bin/next',
    args: 'start -p 3000',
    instances: 1,
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    // Note: env_file doesn't work reliably in all PM2 versions
    // Environment variables are injected during deployment via this env object
    env: {
      NODE_ENV: 'production',
      PORT: '${PORT}',
      SERVER_IP: '${SERVER_IP}',
      SERVER_HOSTNAME: '${SERVER_HOSTNAME}',
      DB_PRIMARY_HOST: '${DB_PRIMARY_HOST}',
      DB_REPLICA_HOST: '${DB_REPLICA_HOST}',
      DB_PORT: '${DB_PORT}',
      DB_NAME: '${DB_NAME}',
      DB_USER: '${DB_USER}',
      DB_PASSWORD: '${DB_PASSWORD}',
      DB_SSL: '${DB_SSL}'
    },
    error_file: '/var/log/webapp/error.log',
    out_file: '/var/log/webapp/access.log',
    log_file: '/var/log/webapp/combined.log',
    time: true,
    max_restarts: 10,
    min_uptime: '10s'
  }]
}
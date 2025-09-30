import { hostname } from 'os';
import { ServerInfo } from '@/types';

// Get current webapp server information
export const getWebappServerInfo = (): ServerInfo => {
  return {
    hostname: process.env.SERVER_HOSTNAME || hostname(),
    ip: process.env.SERVER_IP || 'unknown',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development',
    nodeVersion: process.version,
    port: parseInt(process.env.PORT || '3000')
  };
};

// Format server info for display
export const formatServerInfo = (serverInfo: ServerInfo): string => {
  return `${serverInfo.hostname} (${serverInfo.ip}:${serverInfo.port})`;
};

// Format database server info for display
export const formatDatabaseServerInfo = (dbInfo: any): string => {
  const type = dbInfo.type === 'primary' ? 'Primary' : 'Replica';
  const responseTime = dbInfo.responseTime ? ` - ${dbInfo.responseTime}ms` : '';
  return `${type} DB: ${dbInfo.host}:${dbInfo.port}${responseTime}`;
};
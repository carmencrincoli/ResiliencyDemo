import { Pool, PoolConfig } from 'pg';
import { logger } from './logger';
import { DatabaseServerInfo } from '@/types';

interface DatabaseConfig {
  primary: PoolConfig;
  replica: PoolConfig;
}

// Track last used database server
let lastUsedServer: DatabaseServerInfo | null = null;

// Database configuration with failover support
const dbConfig: DatabaseConfig = {
  primary: {
    host: process.env.DB_PRIMARY_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'ecommerce',
    user: process.env.DB_USER || 'ecommerce_user',
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    max: 10, // Maximum number of clients in the pool
    idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
    connectionTimeoutMillis: 3000, // Return an error after 3 seconds if connection could not be established
    statement_timeout: 30000, // Terminate any statement that takes more than 30 seconds
    query_timeout: 30000, // Terminate any query that takes more than 30 seconds
  },
  replica: {
    host: process.env.DB_REPLICA_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'ecommerce',
    user: process.env.DB_USER || 'ecommerce_user',
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 3000,
    statement_timeout: 30000,
    query_timeout: 30000,
  },
};

// Create connection pools
let primaryPool: Pool;
let replicaPool: Pool;
let primaryHealthy = true;
let replicaHealthy = true;

// Health monitoring
let healthCheckInterval: NodeJS.Timeout | null = null;
const HEALTH_CHECK_INTERVAL = 30000; // Check every 30 seconds

// Initialize pools
function initializePools() {
  if (!primaryPool) {
    primaryPool = new Pool(dbConfig.primary);
    
    primaryPool.on('connect', () => {
      logger.info('New primary database client connected');
    });
    
    primaryPool.on('error', (err) => {
      logger.error('Unexpected error on primary database client', err);
      primaryHealthy = false;
    });
  }

  if (!replicaPool) {
    replicaPool = new Pool(dbConfig.replica);
    
    replicaPool.on('connect', () => {
      logger.info('New replica database client connected');
    });
    
    replicaPool.on('error', (err) => {
      logger.error('Unexpected error on replica database client', err);
      replicaHealthy = false;
    });
  }
  
  // Start background health monitoring
  startHealthMonitoring();
}

// Start background health monitoring
function startHealthMonitoring() {
  if (healthCheckInterval) return; // Already running
  
  logger.info('Starting background database health monitoring');
  healthCheckInterval = setInterval(async () => {
    try {
      await checkDatabaseHealth();
      // The checkDatabaseHealth() function already updates primaryHealthy and replicaHealthy flags
    } catch (error) {
      logger.error('Background health check failed:', error);
    }
  }, HEALTH_CHECK_INTERVAL);
}

// Stop background health monitoring
function stopHealthMonitoring() {
  if (healthCheckInterval) {
    clearInterval(healthCheckInterval);
    healthCheckInterval = null;
    logger.info('Stopped background database health monitoring');
  }
}

// Health check function
export const checkDatabaseHealth = async (): Promise<{ primary: boolean; replica: boolean }> => {
  const results = { primary: false, replica: false };
  
  // Check primary
  try {
    const client = await primaryPool.connect();
    await client.query('SELECT NOW()');
    client.release();
    results.primary = true;
    primaryHealthy = true;
    logger.debug('Primary database health check passed');
  } catch (error) {
    logger.error('Primary database health check failed:', error);
    primaryHealthy = false;
  }

  // Check replica
  try {
    const client = await replicaPool.connect();
    await client.query('SELECT NOW()');
    client.release();
    results.replica = true;
    replicaHealthy = true;
    logger.debug('Replica database health check passed');
  } catch (error) {
    logger.error('Replica database health check failed:', error);
    replicaHealthy = false;
  }

  return results;
};

// Get appropriate pool based on query type and health
export const getPool = (forWrite: boolean = false): { pool: Pool; serverInfo: DatabaseServerInfo } => {
  initializePools();
  
  if (forWrite) {
    // Write operations must go to primary
    if (primaryHealthy) {
      const serverInfo: DatabaseServerInfo = {
        host: dbConfig.primary.host as string,
        port: dbConfig.primary.port as number,
        type: 'primary',
        healthy: true
      };
      lastUsedServer = serverInfo;
      return { pool: primaryPool, serverInfo };
    }
    throw new Error('Primary database is not available for write operations');
  }
  
  // Read operations - prefer primary, fallback to replica
  if (primaryHealthy) {
    const serverInfo: DatabaseServerInfo = {
      host: dbConfig.primary.host as string,
      port: dbConfig.primary.port as number,
      type: 'primary',
      healthy: true
    };
    lastUsedServer = serverInfo;
    return { pool: primaryPool, serverInfo };
  } else if (replicaHealthy) {
    logger.info('Using replica database for read operation (primary unavailable)');
    const serverInfo: DatabaseServerInfo = {
      host: dbConfig.replica.host as string,
      port: dbConfig.replica.port as number,
      type: 'replica',
      healthy: true
    };
    lastUsedServer = serverInfo;
    return { pool: replicaPool, serverInfo };
  }
  
  throw new Error('No database connections available');
};

// Execute query with automatic failover
export const executeQuery = async (
  query: string, 
  values?: any[], 
  forWrite: boolean = false
): Promise<{ result: any; serverInfo: DatabaseServerInfo }> => {
  const maxRetries = forWrite ? 1 : 2; // Don't retry writes on replica
  let lastError: Error | null = null;
  let serverInfo: DatabaseServerInfo | null = null;

  for (let attempt = 0; attempt < maxRetries; attempt++) {
    try {
      const startTime = Date.now();
      const { pool, serverInfo: dbServerInfo } = getPool(forWrite || attempt === 0);
      serverInfo = dbServerInfo;
      
      const result = await pool.query(query, values);
      
      // Calculate response time
      serverInfo.responseTime = Date.now() - startTime;
      
      return { result, serverInfo };
    } catch (error) {
      lastError = error as Error;
      logger.error(`Database query failed (attempt ${attempt + 1}/${maxRetries}):`, error);
      
      // Mark the current primary as unhealthy and retry with replica for reads
      if (attempt === 0 && !forWrite) {
        primaryHealthy = false;
        logger.info('Marking primary as unhealthy, will try replica for read operation');
      }
    }
  }

  throw lastError || new Error('All database connection attempts failed');
};

// Get last used server information
export const getLastUsedServer = (): DatabaseServerInfo | null => {
  return lastUsedServer;
};

// Test database connections
export const testConnections = async (): Promise<boolean> => {
  try {
    initializePools();
    const health = await checkDatabaseHealth();
    logger.info('Database connection test results:', health);
    return health.primary || health.replica;
  } catch (error) {
    logger.error('Database connection test failed:', error);
    return false;
  }
};

// Graceful shutdown
export const closePools = async (): Promise<void> => {
  try {
    // Stop health monitoring
    stopHealthMonitoring();
    
    const promises = [];
    if (primaryPool) {
      promises.push(primaryPool.end());
    }
    if (replicaPool) {
      promises.push(replicaPool.end());
    }
    await Promise.all(promises);
    logger.info('Database pools closed');
  } catch (error) {
    logger.error('Error closing database pools:', error);
  }
};

// Export pools for direct access if needed
export { primaryPool, replicaPool };
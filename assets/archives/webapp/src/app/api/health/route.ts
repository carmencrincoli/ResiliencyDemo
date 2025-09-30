import { NextRequest, NextResponse } from 'next/server';
import { checkDatabaseHealth } from '@/lib/database';
import { HealthCheckResponse } from '@/types';
import { getWebappServerInfo } from '@/lib/server-utils';

const startTime = Date.now();

export async function GET(request: NextRequest) {
  try {
    // Check database health
    const databaseHealth = await checkDatabaseHealth();
    
    // Get webapp server info
    const webappServerInfo = getWebappServerInfo();
    
    const health: HealthCheckResponse = {
      status: (databaseHealth.primary || databaseHealth.replica) ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      database: databaseHealth,
      uptime: Math.floor((Date.now() - startTime) / 1000),
    };

    const statusCode = health.status === 'healthy' ? 200 : 503;
    
    // Add server info to response headers for monitoring tools
    const response = NextResponse.json(health, { status: statusCode });
    response.headers.set('X-Server-Hostname', webappServerInfo.hostname);
    response.headers.set('X-Server-IP', webappServerInfo.ip);
    response.headers.set('X-Server-Port', webappServerInfo.port.toString());
    
    return response;
  } catch (error) {
    console.error('Health check failed:', error);
    
    const health: HealthCheckResponse = {
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      version: '1.0.0',
      database: { primary: false, replica: false },
      uptime: Math.floor((Date.now() - startTime) / 1000),
    };
    
    return NextResponse.json(health, { status: 503 });
  }
}
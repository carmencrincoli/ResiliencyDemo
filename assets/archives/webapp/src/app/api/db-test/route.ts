import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { ApiResponse } from '@/types';
import { getWebappServerInfo } from '@/lib/server-utils';

interface DbTestResult {
  primary: {
    status: string;
    latency?: number;
    error?: string;
    host?: string;
  };
  replica: {
    status: string;
    latency?: number;
    error?: string;
    host?: string;
  };
  timestamp: string;
}

export async function GET(request: NextRequest) {
  const webappServerInfo = getWebappServerInfo();
  
  const testResult: DbTestResult = {
    primary: { status: 'unknown' },
    replica: { status: 'unknown' },
    timestamp: new Date().toISOString()
  };

  let lastUsedDbServer = null;

  // Test primary database
  try {
    const primaryStart = Date.now();
    const { result, serverInfo } = await executeQuery('SELECT 1', [], true); // Force primary
    testResult.primary.latency = Date.now() - primaryStart;
    testResult.primary.status = 'connected';
    testResult.primary.host = `${serverInfo.host}:${serverInfo.port}`;
    lastUsedDbServer = serverInfo;
  } catch (error) {
    testResult.primary.status = 'error';
    testResult.primary.error = error instanceof Error ? error.message : 'Unknown error';
  }

  // Test replica database (or fallback)
  try {
    const replicaStart = Date.now();
    const { result, serverInfo } = await executeQuery('SELECT 1', [], false); // Use replica
    testResult.replica.latency = Date.now() - replicaStart;
    testResult.replica.status = 'connected';
    testResult.replica.host = `${serverInfo.host}:${serverInfo.port}`;
    if (!lastUsedDbServer) {
      lastUsedDbServer = serverInfo;
    }
  } catch (error) {
    testResult.replica.status = 'error';
    testResult.replica.error = error instanceof Error ? error.message : 'Unknown error';
  }

  const overallStatus = testResult.primary.status === 'connected' || testResult.replica.status === 'connected';
  
  const response: ApiResponse<DbTestResult> = {
    success: overallStatus,
    data: testResult,
    message: overallStatus ? 'Database connectivity test completed' : 'Database connectivity failed',
    serverInfo: {
      webapp: webappServerInfo,
      database: lastUsedDbServer || {
        host: 'none',
        port: 0,
        type: 'primary',
        healthy: false
      }
    }
  };

  return NextResponse.json(response, { 
    status: overallStatus ? 200 : 500 
  });
}
import { NextRequest, NextResponse } from 'next/server';
import { ApiResponse } from '@/types';
import { getWebappServerInfo } from '@/lib/server-utils';

export async function GET(request: NextRequest) {
  try {
    // Get server information
    const serverInfo = getWebappServerInfo();

    const response: ApiResponse<typeof serverInfo> = {
      success: true,
      data: serverInfo,
      message: 'Server information retrieved successfully',
      serverInfo: {
        webapp: serverInfo,
        database: {
          host: 'n/a',
          port: 0,
          type: 'primary',
          healthy: true
        }
      }
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error('Failed to get server info:', error);
    
    const response: ApiResponse<null> = {
      success: false,
      data: null,
      message: 'Failed to retrieve server information',
      error: error instanceof Error ? error.message : 'Unknown error'
    };

    return NextResponse.json(response, { status: 500 });
  }
}
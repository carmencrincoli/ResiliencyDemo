'use client';

import { useState, useEffect } from 'react';
import { ServerInfo, DatabaseServerInfo } from '@/types';
import { formatServerInfo, formatDatabaseServerInfo } from '@/lib/server-utils';

interface ServerInfoDisplayProps {
  webappServer?: ServerInfo;
  databaseServer?: DatabaseServerInfo;
  className?: string;
}

export default function ServerInfoDisplay({ 
  webappServer, 
  databaseServer, 
  className = '' 
}: ServerInfoDisplayProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [lastRequestInfo, setLastRequestInfo] = useState<{
    webapp?: ServerInfo;
    database?: DatabaseServerInfo;
  }>({});

  // Update last request info when new server info is provided
  useEffect(() => {
    if (webappServer || databaseServer) {
      setLastRequestInfo({
        webapp: webappServer,
        database: databaseServer
      });
    }
  }, [webappServer, databaseServer]);

  const getStatusIndicator = (healthy?: boolean) => {
    if (healthy === undefined) return '🔄';
    return healthy ? '🟢' : '🔴';
  };

  const getServerStatusClass = (healthy?: boolean) => {
    if (healthy === undefined) return 'text-gray-500';
    return healthy ? 'text-green-600' : 'text-red-600';
  };

  return (
    <div className={`bg-gray-50 border rounded-lg ${className}`}>
      {/* Compact view */}
      <div 
        className="p-3 cursor-pointer hover:bg-gray-100 transition-colors"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <span className="text-sm font-medium text-gray-700">
              Server Info:
            </span>
            {lastRequestInfo.webapp && (
              <span className="text-xs text-blue-600">
                {getStatusIndicator(true)} {lastRequestInfo.webapp.hostname}
              </span>
            )}
            {lastRequestInfo.database && (
              <span className={`text-xs ${getServerStatusClass(lastRequestInfo.database.healthy)}`}>
                {getStatusIndicator(lastRequestInfo.database.healthy)} 
                {lastRequestInfo.database.type} DB
              </span>
            )}
          </div>
          <button className="text-gray-400 hover:text-gray-600">
            {isExpanded ? '▼' : '▶'}
          </button>
        </div>
      </div>

      {/* Expanded view */}
      {isExpanded && (
        <div className="px-3 pb-3 border-t bg-white">
          <div className="mt-3 space-y-3">
            {lastRequestInfo.webapp && (
              <div className="bg-blue-50 p-3 rounded">
                <h4 className="font-medium text-blue-800 mb-2">
                  🖥️ Webapp Server
                </h4>
                <div className="text-sm space-y-1 text-blue-700">
                  <div><strong>Hostname:</strong> {lastRequestInfo.webapp.hostname}</div>
                  <div><strong>IP:</strong> {lastRequestInfo.webapp.ip}</div>
                  <div><strong>Port:</strong> {lastRequestInfo.webapp.port}</div>
                  <div><strong>Environment:</strong> {lastRequestInfo.webapp.environment}</div>
                  <div><strong>Node Version:</strong> {lastRequestInfo.webapp.nodeVersion}</div>
                  <div><strong>Last Response:</strong> {new Date(lastRequestInfo.webapp.timestamp).toLocaleTimeString()}</div>
                </div>
              </div>
            )}

            {lastRequestInfo.database && (
              <div className={`p-3 rounded ${
                lastRequestInfo.database.healthy ? 'bg-green-50' : 'bg-red-50'
              }`}>
                <h4 className={`font-medium mb-2 ${
                  lastRequestInfo.database.healthy ? 'text-green-800' : 'text-red-800'
                }`}>
                  {getStatusIndicator(lastRequestInfo.database.healthy)} Database Server
                </h4>
                <div className={`text-sm space-y-1 ${
                  lastRequestInfo.database.healthy ? 'text-green-700' : 'text-red-700'
                }`}>
                  <div><strong>Type:</strong> {lastRequestInfo.database.type.charAt(0).toUpperCase() + lastRequestInfo.database.type.slice(1)}</div>
                  <div><strong>Host:</strong> {lastRequestInfo.database.host}</div>
                  <div><strong>Port:</strong> {lastRequestInfo.database.port}</div>
                  <div><strong>Status:</strong> {lastRequestInfo.database.healthy ? 'Healthy' : 'Unhealthy'}</div>
                  {lastRequestInfo.database.responseTime && (
                    <div><strong>Response Time:</strong> {lastRequestInfo.database.responseTime}ms</div>
                  )}
                </div>
              </div>
            )}

            {!lastRequestInfo.webapp && !lastRequestInfo.database && (
              <div className="text-center py-4 text-gray-500">
                <p>No server information available yet.</p>
                <p className="text-xs mt-1">Server info will appear after API requests.</p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
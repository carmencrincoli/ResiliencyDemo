// Product interface
export interface Product {
  id: number;
  uuid?: string;
  name: string;
  description: string;
  price: number;
  category: string;
  stock: number;
  image_url?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

// Cart item interface
export interface CartItem {
  product: Product;
  quantity: number;
}

// Server information interface
export interface ServerInfo {
  hostname: string;
  ip: string;
  timestamp: string;
  environment: string;
  nodeVersion: string;
  port: number;
}

// Database server information interface
export interface DatabaseServerInfo {
  host: string;
  port: number;
  type: 'primary' | 'replica';
  healthy: boolean;
  responseTime?: number;
}

// API Response interface with server tracking
export interface ApiResponse<T> {
  success: boolean;
  data: T;
  message?: string;
  error?: string;
  serverInfo?: {
    webapp: ServerInfo;
    database: DatabaseServerInfo;
  };
}

// Database health interface
export interface DatabaseHealth {
  primary: boolean;
  replica: boolean;
}

// Health check response interface
export interface HealthCheckResponse {
  status: 'healthy' | 'unhealthy';
  timestamp: string;
  version: string;
  database: DatabaseHealth;
  uptime: number;
}

// Environment variables interface
export interface AppConfig {
  dbPrimaryHost: string;
  dbReplicaHost: string;
  dbPort: number;
  dbName: string;
  dbUser: string;
  dbPassword: string;
  dbSsl: boolean;
  nodeEnv: string;
  port: number;
}
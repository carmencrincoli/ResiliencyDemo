-- E-commerce Database Schema - Optimized for PostgreSQL 16
-- Execute this script on the primary PostgreSQL server

-- Create database and user with enhanced security
CREATE DATABASE ecommerce WITH 
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

-- Create application user with strong password encryption
CREATE USER ecommerce_user WITH 
    ENCRYPTED PASSWORD 'SERVICE_PASSWORD_PLACEHOLDER'
    CONNECTION LIMIT 50
    VALID UNTIL 'infinity';

-- Connect to ecommerce database
\c ecommerce

-- Grant privileges with principle of least privilege
GRANT CONNECT ON DATABASE ecommerce TO ecommerce_user;
GRANT USAGE ON SCHEMA public TO ecommerce_user;

-- Enable necessary extensions for PostgreSQL 16
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";      -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";       -- Cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements"; -- Performance monitoring

-- Create products table with enhanced features and sequential ID for compatibility
CREATE TABLE products (
    id SERIAL PRIMARY KEY,                    -- Keep numeric ID for frontend compatibility
    uuid UUID DEFAULT uuid_generate_v4(),    -- Add UUID for future extensibility
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
    category VARCHAR(100) NOT NULL,
    stock INTEGER DEFAULT 0 CHECK (stock >= 0),
    image_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_price CHECK (price >= 0 AND price <= 999999.99)
);

-- Create users table with enhanced security (keep UUID for users)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL CHECK (email ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    is_admin BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    last_login TIMESTAMP WITH TIME ZONE,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create orders table with better constraints (keep UUID for orders)
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
    shipping_address JSONB NOT NULL,  -- Use JSONB for better performance
    billing_address JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create order_items table with proper constraints (reference products by numeric ID)
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER REFERENCES products(id) ON DELETE RESTRICT,  -- Reference numeric ID
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
    total_price DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create sessions table for Redis backup with improved design
CREATE TABLE sessions (
    id VARCHAR(255) PRIMARY KEY,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_data JSONB,
    ip_address INET,
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create audit log table for security tracking
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    record_id UUID,
    old_values JSONB,
    new_values JSONB,
    user_id UUID REFERENCES users(id),
    ip_address INET,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create optimized indexes for PostgreSQL 16
CREATE INDEX CONCURRENTLY idx_products_category_active ON products(category, is_active) WHERE is_active = TRUE;
CREATE INDEX CONCURRENTLY idx_products_price_active ON products(price, is_active) WHERE is_active = TRUE;
CREATE INDEX CONCURRENTLY idx_products_uuid ON products(uuid);  -- Index on UUID for future use
CREATE INDEX CONCURRENTLY idx_users_email_active ON users(email) WHERE is_active = TRUE;
CREATE INDEX CONCURRENTLY idx_users_last_login ON users(last_login) WHERE last_login IS NOT NULL;
CREATE INDEX CONCURRENTLY idx_orders_user_status ON orders(user_id, status);
CREATE INDEX CONCURRENTLY idx_orders_created_status ON orders(created_at, status);
CREATE INDEX CONCURRENTLY idx_order_items_order_id ON order_items(order_id);
CREATE INDEX CONCURRENTLY idx_order_items_product_id ON order_items(product_id);
CREATE INDEX CONCURRENTLY idx_sessions_user_id_active ON sessions(user_id, expires_at);
CREATE INDEX CONCURRENTLY idx_sessions_expires_at ON sessions(expires_at);
CREATE INDEX CONCURRENTLY idx_audit_log_table_created ON audit_log(table_name, created_at);
CREATE INDEX CONCURRENTLY idx_audit_log_user_created ON audit_log(user_id, created_at);

-- Insert sample products with UUIDs
INSERT INTO products (name, description, price, category, stock, is_active) VALUES
('Azure Local Server', 'High-performance edge computing solution for hybrid cloud deployments', 2999.99, 'Hardware', 10, TRUE),
('Cloud Storage Bundle', '10TB hybrid cloud storage solution with automatic tiering', 599.99, 'Storage', 25, TRUE),
('Network Switch Pro', '48-port managed switch optimized for edge deployments', 899.99, 'Networking', 15, TRUE),
('Backup Solution Kit', 'Complete data protection and backup solution for Azure Local', 399.99, 'Software', 30, TRUE),
('Security Bundle', 'Enterprise-grade security package for edge computing', 799.99, 'Security', 20, TRUE),
('Monitoring Dashboard', 'Real-time monitoring and analytics dashboard', 299.99, 'Software', 50, TRUE),
('Edge AI Accelerator', 'Hardware acceleration for AI workloads at the edge', 1299.99, 'Hardware', 8, TRUE),
('Disaster Recovery Service', 'Automated disaster recovery and business continuity', 499.99, 'Software', 40, TRUE),
('Container Orchestration Platform', 'Kubernetes-based container management solution', 699.99, 'Software', 35, TRUE),
('IoT Gateway Device', 'Secure gateway for IoT device connectivity', 899.99, 'Hardware', 12, TRUE);

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers to automatically update updated_at
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Grant specific permissions to application user (principle of least privilege)
GRANT SELECT, INSERT, UPDATE, DELETE ON products, users, orders, order_items, sessions TO ecommerce_user;
GRANT INSERT ON audit_log TO ecommerce_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ecommerce_user;

-- Create Row Level Security policies for enhanced security
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- RLS policy: Users can only see active products
CREATE POLICY products_visible_policy ON products
    FOR SELECT
    USING (is_active = TRUE);

-- RLS policy: Users can only access their own data
CREATE POLICY users_own_data_policy ON users
    FOR ALL
    USING (id = current_setting('app.current_user_id')::UUID);

-- RLS policy: Users can only see their own orders
CREATE POLICY orders_own_data_policy ON orders
    FOR ALL
    USING (user_id = current_setting('app.current_user_id')::UUID);

-- Create replication user for standby server with minimal privileges
CREATE USER replicator WITH 
    REPLICATION 
    ENCRYPTED PASSWORD 'SERVICE_PASSWORD_PLACEHOLDER'
    CONNECTION LIMIT 5;

-- Display success message
SELECT 'Database schema created successfully!' as message;
import { NextRequest, NextResponse } from 'next/server';
import { executeQuery } from '@/lib/database';
import { Product, ApiResponse } from '@/types';
import { getWebappServerInfo } from '@/lib/server-utils';

export async function GET(request: NextRequest) {
  try {
    // Get query parameters
    const { searchParams } = new URL(request.url);
    const category = searchParams.get('category');
    const limit = parseInt(searchParams.get('limit') || '50');
    const offset = parseInt(searchParams.get('offset') || '0');

    // Build query
    let query = `
      SELECT id, uuid, name, description, price, category, stock, image_url, is_active, created_at, updated_at
      FROM products 
      WHERE is_active = true
    `;
    const queryParams: any[] = [];

    if (category) {
      query += ` AND category = $${queryParams.length + 1}`;
      queryParams.push(category);
    }

    query += ` ORDER BY name ASC LIMIT $${queryParams.length + 1} OFFSET $${queryParams.length + 2}`;
    queryParams.push(limit, offset);

    // Execute query (read operation, can use replica)
    const { result, serverInfo: dbServerInfo } = await executeQuery(query, queryParams, false);
    
    // Convert price strings to numbers for frontend compatibility
    const products = result.rows.map((row: any) => ({
      ...row,
      price: parseFloat(row.price) || 0
    }));
    
    // Get webapp server info
    const webappServerInfo = getWebappServerInfo();
    
    const response: ApiResponse<Product[]> = {
      success: true,
      data: products,
      message: `Retrieved ${products.length} products`,
      serverInfo: {
        webapp: webappServerInfo,
        database: dbServerInfo
      }
    };

    return NextResponse.json(response);
  } catch (error) {
    console.error('Failed to fetch products:', error);
    
    // Get webapp server info even on error
    const webappServerInfo = getWebappServerInfo();
    
    const response: ApiResponse<Product[]> = {
      success: false,
      data: [],
      error: 'Database is currently unavailable. Please try again later.',
      serverInfo: {
        webapp: webappServerInfo,
        database: {
          host: 'unavailable',
          port: 0,
          type: 'primary',
          healthy: false
        }
      }
    };

    return NextResponse.json(response, { status: 503 }); // Service unavailable
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { name, description, price, category, stock, image_url } = body;

    // Validate required fields
    if (!name || !description || !price || !category) {
      return NextResponse.json(
        { success: false, error: 'Missing required fields' },
        { status: 400 }
      );
    }

    if (price <= 0) {
      return NextResponse.json(
        { success: false, error: 'Price must be greater than 0' },
        { status: 400 }
      );
    }

    // Insert product (write operation, must use primary)
    const query = `
      INSERT INTO products (name, description, price, category, stock, image_url)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING id, uuid, name, description, price, category, stock, image_url, is_active, created_at, updated_at
    `;

    const values = [name, description, price, category, stock || 0, image_url];
    const { result, serverInfo: dbServerInfo } = await executeQuery(query, values, true);

    // Convert price string to number for frontend compatibility
    const product = {
      ...result.rows[0],
      price: parseFloat((result.rows[0] as any).price) || 0
    };

    // Get webapp server info
    const webappServerInfo = getWebappServerInfo();

    const response: ApiResponse<Product> = {
      success: true,
      data: product,
      message: 'Product created successfully',
      serverInfo: {
        webapp: webappServerInfo,
        database: dbServerInfo
      }
    };

    return NextResponse.json(response, { status: 201 });
  } catch (error) {
    console.error('Failed to create product:', error);
    
    // Get webapp server info even on error
    const webappServerInfo = getWebappServerInfo();
    
    const response: ApiResponse<null> = {
      success: false,
      data: null,
      error: 'Failed to create product',
      serverInfo: {
        webapp: webappServerInfo,
        database: {
          host: 'error',
          port: 0,
          type: 'primary',
          healthy: false
        }
      }
    };

    return NextResponse.json(response, { status: 500 });
  }
}
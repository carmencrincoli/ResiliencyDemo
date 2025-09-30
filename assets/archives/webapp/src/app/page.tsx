'use client';

import { useState, useEffect } from 'react';
import { Product, CartItem, ApiResponse } from '@/types';
import ProductGrid from '@/components/ProductGrid';
import Cart from '@/components/Cart';
import ServerInfoDisplay from '@/components/ServerInfoDisplay';

export default function Home() {
  const [products, setProducts] = useState<Product[]>([]);
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showCart, setShowCart] = useState(false);
  const [serverInfo, setServerInfo] = useState<{
    webapp?: any;
    database?: any;
  }>({});

  useEffect(() => {
    loadProducts();
  }, []);

  const loadProducts = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const response = await fetch('/api/products');
      const data: ApiResponse<Product[]> = await response.json();
      
      // Capture server information if available
      if (data.serverInfo) {
        setServerInfo({
          webapp: data.serverInfo.webapp,
          database: data.serverInfo.database
        });
      }
      
      if (data.success || Array.isArray(data.data)) {
        setProducts(data.data);
      } else {
        throw new Error(data.error || 'Failed to load products');
      }
    } catch (err) {
      console.error('Failed to load products:', err);
      setError('Failed to load products. Please check if the application is running correctly.');
    } finally {
      setLoading(false);
    }
  };

  const addToCart = (product: Product, quantity: number = 1) => {
    setCartItems(prevItems => {
      const existingItem = prevItems.find(item => item.product.id === product.id);
      if (existingItem) {
        return prevItems.map(item =>
          item.product.id === product.id
            ? { ...item, quantity: item.quantity + quantity }
            : item
        );
      }
      return [...prevItems, { product, quantity }];
    });
  };

  const updateCartQuantity = (productId: number, quantity: number) => {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    setCartItems(prevItems =>
      prevItems.map(item =>
        item.product.id === productId
          ? { ...item, quantity }
          : item
      )
    );
  };

  const removeFromCart = (productId: number) => {
    setCartItems(prevItems => prevItems.filter(item => item.product.id !== productId));
  };

  const getTotalItems = () => {
    return cartItems.reduce((total, item) => total + item.quantity, 0);
  };

  const getTotalPrice = () => {
    return cartItems.reduce((total, item) => total + (item.product.price * item.quantity), 0);
  };

  if (loading) {
    return (
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-center items-center min-h-64">
          <div className="loading-spinner"></div>
          <span className="ml-4 text-lg">Loading products...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8">
      {/* Server Info Display */}
      <ServerInfoDisplay 
        webappServer={serverInfo.webapp}
        databaseServer={serverInfo.database}
        className="mb-6"
      />

      <div className="flex justify-between items-center mb-8">
        <div>
          <h2 className="text-3xl font-bold text-gray-800">Products</h2>
          <p className="text-gray-600 mt-2">Browse our selection of Azure products and services</p>
        </div>
        <div className="flex space-x-4">
          <button
            onClick={loadProducts}
            className="btn-secondary"
            disabled={loading}
          >
            {loading ? 'Refreshing...' : '🔄 Refresh Data'}
          </button>
          <button
            onClick={() => setShowCart(!showCart)}
            className="btn-primary relative"
          >
            {showCart ? 'Hide Cart' : 'View Cart'}
            {getTotalItems() > 0 && (
              <span className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full w-6 h-6 flex items-center justify-center text-xs">
                {getTotalItems()}
              </span>
            )}
          </button>
        </div>
      </div>

      {error && (
        <div className="error-banner">
          <p>{error}</p>
          <button onClick={loadProducts} className="btn-secondary mt-2">
            Retry
          </button>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className={showCart ? 'lg:col-span-2' : 'lg:col-span-3'}>
          <ProductGrid 
            products={products} 
            onAddToCart={addToCart} 
          />
        </div>
        
        {showCart && (
          <div className="lg:col-span-1">
            <div className="bg-white rounded-lg shadow-md p-6 sticky top-4">
              <Cart
                cartItems={cartItems}
                onUpdateQuantity={updateCartQuantity}
                onRemoveItem={removeFromCart}
                totalPrice={getTotalPrice()}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
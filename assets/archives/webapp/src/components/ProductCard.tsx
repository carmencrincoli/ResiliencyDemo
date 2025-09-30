interface ProductCardProps {
  product: {
    id: number;
    name: string;
    description: string;
    price: number;
    category: string;
    stock: number;
  };
  onAddToCart: (product: any, quantity: number) => void;
}

export default function ProductCard({ product, onAddToCart }: ProductCardProps) {
  const handleAddToCart = () => {
    onAddToCart(product, 1);
  };

  return (
    <div className="product-card">
      <div className="p-6">
        <div className="flex justify-between items-start mb-2">
          <h3 className="text-lg font-semibold text-gray-800 line-clamp-2">
            {product.name}
          </h3>
          <span className="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
            {product.category}
          </span>
        </div>
        
        <p className="text-gray-600 mb-4 line-clamp-3">
          {product.description}
        </p>
        
        <div className="flex justify-between items-center mb-4">
          <div>
            <span className="text-2xl font-bold text-green-600">
              ${product.price.toFixed(2)}
            </span>
          </div>
          <div className="text-right">
            <span className={`text-sm ${product.stock > 0 ? 'text-green-600' : 'text-red-600'}`}>
              {product.stock > 0 ? `${product.stock} in stock` : 'Out of stock'}
            </span>
          </div>
        </div>
        
        <button
          onClick={handleAddToCart}
          disabled={product.stock === 0}
          className={`w-full py-2 px-4 rounded font-semibold transition-colors duration-200 ${
            product.stock > 0
              ? 'bg-blue-600 hover:bg-blue-700 text-white'
              : 'bg-gray-300 text-gray-500 cursor-not-allowed'
          }`}
        >
          {product.stock > 0 ? 'Add to Cart' : 'Out of Stock'}
        </button>
      </div>
    </div>
  );
}
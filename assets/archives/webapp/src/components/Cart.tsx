import { CartItem } from '@/types';

interface CartProps {
  cartItems: CartItem[];
  onUpdateQuantity: (productId: number, quantity: number) => void;
  onRemoveItem: (productId: number) => void;
  totalPrice: number;
}

export default function Cart({ cartItems, onUpdateQuantity, onRemoveItem, totalPrice }: CartProps) {
  if (cartItems.length === 0) {
    return (
      <div className="text-center py-8">
        <div className="text-gray-500 text-lg mb-2">Your cart is empty</div>
        <p className="text-gray-400">Add some products to get started!</p>
      </div>
    );
  }

  return (
    <div>
      <h3 className="text-xl font-bold mb-4">Shopping Cart</h3>
      
      <div className="space-y-4 mb-6">
        {cartItems.map((item) => (
          <div key={item.product.id} className="border-b pb-4 last:border-b-0">
            <div className="flex justify-between items-start mb-2">
              <h4 className="font-semibold text-sm">{item.product.name}</h4>
              <button
                onClick={() => onRemoveItem(item.product.id)}
                className="text-red-500 hover:text-red-700 text-sm"
              >
                Remove
              </button>
            </div>
            
            <div className="flex justify-between items-center">
              <div className="flex items-center space-x-2">
                <button
                  onClick={() => onUpdateQuantity(item.product.id, item.quantity - 1)}
                  className="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center"
                >
                  -
                </button>
                <span className="w-8 text-center">{item.quantity}</span>
                <button
                  onClick={() => onUpdateQuantity(item.product.id, item.quantity + 1)}
                  disabled={item.quantity >= item.product.stock}
                  className="w-8 h-8 rounded-full bg-gray-200 hover:bg-gray-300 flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  +
                </button>
              </div>
              
              <div className="text-right">
                <div className="text-sm text-gray-600">
                  ${item.product.price.toFixed(2)} each
                </div>
                <div className="font-semibold">
                  ${(item.product.price * item.quantity).toFixed(2)}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>
      
      <div className="border-t pt-4">
        <div className="flex justify-between items-center mb-4">
          <span className="text-lg font-semibold">Total:</span>
          <span className="text-xl font-bold text-green-600">
            ${totalPrice.toFixed(2)}
          </span>
        </div>
        
        <button className="w-full btn-primary">
          Checkout
        </button>
      </div>
    </div>
  );
}
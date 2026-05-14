const CART_KEY = "care_mall_cart";

function getCart() {
  const raw = localStorage.getItem(CART_KEY);
  if (!raw) return [];
  try {
    return JSON.parse(raw);
  } catch (_) {
    return [];
  }
}

function saveCart(cart) {
  localStorage.setItem(CART_KEY, JSON.stringify(cart));
}

function addToCart(productId) {
  const cart = getCart();
  const found = cart.find((item) => item.productId === productId);
  if (found) {
    found.qty += 1;
  } else {
    cart.push({ productId, qty: 1 });
  }
  saveCart(cart);
}

function clearCart() {
  saveCart([]);
}

window.CARE_CART = {
  getCart,
  addToCart,
  clearCart
};

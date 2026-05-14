function query(name) {
  const params = new URLSearchParams(window.location.search);
  return params.get(name);
}

function renderProductList(containerId, category = null) {
  const target = document.getElementById(containerId);
  if (!target) return;
  const products = category
    ? window.CARE_PRODUCTS.filter((p) => p.category === category)
    : window.CARE_PRODUCTS;
  target.innerHTML = products
    .map(
      (p) => `
      <article class="card">
        <div class="badge">${p.category}</div>
        <h3>${p.name}</h3>
        <p>${p.description}</p>
        <p><strong>NT$ ${p.price}</strong></p>
        <p>
          <a href="./product.html?id=${p.id}">查看商品</a>
        </p>
        <button onclick="handleAddToCart('${p.id}')">加入購物車</button>
      </article>
    `
    )
    .join("");
}

function handleAddToCart(productId) {
  window.CARE_CART.addToCart(productId);
  alert("已加入購物車");
}

function renderProductDetail() {
  const id = query("id");
  const product = window.CARE_PRODUCTS.find((p) => p.id === id);
  const target = document.getElementById("product-detail");
  if (!target) return;
  if (!product) {
    target.innerHTML = "<p>找不到商品</p>";
    return;
  }
  target.innerHTML = `
    <article class="card">
      <div class="badge">${product.category}</div>
      <h2>${product.name}</h2>
      <p>${product.description}</p>
      <p><strong>NT$ ${product.price}</strong></p>
      <button onclick="handleAddToCart('${product.id}')">加入購物車</button>
    </article>
  `;
}

function renderCart() {
  const target = document.getElementById("cart-items");
  if (!target) return;
  const cart = window.CARE_CART.getCart();
  if (!cart.length) {
    target.innerHTML = "<p>購物車目前是空的。</p>";
    return;
  }
  const merged = cart.map((item) => {
    const product = window.CARE_PRODUCTS.find((p) => p.id === item.productId);
    return { ...item, product };
  });
  const total = merged.reduce((sum, item) => {
    return sum + item.qty * (item.product?.price || 0);
  }, 0);
  target.innerHTML = `
    ${merged
      .map(
        (item) => `
      <div class="card">
        <h3>${item.product?.name || "未知商品"}</h3>
        <p>數量：${item.qty}</p>
        <p>小計：NT$ ${(item.product?.price || 0) * item.qty}</p>
      </div>
    `
      )
      .join("")}
    <h3>總計：NT$ ${total}</h3>
  `;
}

function checkout() {
  alert("模擬結帳完成，感謝您的購買。");
  window.CARE_CART.clearCart();
  window.location.href = "./checkout.html";
}

window.CARE_APP = {
  renderProductList,
  renderProductDetail,
  renderCart,
  checkout
};

// Names/IDs mirror ShopService; this is not a price, stock or payment authority.
const ITEMS = [
  ["cookie", "小餅乾", ["餅乾", "狗狗餅乾", "點心"]],
  ["rice_ball", "飯糰", ["飯團"]],
  ["warm_milk", "溫牛奶", ["牛奶", "熱牛奶"]],
  ["juice", "果汁", ["飲料"]],
  ["salmon_bowl", "鮭魚餐", ["鮭魚", "魚肉", "鮭魚碗"]],
  ["chicken_soup", "暖雞湯", ["雞湯", "雞肉湯"]],
  ["yarn_ball", "毛線球", ["玩具球"]],
  ["bell", "小鈴鐺", ["鈴鐺"]],
  ["soft_blanket", "柔軟毯子", ["毯子", "小毯子"]],
  ["pet_bed", "午睡小床", ["床", "小床", "寵物床"]],
  ["grooming_brush", "梳毛刷", ["梳子", "毛刷", "寵物梳"]],
  ["bath_towel", "洗澡浴巾", ["毛巾", "浴巾", "洗澡毛巾"]],
  ["story_book", "睡前故事書", ["故事書", "繪本"]],
  ["music_box", "小音樂盒", ["音樂盒"]],
  ["revive_potion", "復活藥水", ["藥水"]],
];

function buildShopIntent(text) {
  const match = text.match(/^(?:請|麻煩)?(?:幫我|替我|我想|我要|我欲)?(?:用金幣)?(?:購買|買)\s*(.+?)[。！!]*$/);
  if (!match) return { handled: false, intent: null };
  const target = match[1].trim();
  // Retain the existing skin tool; merchandise, compound and ambiguous orders fail closed.
  if (/造型|皮膚|外觀/.test(target)) return { handled: false, intent: null };
  const quantityMatch = target.match(/^(?:(\d+|[一二兩三四五六七八九十])(?:個|份|包|瓶|本|顆|條|張|件)?)?\s*(.+)$/);
  const number = quantityMatch?.[1];
  const quantity = number ? (/^\d+$/.test(number) ? Number(number) : { 一: 1, 二: 2, 兩: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9, 十: 10 }[number]) : 1;
  const name = quantityMatch?.[2];
  const item = ITEMS.find(([, label, aliases]) => label === name || aliases.includes(name));
  if (!item || !Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
    return { handled: true, intent: null };
  }
  return {
    handled: true,
    intent: {
      toolName: "purchase_shop_item",
      arguments: { itemId: item[0], itemName: item[1], quantity },
      userFacingMessage: `要用 App 金幣買${quantity}份${item[1]}嗎？請先確認商城價格；這不是實體商品訂單。`,
    },
  };
}

function isValidShopArguments(args) {
  if (!args || !Number.isInteger(args.quantity) || args.quantity < 1 || args.quantity > 99) return false;
  return ITEMS.some(([id, name]) => args.itemId === id && args.itemName === name);
}

module.exports = { buildShopIntent, isValidShopArguments };

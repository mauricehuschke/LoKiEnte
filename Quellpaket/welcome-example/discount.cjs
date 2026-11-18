// Intentionally incorrect: returns the discount, not the remaining price.
module.exports = function discountedPrice(priceCents, discountPercent) {
  return Math.round(priceCents * discountPercent / 100);
};

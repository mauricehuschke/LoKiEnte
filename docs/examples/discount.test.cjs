const { test } = require('node:test');
const assert = require('node:assert/strict');
const discountedPrice = require('../discount.cjs');

for (const [price, percent, remaining] of [
    [10000, 20, 8000], [10000, 0, 10000], [10000, 100, 0], [999, 10, 899],
]) {
    test(`${price} cents at ${percent}% leaves ${remaining} cents`, () => {
        assert.equal(discountedPrice(price, percent), remaining);
    });
}
for (const [price, percent] of [[-1, 20], [10000, -1], [10000, 101]]) {
    test(`reject invalid price/discount ${price}, ${percent}`, () => {
        assert.throws(() => discountedPrice(price, percent), RangeError);
    });
}

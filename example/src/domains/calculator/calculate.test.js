const { add, subtract, multiply, divide } = require('./calculate');

describe('add', () => {
  test('adds two positive numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  test('adds negative and positive number', () => {
    expect(add(-2, 3)).toBe(1);
  });

  test('adds two negative numbers', () => {
    expect(add(-2, -3)).toBe(-5);
  });
});

describe('subtract', () => {
  test('subtracts two positive numbers', () => {
    expect(subtract(5, 3)).toBe(2);
  });

  test('subtracts a larger number from a smaller one', () => {
    expect(subtract(3, 5)).toBe(-2);
  });

  test('subtracts negative numbers', () => {
    expect(subtract(-5, -3)).toBe(-2);
  });
});

describe('multiply', () => {
  test('multiplies two positive numbers', () => {
    expect(multiply(2, 3)).toBe(6);
  });

  test('multiplies by zero', () => {
    expect(multiply(5, 0)).toBe(0);
  });

  test('multiplies negative and positive number', () => {
    expect(multiply(-2, 3)).toBe(-6);
  });
});

describe('divide', () => {
  test('divides two positive numbers', () => {
    expect(divide(6, 3)).toBe(2);
  });

  test('divides negative by positive', () => {
    expect(divide(-6, 3)).toBe(-2);
  });

  test('divides by one', () => {
    expect(divide(7, 1)).toBe(7);
  });

  test('divides zero by a number', () => {
    expect(divide(0, 5)).toBe(0);
  });

  test('divides by zero returns Infinity', () => {
    expect(divide(5, 0)).toBe(Infinity);
  });
});

const User = require('./user');

describe('User class', () => {
  const userData = {
    username: 'johndoe',
    name: 'John Doe',
    age: 30,
    email: 'john@example.com'
  };

  let user;

  beforeEach(() => {
    user = new User({ ...userData });
  });

  test('should create a user with correct properties', () => {
    expect(user.username).toBe(userData.username);
    expect(user.name).toBe(userData.name);
    expect(user.age).toBe(userData.age);
    expect(user.email).toBe(userData.email);
  });

  test('getProfile should return correct user profile', () => {
    const profile = user.getProfile();
    expect(profile).toEqual(userData);
  });

  test('setName should update the name', () => {
    user.setName('Jane Smith');
    expect(user.name).toBe('Jane Smith');
    expect(user.getProfile().name).toBe('Jane Smith');
  });

  test('setAge should update the age', () => {
    user.setAge(25);
    expect(user.age).toBe(25);
    expect(user.getProfile().age).toBe(25);
  });

  test('setEmail should update the email', () => {
    user.setEmail('jane@example.com');
    expect(user.email).toBe('jane@example.com');
    expect(user.getProfile().email).toBe('jane@example.com');
  });
});
test('should fail intentionally', () => {
  expect(user.username).toBe('notjohndoe');
});

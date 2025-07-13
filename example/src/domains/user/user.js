class User {
  constructor({ username, name, age, email }) {
    this.username = username;
    this.name = name;
    this.age = age;
    this.email = email;
  }

  getProfile() {
    return {
      username: this.username,
      name: this.name,
      age: this.age,
      email: this.email
    };
  }

  setName(newName) {
    this.name = newName;
  }

  setAge(newAge) {
    this.age = newAge;
  }

  setEmail(newEmail) {
    this.email = newEmail;
  }
}

module.exports = User;

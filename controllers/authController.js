// controllers/authController.js - Registration logic with Redis caching
const db = require('../config/db');
const redisClient = require('../config/redis');

const registerUser = async (req, res) => {
  const { username } = req.body;
  if (!username) {
    return res.status(400).json({ error: 'Username is required' });
  }
  try {
    // Check if the user is cached in Redis
    const cachedUser = await redisClient.get(`user:${username}`);
    if (cachedUser) {
      return res.json({ message: 'User already registered', username });
    }
    
    // Check if user exists in DB
    const result = await db.query('SELECT * FROM users WHERE username = $1', [username]);
    if (result.rows.length > 0) {
      await redisClient.set(`user:${username}`, JSON.stringify(result.rows[0]));
      return res.json({ message: 'User already registered', username });
    }
    
    // Insert new user in the database
    const insertResult = await db.query(
      'INSERT INTO users (username) VALUES ($1) RETURNING id',
      [username]
    );
    
    const newUser = { id: insertResult.rows[0].id, username };
    await redisClient.set(`user:${username}`, JSON.stringify(newUser));
    
    return res.json({
      message: 'User registered successfully',
      username,
      userId: newUser.id
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Registration failed' });
  }
};

module.exports = { registerUser };

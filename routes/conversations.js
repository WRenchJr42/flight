// routes/conversations.js
const express = require('express');
const router = express.Router();
const db = require('../config/db');

// GET /conversations?username=u1 returns conversation partners for u1
router.get('/', async (req, res) => {
  const { username } = req.query;
  if (!username) return res.status(400).json({ error: 'Username is required' });
  try {
    // Since conversation is bidirectional, check both columns.
    const result = await db.query(
      `SELECT CASE WHEN user1 = $1 THEN user2 ELSE user1 END AS conversation_partner
       FROM conversations
       WHERE user1 = $1 OR user2 = $1`,
       [username]
    );
    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({ error: 'Failed to fetch conversations' });
  }
});

module.exports = router;

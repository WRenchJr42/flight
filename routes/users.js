// routes/users.js
const express = require('express');
const router = express.Router();
const db = require('../config/db');

// GET /users/search?query=<searchString>
router.get('/search', async (req, res) => {
  const { query } = req.query;
  if (!query)
    return res.status(400).json({ error: 'Query parameter is required' });
  try {
    const result = await db.query(
      "SELECT username FROM users WHERE username ILIKE $1 LIMIT 10",
      [`%${query}%`]
    );
    res.json(result.rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Search failed' });
  }
});

module.exports = router;

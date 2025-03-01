const db = require('../config/db');
const { encryptMessage, decryptMessage } = require('../utils/encryption');

const sendMessage = async (req, res) => {
    const { sender, receiver, message, publicKey } = req.body;
    if (!sender || !receiver || !message || !publicKey)
        return res.status(400).json({ error: 'All fields are required' });

    const encryptedMessage = encryptMessage(message, publicKey);

    await db.query('INSERT INTO messages (sender, receiver, message) VALUES ($1, $2, $3)', 
        [sender, receiver, encryptedMessage]);

    res.json({ message: 'Message sent securely' });
};

const getMessages = async (req, res) => {
    const { userId } = req.query;
    if (!userId) return res.status(400).json({ error: 'User ID is required' });

    const result = await db.query('SELECT sender, receiver, message FROM messages WHERE receiver = $1', [userId]);
    res.json(result.rows);
};

module.exports = { sendMessage, getMessages };

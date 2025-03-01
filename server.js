const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const bodyParser = require('body-parser');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

// Import winston for logging
const winston = require('winston');

const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const conversationsRoutes = require('./routes/conversations');
const usersRoutes = require('./routes/users');
const db = require('./config/db');
const redisClient = require('./config/redis');
const { encryptMessage, decryptMessage } = require('./utils/encryption');

// Configure winston logger
const logFilePath = path.join(__dirname, 'server.log');
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
      winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
      winston.format.printf(info => `${info.timestamp} ${info.level.toUpperCase()}: ${info.message}`)
  ),
  transports: [
    new winston.transports.File({ filename: logFilePath })
  ]
});

// Also log to console for development
logger.add(new winston.transports.Console({
  format: winston.format.simple()
}));

const app = express();
const server = http.createServer(app);

// Global mapping for online users
const onlineUsers = {};

// Configure Socket.IO with CORS options
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
    allowedHeaders: ['Content-Type'],
    credentials: true
  }
});

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use('/auth', authRoutes);
app.use('/chat', chatRoutes);
app.use('/conversations', conversationsRoutes);
app.use('/users', usersRoutes);

// Add endpoint to return logs from server.log
app.get('/logs', (req, res) => {
  fs.readFile(logFilePath, 'utf8', (err, data) => {
    if (err) {
      logger.error(`Error reading log file: ${err}`);
      return res.status(500).send('Error reading logs');
    }
    res.type('text/plain').send(data);
  });
});

// Add endpoint to return public IP from file (/home/yash/node1/shell/ip_address.txt)
app.get('/ip', (req, res) => {
  const ipFilePath = '/home/yash/node1/shell/ip_address.txt';
  fs.readFile(ipFilePath, 'utf8', (err, data) => {
    if (err) {
      logger.error(`Error reading IP file: ${err}`);
      return res.status(500).send('Error reading IP file');
    }
    res.type('text/plain').send(data.trim());
  });
});

// Log HTTP upgrade requests (for debugging purposes)
server.on('upgrade', (req, socket, head) => {
  logger.info('HTTP upgrade request received');
});

// Socket.IO Connection Handling
io.on('connection', (socket) => {
  logger.info(`Socket.IO client connected: ${socket.id}`);

  socket.on('register', (data) => {
    if (data.username) {
      onlineUsers[data.username] = socket.id;
      socket.username = data.username;
      logger.info(`User registered on socket: ${data.username} (Socket ID: ${socket.id})`);
    }
  });

  socket.on('sendMessage', async (data) => {
    let processedMessage = data.message;
    if (data.publicKey) {
      try {
        processedMessage = encryptMessage(data.message, data.publicKey);
      } catch (err) {
        logger.error(`Encryption error: ${err}`);
        processedMessage = data.message;
      }
    }
    
    // Update conversation relationship (assuming you have a conversations table)
    try {
      const [userA, userB] = [data.sender, data.receiver].sort();
      await db.query(
        'INSERT INTO conversations (user1, user2) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [userA, userB]
      );
    } catch (err) {
      logger.error(`Error updating conversation: ${err}`);
    }

    const targetSocketId = onlineUsers[data.receiver];
    if (targetSocketId) {
      io.to(targetSocketId).emit('receiveMessage', {
        sender: data.sender,
        message: processedMessage
      });
      logger.info(`Private message from ${data.sender} sent to ${data.receiver}`);
    } else {
      logger.info(`User ${data.receiver} not online.`);
    }
  });

  socket.on('disconnect', () => {
    if (socket.username && onlineUsers[socket.username]) {
      logger.info(`User disconnected: ${socket.username}`);
      delete onlineUsers[socket.username];
    }
  });

  socket.on('error', (err) => {
    logger.error(`Socket.IO error: ${err}`);
  });
});

server.listen(3000, '0.0.0.0', () => {
  logger.info('Server running on port 3000 (IPv4). Socket.IO is available at /socket.io/');
});

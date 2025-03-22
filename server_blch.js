const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const bodyParser = require('body-parser');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const winston = require('winston');
const crypto = require('crypto');
const redis = require('redis');
const { Pool } = require('pg');

const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const conversationsRoutes = require('./routes/conversations');
const usersRoutes = require('./routes/users');
const redisClient = redis.createClient();

const db = new Pool({
  user: 'your_db_user',
  host: 'your_db_host',
  database: 'your_db_name',
  password: 'your_db_password',
  port: 5432,
});

db.connect()
  .then(() => console.log('Connected to PostgreSQL'))
  .catch(err => console.error('PostgreSQL connection error:', err));

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

logger.add(new winston.transports.Console({
  format: winston.format.simple()
}));

const app = express();
const server = http.createServer(app);
const onlineUsers = {};
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST'],
    allowedHeaders: ['Content-Type'],
    credentials: true
  }
});

app.use(cors());
app.use(bodyParser.json());
app.use('/auth', authRoutes);
app.use('/chat', chatRoutes);
app.use('/conversations', conversationsRoutes);
app.use('/users', usersRoutes);

function computeSHA256(data) {
  return crypto.createHash('sha256').update(data).digest('hex');
}

app.get('/logs', (req, res) => {
  fs.readFile(logFilePath, 'utf8', (err, data) => {
    if (err) {
      logger.error(`Error reading log file: ${err}`);
      return res.status(500).send('Error reading logs');
    }
    res.type('text/plain').send(data);
  });
});

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
    const messageHash = computeSHA256(processedMessage);
    const timestamp = Date.now();

    try {
      await db.query(
        'INSERT INTO messages (sender, receiver, message, timestamp) VALUES ($1, $2, $3, $4)',
        [data.sender, data.receiver, processedMessage, timestamp]
      );
      logger.info(`Message stored in PostgreSQL from ${data.sender} to ${data.receiver}`);
    } catch (err) {
      logger.error(`PostgreSQL error: ${err}`);
    }

    const blockchainEntry = JSON.stringify({
      sender: data.sender,
      receiver: data.receiver,
      message: processedMessage,
      hash: messageHash,
      timestamp: timestamp
    });
    
    redisClient.lpush('blockchain', blockchainEntry, (err) => {
      if (err) {
        logger.error(`Blockchain storage error: ${err}`);
      } else {
        logger.info(`Blockchain transaction recorded for message: ${messageHash}`);
      }
    });

    const targetSocketId = onlineUsers[data.receiver];
    if (targetSocketId) {
      io.to(targetSocketId).emit('receiveMessage', {
        sender: data.sender,
        message: processedMessage,
        hash: messageHash
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

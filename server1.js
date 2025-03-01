// server.js - Main entry point
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const bodyParser = require('body-parser');
const cors = require('cors');
const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chat');
const conversationsRoutes = require('./routes/conversations');
const db = require('./config/db');
const redisClient = require('./config/redis');
const { encryptMessage, decryptMessage } = require('./utils/encryption');
const usersRoutes = require('./routes/users');
const app = express();
const server = http.createServer(app);

// Global mapping for online users
const onlineUsers = {};
const fs = require('fs');
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

app.get('/ip', (req, res) => {
  const ipFilePath = '/home/yash/node1/shell/ip_address.txt';
  fs.readFile(ipFilePath, 'utf8', (err, data) => {
    if (err) {
      console.error("Error reading IP file:", err);
      return res.status(500).send("Error reading IP file");
    }
    res.send(data.trim());
  });
});

// (Optional) Log HTTP upgrade requests for debugging purposes
server.on('upgrade', (req, socket, head) => {
  console.log('HTTP upgrade request received');
});

// Socket.IO Connection Handling
io.on('connection', (socket) => {
  console.log(`Socket.IO client connected: ${socket.id}`);

  // When a client registers, store their username with the socket ID.
  socket.on('register', (data) => {
    if (data.username) {
      onlineUsers[data.username] = socket.id;
      socket.username = data.username;
      console.log(`User registered on socket: ${data.username} (Socket ID: ${socket.id})`);
    }
  });

  // Handle private messaging.
  socket.on('sendMessage', async (data) => {
    // Expected data: { sender, receiver, message, publicKey? }
    let processedMessage = data.message;
    if (data.publicKey) {
      try {
        processedMessage = require('./utils/encryption').encryptMessage(data.message, data.publicKey);
      
      } catch (err) {
        console.error('Encryption error:', err);
        processedMessage = data.message;
      }
    } else {
      processedMessage = data.message;
    }

    // Update conversation relationship if needed (not shown here)
    try {
      const [userA, userB] = [data.sender, data.receiver].sort();
      await db.query(
        'INSERT INTO conversations (user1, user2) VALUES ($1, $2) ON CONFLICT DO NOTHING',
        [userA, userB]
      );
    } catch (err) {
      console.error('Error updating conversation:', err);
    }

    // Look up the target user's socket ID
    const targetSocketId = onlineUsers[data.receiver];
    if (targetSocketId) {
      io.to(targetSocketId).emit('receiveMessage', {
        sender: data.sender,
        message: processedMessage
      });
      console.log(`Private message from ${data.sender} sent to ${data.receiver}`);
    } else {
      console.log(`User ${data.receiver} not online.`);
      // Optionally, store message for offline delivery.
    }
  });

  // On disconnect, remove the user from onlineUsers mapping.
  socket.on('disconnect', () => {
    if (socket.username && onlineUsers[socket.username]) {
      delete onlineUsers[socket.username];
      console.log(`User disconnected: ${socket.username}`);
    }
  });

  socket.on('error', (err) => {
    console.error(`Socket.IO error: ${err}`);
  });
});

server.listen(3000, '0.0.0.0', () => {
  console.log('Server running on port 3000 (IPv4). Socket.IO is available at /socket.io/');
});

/*
IMPORTANT:
When testing with raw WebSocket clients (like wscat or curl), always connect using Socket.IO's protocol endpoint.
For example:
    ws://YOUR_PUBLIC_IP:3000/socket.io/?EIO=4&transport=websocket
This ensures the proper Socket.IO handshake.
*/

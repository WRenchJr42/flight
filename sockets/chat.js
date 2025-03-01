const { encryptMessage } = require('../utils/encryption');

module.exports = (socket, io) => {
    socket.on('sendMessage', (data) => {
        const encryptedMessage = encryptMessage(data.message, data.publicKey);
        io.emit('receiveMessage', { sender: data.sender, message: encryptedMessage });
    });
};

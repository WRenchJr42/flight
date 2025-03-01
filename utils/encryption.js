const crypto = require('crypto');

const encryptMessage = (message, publicKey) => {
    return crypto.publicEncrypt(publicKey, Buffer.from(message)).toString('base64');
};

const decryptMessage = (encryptedMessage, privateKey) => {
    return crypto.privateDecrypt(privateKey, Buffer.from(encryptedMessage, 'base64')).toString();
};

module.exports = { encryptMessage, decryptMessage };

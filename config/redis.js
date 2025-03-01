const redis = require('redis');
const config = require('./config');

const client = redis.createClient({ url: config.redis.url });

client.on('error', (err) => console.error('Redis Client Error', err));

client.connect();

module.exports = client;

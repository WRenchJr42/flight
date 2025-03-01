import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Global variable for the server IP
String serverIp = "100.69.35.110";

// Function to update serverIp periodically
Future<void> updateServerIp() async {
  try {
    final url = Uri.parse('http://$serverIp:3000/ip');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      String newIp = response.body.trim();
      if (newIp.isNotEmpty && newIp != serverIp) {
        print("Updating serverIp from $serverIp to $newIp");
        serverIp = newIp;
      }
    } else {
      print("Failed to update serverIp, status: ${response.statusCode}");
    }
  } catch (e) {
    print("Error updating serverIp: $e");
  }
}

// A simple ChatMessage model with an optional reply.
class ChatMessage {
  final String sender;
  final String message;
  final String? reply;
  ChatMessage({required this.sender, required this.message, this.reply});
}

// Global local storage for conversation messages using a ValueNotifier.
ValueNotifier<Map<String, List<ChatMessage>>> localConversationsNotifier =
    ValueNotifier({});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MessagingApp());

  // Update the server IP every 5 minutes.
  Timer.periodic(Duration(minutes: 5), (_) {
    updateServerIp();
  });
}

class MessagingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messaging App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'Courier New',
              bodyColor: const Color.fromARGB(255, 3, 211, 10),
              displayColor: const Color.fromARGB(255, 3, 211, 10),
            ),
        appBarTheme: AppBarTheme(backgroundColor: Colors.black),
      ),
      home: FutureBuilder<String?>(
        future: _getStoredUsername(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          if (snapshot.hasData && snapshot.data!.isNotEmpty)
            return ConversationListScreen(username: snapshot.data!);
          return RegistrationScreen();
        },
      ),
    );
  }

  Future<String?> _getStoredUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }
}

class RegistrationScreen extends StatefulWidget {
  @override
  _RegistrationScreenState createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  String username = '';
  bool isLoading = false;
  String error = '';

  Future<void> register() async {
    setState(() {
      isLoading = true;
      error = '';
    });
    final url = 'http://$serverIp:3000/auth/register';
    try {
      final response = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username}));
      if (response.statusCode == 200) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', username);
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => ConversationListScreen(username: username)));
      } else {
        setState(() {
          error = 'Registration failed. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Register Username',
              style: TextStyle(fontFamily: 'Courier New'))),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (error.isNotEmpty)
              Text(error,
                  style: TextStyle(
                      color: const Color.fromARGB(255, 3, 211, 10),
                      fontFamily: 'Courier New')),
            TextField(
              style: TextStyle(
                  fontFamily: 'Courier New',
                  color: const Color.fromARGB(255, 3, 211, 10)),
              decoration: InputDecoration(labelText: 'Enter username'),
              onChanged: (value) {
                username = value;
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : register,
              child: isLoading
                  ? CircularProgressIndicator()
                  : Text('Register',
                      style: TextStyle(
                          fontFamily: 'Courier New',
                          color: const Color.fromARGB(255, 3, 211, 10))),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationListScreen extends StatefulWidget {
  final String username;
  ConversationListScreen({required this.username});
  @override
  _ConversationListScreenState createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  IO.Socket? socket;

  @override
  void initState() {
    super.initState();
    connectSocket();
  }

  void connectSocket() {
    socket = IO.io('ws://$serverIp:3000', IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());
    socket!.connect();

    socket!.onConnect((_) {
      print('Connected to Socket.IO server as ${widget.username}');
      socket!.emit('register', {'username': widget.username});
    });

    socket!.on('receiveMessage', (data) {
      String sender = data['sender'];
      String message = data['message'];
      // Since the message is pre-formatted, we don't need separate reply handling.
      ChatMessage chatMessage =
          ChatMessage(sender: sender, message: message);
      Map<String, List<ChatMessage>> updatedConversations =
          Map.from(localConversationsNotifier.value);
      updatedConversations.putIfAbsent(sender, () => []);
      // Check if a similar message already exists
      if (!updatedConversations[sender]!
          .any((m) => m.message == message && m.sender == sender)) {
        updatedConversations[sender]!.add(chatMessage);
        localConversationsNotifier.value = updatedConversations;
      }
    });

    socket!.onDisconnect((_) {
      print('Disconnected from Socket.IO server');
    });

    socket!.onError((error) {
      print('Socket.IO error: $error');
    });
  }

  @override
  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  void openConversation(String partner) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
            currentUser: widget.username, partner: partner, socket: socket),
      ),
    );
  }

  void openUserSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              UserSearchScreen(currentUser: widget.username, socket: socket)),
    );
  }

  void openLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LogScreen()),
    );
  }

  void openPublicIp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicIpScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Conversations (${widget.username})'),
        actions: [
          IconButton(icon: Icon(Icons.search), onPressed: openUserSearch),
          IconButton(icon: Icon(Icons.article), onPressed: openLogs),
          IconButton(icon: Icon(Icons.public), onPressed: openPublicIp),
        ],
      ),
      body: ValueListenableBuilder<Map<String, List<ChatMessage>>>(
        valueListenable: localConversationsNotifier,
        builder: (context, conversations, _) {
          List<String> conversationPartners = conversations.keys.toList();
          if (conversationPartners.isEmpty) {
            return Center(
                child: Text('No conversations yet.',
                    style: TextStyle(
                        fontFamily: 'Courier New',
                        color: const Color.fromARGB(255, 3, 211, 10))));
          }
          return ListView.builder(
            itemCount: conversationPartners.length,
            itemBuilder: (context, index) {
              String partner = conversationPartners[index];
              List<ChatMessage> msgs = conversations[partner] ?? [];
              String preview = msgs.isNotEmpty ? msgs.last.message : '';
              return ListTile(
                title: Text(partner,
                    style: TextStyle(
                        fontFamily: 'Courier New',
                        color: const Color.fromARGB(255, 2, 238, 10))),
                subtitle: Text(preview,
                    style: TextStyle(
                        fontFamily: 'Courier New',
                        color: const Color.fromARGB(255, 1, 88, 4))),
                onTap: () => openConversation(partner),
              );
            },
          );
        },
      ),
    );
  }
}

class UserSearchScreen extends StatefulWidget {
  final String currentUser;
  final IO.Socket? socket;
  UserSearchScreen({required this.currentUser, required this.socket});
  @override
  _UserSearchScreenState createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<String> searchResults = [];
  bool isLoading = false;

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) return;
    setState(() {
      isLoading = true;
    });
    final url = Uri.parse('http://$serverIp:3000/users/search?query=$query');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          searchResults = data.map((e) => e['username'] as String).toList();
        });
      } else {
        print('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      print("Error searching users: $e");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void openConversation(String partner) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
            currentUser: widget.currentUser,
            partner: partner,
            socket: widget.socket),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Search Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                  fontFamily: 'Courier New',
                  color: const Color.fromARGB(255, 3, 211, 10)),
              decoration: InputDecoration(
                labelText: 'Search by username',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () => searchUsers(_searchController.text),
                ),
              ),
            ),
          ),
          isLoading
              ? CircularProgressIndicator()
              : Expanded(
                  child: ListView.builder(
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final username = searchResults[index];
                      return ListTile(
                        title: Text(username,
                            style: TextStyle(
                                fontFamily: 'Courier New',
                                color: const Color.fromARGB(255, 3, 211, 10))),
                        onTap: () => openConversation(username),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}

class ConversationScreen extends StatefulWidget {
  final String currentUser;
  final String partner;
  final IO.Socket? socket;
  ConversationScreen(
      {required this.currentUser, required this.partner, required this.socket});
  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  ChatMessage? _messageToReply;

  @override
  void initState() {
    super.initState();
    // We no longer add an extra socket listener here;
    // UI updates via the global localConversationsNotifier.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void sendMessage() {
  if (_controller.text.isNotEmpty) {
    // Pre-format the message if it's a reply
    String finalMessage = _controller.text;
    if (_messageToReply != null) {
      finalMessage = "Re: ${_messageToReply!.message}\n${_controller.text}";
    }
    // Emit the pre-formatted message as a single string
    widget.socket!.emit('sendMessage', {
      'sender': widget.currentUser,
      'receiver': widget.partner,
      'message': finalMessage,
    });
    // Update the local conversation storage with the formatted message
    Map<String, List<ChatMessage>> updatedConversations =
        Map.from(localConversationsNotifier.value);
    updatedConversations.putIfAbsent(widget.partner, () => []);
    ChatMessage newMessage = ChatMessage(
      sender: widget.currentUser,
      message: finalMessage,
      reply: _messageToReply?.message,
    );
    updatedConversations[widget.partner]!.add(newMessage);
    localConversationsNotifier.value = updatedConversations;

    _controller.clear();
    setState(() {
      _messageToReply = null;
    });
  }
}


  void _showReplyOptions(ChatMessage message) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(Icons.reply),
                  title: Text('Reply'),
                  onTap: () {
                    setState(() {
                      _messageToReply = message;
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        });
  }

  Widget _buildMessageBubble(ChatMessage message) {
    bool isMe = message.sender == widget.currentUser;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          _showReplyOptions(message);
        },
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: EdgeInsets.all(12),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
              bottomLeft: isMe ? Radius.circular(12) : Radius.circular(0),
              bottomRight: isMe ? Radius.circular(0) : Radius.circular(12),
            ),
          ),
          child: Text(
            message.message,
            style: TextStyle(color: Colors.black),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat with ${widget.partner}')),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<Map<String, List<ChatMessage>>>(
              valueListenable: localConversationsNotifier,
              builder: (context, conversations, _) {
                List<ChatMessage> messages = conversations[widget.partner] ?? [];
                return ListView.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, index) =>
                      _buildMessageBubble(messages[index]),
                );
              },
            ),
          ),
          if (_messageToReply != null)
            Container(
              color: Colors.grey[800],
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Replying to: ${_messageToReply!.message}",
                      style: TextStyle(
                          fontStyle: FontStyle.italic, color: Colors.white70),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      setState(() {
                        _messageToReply = null;
                      });
                    },
                  )
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(
                        fontFamily: 'Courier New',
                        color: const Color.fromARGB(255, 3, 211, 10)),
                    decoration: InputDecoration(
                      labelText: 'Enter message',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white38),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send,
                      color: const Color.fromARGB(255, 3, 211, 10)),
                  onPressed: sendMessage,
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}

class LogScreen extends StatelessWidget {
  // This screen fetches the logs from your server endpoint /logs
  Future<String> fetchLogs() async {
    final url = Uri.parse('http://$serverIp:3000/logs');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return response.body;
    }
    return 'Failed to load logs (Status: ${response.statusCode})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Server Logs')),
      body: FutureBuilder<String>(
        future: fetchLogs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Text(snapshot.data ?? 'No logs available',
                style: TextStyle(
                    fontFamily: 'Courier New', color: Colors.greenAccent)),
          );
        },
      ),
    );
  }
}

class PublicIpScreen extends StatelessWidget {
  // This screen fetches the public IP from your server endpoint /ip
  Future<String> fetchPublicIp() async {
    final url = Uri.parse('http://$serverIp:3000/ip');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      return response.body.trim();
    }
    return 'Failed to load IP (Status: ${response.statusCode})';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Public IP Address')),
      body: FutureBuilder<String>(
        future: fetchPublicIp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(child: Text('Error: ${snapshot.error}'));
          return Center(
            child: Text('Public IP: ${snapshot.data}',
                style: TextStyle(
                    fontFamily: 'Courier New',
                    color: Colors.greenAccent,
                    fontSize: 20)),
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

final FirebaseFirestore db = FirebaseFirestore.instance;

Future<void> updateUserStatus(bool isOnline) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await db.collection('users').doc(user.uid).set({
    'isOnline': isOnline,
    'lastSeen': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lavender Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9575CD),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          return StatusSession(
            key: ValueKey(user.uid),
            user: user,
          );
        }

        return const LoginScreen();
      },
    );
  }
}

class StatusSession extends StatefulWidget {
  final User user;

  const StatusSession({super.key, required this.user});

  @override
  State<StatusSession> createState() => _StatusSessionState();
}

class _StatusSessionState extends State<StatusSession>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    updateUserStatus(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      updateUserStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      updateUserStatus(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    updateUserStatus(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const UsersScreen();
  }
}

// LOGIN AND SIGNUP

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool loading = false;

  Future<void> submit() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (!isLogin && name.isEmpty) {
      showMessage('Please enter your name.');
      return;
    }

    if (email.isEmpty || password.length < 6) {
      showMessage(
        'Enter your email and a password of at least 6 characters.',
      );
      return;
    }

    setState(() => loading = true);

    try {
      UserCredential result;

      if (isLogin) {
        result = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = result.user!;
      final ref = db.collection('users').doc(user.uid);

      if (isLogin) {
        final profile = await ref.get();
        final savedName = profile.data()?['name'];

        await ref.set({
          'uid': user.uid,
          'email': user.email ?? email,
          if (!profile.exists ||
              savedName == null ||
              savedName.toString().trim().isEmpty)
            'name': user.displayName ?? email.split('@')[0],
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'uid': user.uid,
          'email': user.email ?? email,
          'name': name,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Login failed.');
    } catch (e) {
      showMessage('Could not save profile: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chat_bubble_rounded,
                    size: 64,
                    color: Color(0xFF9575CD),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Lavender Chat 💜',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!isLogin) ...[
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Your Name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      if (!loading) submit();
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : submit,
                      child: loading
                          ? const CircularProgressIndicator()
                          : Text(isLogin ? 'Login' : 'Sign Up'),
                    ),
                  ),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => setState(() => isLogin = !isLogin),
                    child: Text(
                      isLogin
                          ? 'Create an account'
                          : 'Already have an account? Login',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// USERS LIST

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  String formatLastSeen(dynamic value) {
    if (value is! Timestamp) return 'Last seen recently';

    final difference = DateTime.now().difference(value.toDate());

    if (difference.inMinutes < 1) return 'Last seen just now';
    if (difference.inMinutes < 60) {
      return 'Last seen ${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) {
      return 'Last seen ${difference.inHours} hr ago';
    }

    return 'Last seen ${difference.inDays} day(s) ago';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F2FC),
      appBar: AppBar(
        title: const Text('Lavender Chat 💜'),
        backgroundColor: const Color(0xFFE1BEE7),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              try {
                await updateUserStatus(false);
              } catch (_) {}
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load users.'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs
              .where((doc) => doc.id != currentUser.uid)
              .toList();

          if (users.isEmpty) {
            return const Center(
              child: Text('No other users yet. Create a second account.'),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final doc = users[index];
              final user = doc.data();
              final email = (user['email'] ?? 'User').toString();
              final name = (user['name'] ?? '').toString().trim();
              final displayName =
                  name.isNotEmpty ? name : email.split('@')[0];
              final isOnline = user['isOnline'] == true;

              return ListTile(
                leading: Stack(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFD1C4E9),
                      child: Icon(
                        Icons.person,
                        color: Colors.deepPurple,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                title: Text(displayName),
                subtitle: Text(
                  isOnline
                      ? 'Online'
                      : formatLastSeen(user['lastSeen']),
                ),
                trailing: const Icon(Icons.chat_bubble_outline),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivateChatScreen(
                        otherUid: doc.id,
                        otherEmail: email,
                        otherName: displayName,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// PRIVATE CHAT WITH TYPING INDICATOR

class PrivateChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherEmail;
  final String otherName;

  const PrivateChatScreen({
    super.key,
    required this.otherUid,
    required this.otherEmail,
    required this.otherName,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final controller = TextEditingController();

  late final String myUid;
  late final List<String> members;
  late final DocumentReference<Map<String, dynamic>> chatRef;

  bool ready = false;
  String? setupError;

  bool isTyping = false;
  Timer? typingTimer;

  @override
  void initState() {
    super.initState();

    myUid = FirebaseAuth.instance.currentUser!.uid;
    members = [myUid, widget.otherUid]..sort();

    final chatId = members.join('_');
    chatRef = db.collection('chats').doc(chatId);

    prepareChat();
  }

  Future<void> prepareChat() async {
    try {
      await chatRef.set({
        'members': members,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => setupError = e.toString());
    }
  }

  // Update only this user's typing field.
  Future<void> updateTypingStatus(bool typing) async {
    if (!ready) return;

    try {
      await chatRef.update({
        'typing.$myUid': typing,
      });
    } catch (_) {
      // Chat remains usable if the typing update fails.
    }
  }

  void handleTyping(String value) {
    if (!ready) return;

    if (value.trim().isNotEmpty) {
      if (!isTyping) {
        isTyping = true;
        updateTypingStatus(true);
      }

      // Reset the timer each time the user types.
      typingTimer?.cancel();
      typingTimer = Timer(const Duration(seconds: 2), () {
        isTyping = false;
        updateTypingStatus(false);
      });
    } else {
      typingTimer?.cancel();
      isTyping = false;
      updateTypingStatus(false);
    }
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || !ready) return;

    typingTimer?.cancel();
    isTyping = false;
    await updateTypingStatus(false);

    controller.clear();

    try {
      await chatRef.collection('messages').add({
        'text': text,
        'senderId': myUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message could not be sent.')),
      );
    }
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    if (ready) {
      updateTypingStatus(false);
    }
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F2FC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherName),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: db.collection('users').doc(widget.otherUid).snapshots(),
              builder: (context, snapshot) {
                final user = snapshot.data?.data();
                final online = user?['isOnline'] == true;

                return Text(
                  online ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? Colors.green.shade800 : Colors.black54,
                  ),
                );
              },
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE1BEE7),
      ),
      body: setupError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Could not open secure chat:\n$setupError'),
              ),
            )
          : !ready
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>>(
                        stream: chatRef
                            .collection('messages')
                            .orderBy('createdAt')
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Could not load messages.'),
                            );
                          }

                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final docs = snapshot.data!.docs;

                          if (docs.isEmpty) {
                            return const Center(
                              child: Text('Say hello! 💜'),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final mine = data['senderId'] == myUid;

                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? const Color(0xFFD1C4E9)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    (data['text'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),

                    // Show "Typing..." when the other user is typing.
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: chatRef.snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();

                        final typing = snapshot.data!.data()?['typing'] ?? {};
                        final otherTyping = typing[widget.otherUid] == true;

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: otherTyping
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '${widget.otherName} is typing...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                )
                              : const SizedBox(),
                        );
                      },
                    ),
              
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: handleTyping,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.send),
                            color: const Color(0xFF9575CD),
                            onPressed: sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
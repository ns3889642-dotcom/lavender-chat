import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const Color lavender = Color(0xFF9575CD);

// Cloudinary settings
const String cloudName = 'g12vrgfi';
const String uploadPreset = 'lavender_profiles';

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore db = FirebaseFirestore.instance;

String makeChatId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort();
  return '${ids[0]}_${ids[1]}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const LavenderChatApp());
}

class LavenderChatApp extends StatelessWidget {
  const LavenderChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lavender Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: lavender),
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
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) return const UsersScreen();
        return const LoginScreen();
      },
    );
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

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> submit() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty ||
        password.isEmpty ||
        (!isLogin && name.isEmpty)) {
      showMessage('Please fill in all required fields.');
      return;
    }

    setState(() => loading = true);

    try {
      if (isLogin) {
        final result = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = result.user!;

        await db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': user.displayName ?? 'User',
          'email': user.email,
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        final result = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = result.user!;
        await user.updateDisplayName(name);

        await db.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email,
          'photoUrl': '',
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Authentication failed.');
    } catch (e) {
      showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
      appBar: AppBar(title: const Text('Lavender Chat')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const Icon(Icons.chat_rounded,
                    size: 75, color: lavender),
                const SizedBox(height: 20),
                Text(
                  isLogin ? 'Welcome Back' : 'Create Account',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                if (!isLogin) ...[
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: loading ? null : submit,
                    child: Text(
                      loading
                          ? 'Please wait...'
                          : isLogin
                              ? 'Login'
                              : 'Sign Up',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => isLogin = !isLogin);
                  },
                  child: Text(
                    isLogin
                        ? 'Create a new account'
                        : 'Already have an account? Login',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// REGISTERED USERS

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  Future<void> logout() async {
    final user = auth.currentUser;
    if (user != null) {
      await db.collection('users').doc(user.uid).set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = auth.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lavender Chat'),
        actions: [
          IconButton(
            tooltip: 'My Profile',
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await logout();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Logout error: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not load users. Check Firestore rules.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs
              .where((doc) => doc.id != currentUser.uid)
              .toList();

          if (users.isEmpty) {
            return const Center(
              child: Text('No other registered users yet.'),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final data = users[index].data();
              final name = data['name'] as String? ?? 'User';
              final photoUrl = data['photoUrl'] as String? ?? '';
              final online = data['isOnline'] == true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: lavender.withValues(alpha: 0.15),
                  backgroundImage: photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl.isEmpty
                      ? const Icon(Icons.person, color: lavender)
                      : null,
                ),
                title: Text(name),
                subtitle: Text(online ? 'Online' : 'Offline'),
                trailing: const Icon(Icons.chat_bubble_outline),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PrivateChatScreen(
                        otherUid: users[index].id,
                        otherName: name,
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

// PROFILE AND CLOUDINARY PHOTO UPLOAD

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker picker = ImagePicker();
  final TextEditingController nameController = TextEditingController();

  Uint8List? selectedPhoto;
  String photoUrl = '';
  bool saving = false;
  bool uploading = false;
  bool loadingPhoto = true;

  String get photoKey => 'profile_photo_${auth.currentUser!.uid}';

  @override
  void initState() {
    super.initState();
    nameController.text = auth.currentUser?.displayName ?? '';
    loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final user = auth.currentUser!;
      final doc = await db.collection('users').doc(user.uid).get();
      final data = doc.data();

      photoUrl = data?['photoUrl'] as String? ?? '';

      // Local copy is only a browser cache.
      final prefs = await SharedPreferences.getInstance();
      final savedPhoto = prefs.getString(photoKey);

      if (savedPhoto != null && mounted) {
        selectedPhoto = base64Decode(savedPhoto);
      }
    } catch (e) {
      debugPrint('Profile load error: $e');
    } finally {
      if (mounted) setState(() => loadingPhoto = false);
    }
  }

  Future<void> choosePhoto() async {
    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        selectedPhoto = bytes;
        uploading = true;
      });

      // Upload to Cloudinary using an unsigned upload preset.
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
        ),
      );

      request.fields['upload_preset'] = uploadPreset;
      request.fields['folder'] = 'lavender_profiles';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'profile_${auth.currentUser!.uid}.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final result = jsonDecode(response.body) as Map<String, dynamic>;

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 300) {
        throw Exception(
          result['error']?['message'] ?? 'Cloudinary upload failed.',
        );
      }

      final uploadedUrl = result['secure_url'] as String?;
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw Exception('Cloudinary did not return a photo URL.');
      }

      final user = auth.currentUser!;
      await db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'photoUrl': uploadedUrl,
      }, SetOptions(merge: true));

      // Save a local cache too.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(photoKey, base64Encode(bytes));

      if (!mounted) return;
      setState(() => photoUrl = uploadedUrl);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo uploaded successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Photo upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> saveName() async {
    final user = auth.currentUser;
    final name = nameController.text.trim();

    if (user == null || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name.')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await user.updateDisplayName(name);
      await db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'email': user.email,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name updated successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save name: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? imageProvider;

    if (selectedPhoto != null) {
      imageProvider = MemoryImage(selectedPhoto!);
    } else if (photoUrl.isNotEmpty) {
      imageProvider = NetworkImage(photoUrl);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 65,
                  backgroundColor: lavender.withValues(alpha: 0.15),
                  backgroundImage: imageProvider,
                  child: loadingPhoto
                      ? const CircularProgressIndicator()
                      : imageProvider == null
                          ? const Icon(
                              Icons.person,
                              size: 70,
                              color: lavender,
                            )
                          : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: uploading || loadingPhoto ? null : choosePhoto,
                  icon: const Icon(Icons.photo_library),
                  label: Text(uploading ? 'Uploading...' : 'Choose Photo'),
                ),
                const SizedBox(height: 24),
                Text(auth.currentUser?.email ?? 'No email'),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving ? null : saveName,
                    child: Text(saving ? 'Saving...' : 'Save Name'),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Your uploaded photo is stored online and its URL is saved '
                  'in your user profile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// PRIVATE REAL-TIME CHAT

class PrivateChatScreen extends StatefulWidget {
  final String otherUid;
  final String otherName;

  const PrivateChatScreen({
    super.key,
    required this.otherUid,
    required this.otherName,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController messageController = TextEditingController();

  String get chatId =>
      makeChatId(auth.currentUser!.uid, widget.otherUid);

  CollectionReference<Map<String, dynamic>> get messages =>
      db.collection('chats').doc(chatId).collection('messages');

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    final user = auth.currentUser;

    if (text.isEmpty || user == null) return;
    messageController.clear();

    try {
      final chatRef = db.collection('chats').doc(chatId);

      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(chatRef);

        if (!snapshot.exists) {
          transaction.set(chatRef, {
            'members': [user.uid, widget.otherUid],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      await messages.add({
        'text': text,
        'senderId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'readBy': [user.uid],
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message could not be sent: $e')),
      );
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherName),
        backgroundColor: lavender,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messages
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load messages.'),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Start the conversation!'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final text = data['text'] as String? ?? '';
                    final senderId = data['senderId'] as String? ?? '';
                    final isMe = senderId == myUid;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe
                              ? lavender.withValues(alpha: 0.8)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: lavender,
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

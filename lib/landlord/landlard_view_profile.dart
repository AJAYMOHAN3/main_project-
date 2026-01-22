import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/main.dart';
import 'dart:typed_data';

class LandlordsearchProfilePage2 extends StatefulWidget {
  // No parameters accepted as requested
  const LandlordsearchProfilePage2({super.key});

  @override
  LandlordsearchProfilePage2State createState() =>
      LandlordsearchProfilePage2State();
}

class LandlordsearchProfilePage2State
    extends State<LandlordsearchProfilePage2> {
  String? _landlordName;
  String? _profilePicUrl;
  List<Reference> _userDocs = []; // To store document references
  bool _isLoading = true;

  // Helper to determine platform
  bool kIsWeb = bool.fromEnvironment('dart.library.js_util');

  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    try {
      await Future.wait([_fetchName(), _fetchProfilePic(), _fetchUserDocs()]);
    } catch (e) {
      // debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 1. Fetch Full Name from Firestore
  Future<void> _fetchName() async {
    try {
      if (useNativeSdk) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('landlord')
            .doc(uid)
            .get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              _landlordName = data['fullName'];
            });
          }
        }
      } else {
        // REST
        final url = Uri.parse(
          '$kFirestoreBaseUrl/landlord/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['fullName'] != null) {
            if (mounted) {
              setState(() {
                _landlordName = data['fields']['fullName']['stringValue'];
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  // 2. Fetch Profile Pic from Storage
  Future<void> _fetchProfilePic() async {
    try {
      String path = '$uid/profile_pic/';
      if (useNativeSdk) {
        final list = await FirebaseStorage.instance
            .ref(path)
            .list(const ListOptions(maxResults: 1));
        if (list.items.isNotEmpty) {
          String url = await list.items.first.getDownloadURL();
          if (mounted) setState(() => _profilePicUrl = url);
        }
      } else {
        // REST
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=${Uri.encodeComponent(path)}&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String fullPath = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(fullPath);
            String downloadUrl =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) setState(() => _profilePicUrl = downloadUrl);
          }
        }
      }
    } catch (_) {}
  }

  // 3. Fetch User Docs from Storage
  Future<void> _fetchUserDocs() async {
    try {
      String path = '$uid/user_docs/';
      if (useNativeSdk) {
        final list = await FirebaseStorage.instance.ref(path).listAll();
        if (mounted) {
          setState(() {
            _userDocs = list.items;
          });
        }
      } else {
        // REST
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=${Uri.encodeComponent(path)}&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Reference> mappedRefs = [];
          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;
              mappedRefs.add(
                RestReference(name: fileName, fullPath: fullPath) as Reference,
              );
            }
          }
          if (mounted) {
            setState(() {
              _userDocs = mappedRefs;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _openDocument(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open document")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)), // Background color
          const AnimatedGradientBackground(), // Animated background
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "My Profile",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 20),

                _isLoading
                    ? const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 1. Profile Picture
                              CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.1,
                                ),
                                backgroundImage: _profilePicUrl != null
                                    ? NetworkImage(_profilePicUrl!)
                                    : null,
                                child: _profilePicUrl == null
                                    ? const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 15),

                              // 2. Full Name
                              Text(
                                _landlordName ?? "Name Not Found",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 40),

                              // 3. User Documents Section
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "My Documents",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),

                              if (_userDocs.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "No documents uploaded.",
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _userDocs.length,
                                  itemBuilder: (context, index) {
                                    final doc = _userDocs[index];
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.description,
                                          color: Colors.blueAccent,
                                        ),
                                        title: Text(
                                          doc.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.open_in_new,
                                          color: Colors.white54,
                                        ),
                                        onTap: () => _openDocument(doc),
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Helper for REST References on Web/Windows ---
class RestReference implements Reference {
  @override
  final String name;
  @override
  final String fullPath;

  RestReference({required this.name, required this.fullPath});

  @override
  Future<String> getDownloadURL() async {
    String encodedName = Uri.encodeComponent(fullPath);
    return '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
  }

  @override
  String get bucket => kStorageBucket;

  // Unused implementations
  @override
  FirebaseStorage get storage => throw UnimplementedError();
  @override
  Reference get root => throw UnimplementedError();
  @override
  Reference get parent => throw UnimplementedError();
  @override
  Reference child(String path) => throw UnimplementedError();
  @override
  Future<void> delete() => throw UnimplementedError();
  @override
  Future<FullMetadata> getMetadata() => throw UnimplementedError();
  @override
  Future<ListResult> list([ListOptions? options]) => throw UnimplementedError();
  @override
  Future<ListResult> listAll() => throw UnimplementedError();
  @override
  Future<Uint8List?> getData([int maxDownloadSizeBytes = 10485760]) =>
      throw UnimplementedError();
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putBlob(dynamic blob, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) =>
      throw UnimplementedError();
  @override
  Future<FullMetadata> updateMetadata(SettableMetadata metadata) =>
      throw UnimplementedError();
  @override
  UploadTask putString(
    String data, {
    PutStringFormat format = PutStringFormat.raw,
    SettableMetadata? metadata,
  }) => throw UnimplementedError();
  @override
  DownloadTask writeToFile(File file) => throw UnimplementedError();
}

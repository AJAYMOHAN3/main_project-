import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/tenant/tenant.dart';
import 'package:main_project/main.dart';
import 'package:main_project/config.dart';
import 'dart:typed_data';

class LandlordsearchProfilePage2 extends StatefulWidget {
  const LandlordsearchProfilePage2({super.key});

  @override
  LandlordsearchProfilePage2State createState() =>
      LandlordsearchProfilePage2State();
}

class LandlordsearchProfilePage2State
    extends State<LandlordsearchProfilePage2> {
  String? _landlordName;
  String? _profilePicUrl;

  // --- NEW: Replaced docs list with verification & reviews state ---
  bool _isAadharVerified = false;
  List<Map<String, dynamic>> _reviews = [];

  bool _isLoading = true;
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    try {
      // CHANGED: Replaced _fetchUserDocs with _fetchReviews
      await Future.wait([_fetchName(), _fetchProfilePic(), _fetchReviews()]);
    } catch (e) {
      // debugPrint("Error fetching data: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 1. Fetch Full Name and Aadhaar Verification from Firestore
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
              // NEW: Fetch verification status
              if (data.containsKey('aadhar')) {
                _isAadharVerified = data['aadhar'] == 'verified';
              }
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
          if (data['fields'] != null) {
            if (mounted) {
              setState(() {
                if (data['fields']['fullName'] != null) {
                  _landlordName = data['fields']['fullName']['stringValue'];
                }
                // NEW: Fetch verification status via REST
                if (data['fields']['aadhar'] != null) {
                  _isAadharVerified =
                      data['fields']['aadhar']['stringValue'] == 'verified';
                }
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

  // 3. NEW: Fetch Reviews from Firestore
  Future<void> _fetchReviews() async {
    try {
      if (useNativeSdk) {
        DocumentSnapshot revDoc = await FirebaseFirestore.instance
            .collection('reviews')
            .doc(uid)
            .get();
        if (revDoc.exists) {
          final data = revDoc.data() as Map<String, dynamic>;
          if (data.containsKey('reviews')) {
            if (mounted) {
              setState(() {
                _reviews = List<Map<String, dynamic>>.from(data['reviews']);
              });
            }
          }
        }
      } else {
        // REST
        final url = Uri.parse(
          '$kFirestoreBaseUrl/reviews/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['reviews'] != null) {
            var rawList =
                data['fields']['reviews']['arrayValue']['values'] as List?;
            if (rawList != null) {
              List<Map<String, dynamic>> parsedReviews = [];
              for (var item in rawList) {
                if (item['mapValue'] != null &&
                    item['mapValue']['fields'] != null) {
                  Map<String, dynamic> cleanMap = {};
                  item['mapValue']['fields'].forEach((k, v) {
                    cleanMap[k] = _parseFirestoreRestValue(v);
                  });
                  parsedReviews.add(cleanMap);
                }
              }
              if (mounted) {
                setState(() {
                  _reviews = parsedReviews;
                });
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  // REST Parsing Helper
  dynamic _parseFirestoreRestValue(Map<String, dynamic> valueMap) {
    if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
    if (valueMap.containsKey('integerValue')) {
      return int.tryParse(valueMap['integerValue'] ?? '0');
    }
    if (valueMap.containsKey('doubleValue')) {
      return double.tryParse(valueMap['doubleValue'] ?? '0.0');
    }
    if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];
    if (valueMap.containsKey('arrayValue')) {
      var values = valueMap['arrayValue']['values'] as List?;
      if (values == null) return [];
      return values.map((v) => _parseFirestoreRestValue(v)).toList();
    }
    return null;
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

                              // 3. Identity Verification Section
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Identity Verification",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),

                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: _isAadharVerified
                                    ? Row(
                                        children: [
                                          const Icon(
                                            Icons.verified_user,
                                            color: Colors.green,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: const [
                                                Text(
                                                  "Identity Verified",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  "Aadhaar verified through DigiLocker",
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.orange,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: const [
                                                Text(
                                                  "Identity Not Verified",
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  "This landlord has not verified their identity yet.",
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 40),

                              // 4. My Reviews Section
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "My Reviews",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),

                              if (_reviews.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "No reviews yet.",
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _reviews.length,
                                  itemBuilder: (context, index) {
                                    final rev = _reviews[index];
                                    final String tName =
                                        rev['tenantName'] ?? "Anonymous";
                                    final double rating =
                                        double.tryParse(
                                          rev['rating']?.toString() ?? '5.0',
                                        ) ??
                                        5.0;
                                    final String reviewText =
                                        rev['review'] ?? "";

                                    return _buildReviewCard(
                                      tenantName: tName,
                                      rating: rating,
                                      review: reviewText,
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

  // Widget to display individual reviews
  Widget _buildReviewCard({
    required String tenantName,
    required double rating,
    required String review,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Text(
                tenantName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (index) => Icon(
                    index < rating.floor()
                        ? Icons.star
                        : index < rating
                        ? Icons.star_half
                        : Icons.star_border,
                    color: Colors.yellow.shade600,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            review,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// Keeping RestReference class to satisfy any missing dependencies for this specific file scope
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

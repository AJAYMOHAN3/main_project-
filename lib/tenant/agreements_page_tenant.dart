import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

class AgreementsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const AgreementsPage2({super.key, required this.onBack});

  @override
  State<AgreementsPage2> createState() => _AgreementsPage2State();
}

class _AgreementsPage2State extends State<AgreementsPage2> {
  final String _currentUid = uid;
  List<Reference> _agreementFiles = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAgreements();
  }

  // --- UPDATED: Multi-platform Fetch Logic ---
  Future<void> _fetchAgreements() async {
    if (_currentUid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = "User not logged in.";
      });
      return;
    }

    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final storageRef = FirebaseStorage.instance.ref(
          'tagreement/$_currentUid/',
        );
        final listResult = await storageRef.listAll();

        if (mounted) {
          setState(() {
            _agreementFiles = listResult.items;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = "Failed to load agreements.";
          });
        }
      }
    }
    // 2. REST LOGIC (Web/Windows/macOS/Linux)
    else {
      try {
        // Encode the path prefix (tagreement/UID/)
        final String prefix = 'tagreement/$_currentUid/';
        final String encodedPrefix = Uri.encodeComponent(prefix);

        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=$encodedPrefix&key=$kFirebaseAPIKey',
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          List<Reference> mappedRefs = [];

          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name']; // "tagreement/uid/file.pdf"
              String fileName = fullPath.split('/').last; // "file.pdf"

              // Ensure we are adding files, not the folder itself if returned
              if (fileName.isNotEmpty) {
                mappedRefs.add(
                  RestReference(name: fileName, fullPath: fullPath)
                      as Reference,
                );
              }
            }
          }

          if (mounted) {
            setState(() {
              _agreementFiles = mappedRefs;
              _isLoading = false;
            });
          }
        } else {
          // If empty or bucket not found, just show empty list
          if (mounted) {
            setState(() {
              _agreementFiles = [];
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = "Failed to load agreements.";
          });
        }
      }
    }
  }

  Future<void> _openPdf(Reference ref) async {
    try {
      final String url = await ref.getDownloadURL();
      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch PDF viewer")),
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
          // Background (Using the one from your snippet)
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Agreements",
                  onBack: widget.onBack,
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Agreements List",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Content Area
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        )
                      : _agreementFiles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_off,
                                size: 50,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "No agreements found.",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _agreementFiles.length,
                          itemBuilder: (context, index) {
                            final file = _agreementFiles[index];
                            // Clean up filename for display
                            final name = file.name
                                .replaceAll('.pdf', '')
                                .replaceAll('_', ' ');

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.redAccent,
                                  size: 30,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.visibility,
                                  color: Colors.white54,
                                ),
                                onTap: () => _openPdf(file),
                              ),
                            );
                          },
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

class RestReference implements Reference {
  @override
  final String name;
  @override
  final String fullPath;

  RestReference({required this.name, required this.fullPath});

  @override
  Future<String> getDownloadURL() async {
    // Uses global constants kStorageBaseUrl and kFirebaseAPIKey
    String encodedName = Uri.encodeComponent(fullPath);
    return '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
  }

  // --- Boilerplate to satisfy Reference interface ---
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

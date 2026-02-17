import 'dart:convert';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/config.dart';

class AgreementsPage extends StatefulWidget {
  final VoidCallback onBack;
  const AgreementsPage({super.key, required this.onBack});

  @override
  State<AgreementsPage> createState() => _AgreementsPageState();
}

class _AgreementsPageState extends State<AgreementsPage> {
  final String _currentUid = uid;
  List<Reference> _agreementFiles = [];
  bool _isLoading = true;
  String? _error;

  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchAgreements();
  }

  Future<void> _fetchAgreements() async {
    if (_currentUid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = "User not logged in.";
      });
      return;
    }

    try {
      // 1. SDK LOGIC (Android/iOS)
      if (useNativeSdk) {
        // Path: lagreement / [LandlordUID] /
        final storageRef = FirebaseStorage.instance.ref(
          'lagreement/$_currentUid/',
        );
        final listResult = await storageRef.listAll();

        if (mounted) {
          setState(() {
            _agreementFiles = listResult.items;
            _isLoading = false;
          });
        }
      }
      // 2. REST LOGIC (Web/Windows/MacOS/Linux)
      else {
        final String prefix = 'lagreement/$_currentUid/';
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
              String fullPath = item['name']; // "lagreement/uid/file.pdf"
              String fileName = fullPath.split('/').last; // "file.pdf"

              if (fileName.isNotEmpty) {
                // Use RestReference to match the Reference interface
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
          // Handle empty folder or 404 (bucket logic)
          if (mounted) {
            setState(() {
              _agreementFiles = [];
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      //print("Error fetching agreements: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = "Failed to load agreements.";
        });
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
          // 1. Dark Background
          Container(color: const Color(0xFF141E30)),

          // 2. Twinkling Star Layer
          const TwinklingStarBackground(),

          SafeArea(
            child: Column(
              children: [
                // 💡 PASS THE onBack CALLBACK HERE
                CustomTopNavBar(
                  showBack: true,
                  title: "Agreements",
                  onBack: widget.onBack,
                ),

                // Screen Title
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
                                Icons.folder_open,
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
                            // Format filename (remove extension for cleaner look)
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

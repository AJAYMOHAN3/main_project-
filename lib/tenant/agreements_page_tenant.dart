import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/config.dart';

class AgreementsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const AgreementsPage2({super.key, required this.onBack});

  @override
  State<AgreementsPage2> createState() => _AgreementsPage2State();
}

class _AgreementsPage2State extends State<AgreementsPage2> {
  final String _currentUid = uid;
  List<Reference> _agreementFiles = [];

  // NEW: Map to link a fileName to its cryptographic dagHash
  final Map<String, String> _fileToHashMap = {};

  bool _isLoading = true;
  String? _error;

  // Helper to determine platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  // --- FETCH STORAGE FILES AND FIRESTORE HASHES ---
  Future<void> _fetchData() async {
    if (_currentUid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = "User not logged in.";
      });
      return;
    }

    try {
      // 1. FETCH FIRESTORE DB (To get the DAG Hashes)
      if (useNativeSdk) {
        final doc = await FirebaseFirestore.instance
            .collection('tagreements')
            .doc(_currentUid)
            .get();
        if (doc.exists && doc.data() != null) {
          final agreements = doc.data()!['agreements'] as List<dynamic>? ?? [];
          for (var a in agreements) {
            if (a['fileName'] != null && a['dagHash'] != null) {
              _fileToHashMap[a['fileName']] = a['dagHash'];
            }
          }
        }
      } else {
        // REST Logic for DB
        final dbUrl = Uri.parse(
          '$kFirestoreBaseUrl/tagreements/$_currentUid?key=$kFirebaseAPIKey',
        );
        final dbResp = await http.get(dbUrl);
        if (dbResp.statusCode == 200) {
          final data = jsonDecode(dbResp.body);
          if (data['fields'] != null && data['fields']['agreements'] != null) {
            var values =
                data['fields']['agreements']['arrayValue']['values'] as List?;
            if (values != null) {
              for (var v in values) {
                var map = v['mapValue']['fields'];
                if (map != null) {
                  String fName = map['fileName']?['stringValue'] ?? '';
                  String dHash = map['dagHash']?['stringValue'] ?? '';
                  if (fName.isNotEmpty && dHash.isNotEmpty) {
                    _fileToHashMap[fName] = dHash;
                  }
                }
              }
            }
          }
        }
      }

      // 2. FETCH STORAGE FILES (To display the PDFs)
      if (useNativeSdk) {
        final storageRef = FirebaseStorage.instance.ref(
          'tagreement/$_currentUid/',
        );
        final listResult = await storageRef.listAll();
        if (mounted) {
          setState(() {
            _agreementFiles = listResult.items;
          });
        }
      } else {
        // REST Logic for Storage
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
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;
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
            });
          }
        } else {
          if (mounted) setState(() => _agreementFiles = []);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Failed to load agreements.";
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- OPEN PDF ---
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

  // --- NEW: VERIFY DAG INTEGRITY ---
  Future<void> _verifyIntegrity(String fileName) async {
    final String? dagHash = _fileToHashMap[fileName];

    if (dagHash == null || dagHash.isEmpty) {
      _showIntegrityDialog(
        isVerified: false,
        message:
            "No cryptographic signature found for this document. It was likely created before the Web3 upgrade.",
        hash: "N/A",
      );
      return;
    }

    // Show loading indicator while verifying
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      ),
    );

    bool isValid = false;

    // Verify hash against the dag_nodes ledger
    try {
      if (useNativeSdk) {
        final doc = await FirebaseFirestore.instance
            .collection('dag_nodes')
            .doc(dagHash)
            .get();
        isValid = doc.exists;
      } else {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/dag_nodes/$dagHash?key=$kFirebaseAPIKey',
        );
        final resp = await http.get(url);
        isValid = resp.statusCode == 200;
      }
    } catch (e) {
      debugPrint("Verification error: $e");
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loading indicator

    if (isValid) {
      _showIntegrityDialog(
        isVerified: true,
        message:
            "This agreement is cryptographically secured and immutable on the DAG Ledger. The data has not been tampered with.",
        hash: dagHash,
      );
    } else {
      _showIntegrityDialog(
        isVerified: false,
        message:
            "WARNING: Hash mismatch. The cryptographic signature for this document could not be validated against the ledger.",
        hash: dagHash,
      );
    }
  }

  // --- DAG VERIFICATION UI DIALOG ---
  void _showIntegrityDialog({
    required bool isVerified,
    required String message,
    required String hash,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isVerified ? Icons.verified_user : Icons.warning_amber_rounded,
              color: isVerified ? Colors.tealAccent : Colors.redAccent,
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              "Security Audit",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 20),
            const Text(
              "Ledger Hash (txId):",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                hash,
                style: TextStyle(
                  color: isVerified ? Colors.tealAccent : Colors.redAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
                            final fileName = file.name;
                            final displayName = fileName
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
                                  displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // UPDATED: Trailing Row with Verification and View Buttons
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.security,
                                        color: Colors.tealAccent,
                                      ),
                                      tooltip: "Verify Integrity",
                                      onPressed: () =>
                                          _verifyIntegrity(fileName),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.visibility,
                                        color: Colors.white54,
                                      ),
                                      tooltip: "View PDF",
                                      onPressed: () => _openPdf(file),
                                    ),
                                  ],
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

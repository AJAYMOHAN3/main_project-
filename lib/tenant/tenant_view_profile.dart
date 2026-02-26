import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';

class TenantsearchProfilePage2 extends StatefulWidget {
  final VoidCallback onBack;

  const TenantsearchProfilePage2({super.key, required this.onBack});

  @override
  State<TenantsearchProfilePage2> createState() =>
      _TenantsearchProfilePage2State();
}

class _TenantsearchProfilePage2State extends State<TenantsearchProfilePage2> {
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true;

  List<Reference> _uploadedDocs = [];
  bool _isLoadingDocs = true;

  late final String _tenantUid;

  @override
  void initState() {
    super.initState();

    //final uid = FirebaseAuth.instance.currentuid;
    /*if (uid == null) {
      debugPrint("No logged-in tenant");
      return;
    }*/

    _tenantUid = uid;

    _fetchTenantData();
    _fetchTenantDocuments();
  }

  // ---------------- FETCH TENANT DATA ----------------
  Future<void> _fetchTenantData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tenant')
          .doc(_tenantUid)
          .get();

      if (doc.exists) {
        setState(() {
          _tenantName = doc['fullName'];
        });
      }
    } catch (e) {
      debugPrint("Error fetching tenant data: $e");
    }

    try {
      final result = await FirebaseStorage.instance
          .ref('$_tenantUid/profile_pic/')
          .list(const ListOptions(maxResults: 1));

      if (result.items.isNotEmpty) {
        final url = await result.items.first.getDownloadURL();
        setState(() {
          _profilePicUrl = url;
        });
      }
    } catch (e) {
      debugPrint("No profile picture found");
    } finally {
      setState(() => _isLoadingProfile = false);
    }
  }

  // ---------------- FETCH DOCUMENTS ----------------
  Future<void> _fetchTenantDocuments() async {
    try {
      final result = await FirebaseStorage.instance
          .ref('$_tenantUid/user_docs/')
          .listAll();

      setState(() {
        _uploadedDocs = result.items;
        _isLoadingDocs = false;
      });
    } catch (e) {
      debugPrint("Error fetching documents: $e");
      setState(() => _isLoadingDocs = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true, // Disable automatic system pop
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        // Manually go back to the previous page
        Navigator.of(context).pop();
      },

      child: Scaffold(
        body: Stack(
          children: [
            const AnimatedGradientBackground(),
            SafeArea(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Tenant Profile",
                    onBack: widget.onBack,
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // -------- PROFILE ----------
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white12,
                            backgroundImage: _profilePicUrl != null
                                ? NetworkImage(_profilePicUrl!)
                                : null,
                            child: _isLoadingProfile
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : (_profilePicUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.white,
                                        )
                                      : null),
                          ),
                          const SizedBox(height: 16),

                          Text(
                            _tenantName ?? "Tenant",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 30),

                          // -------- DOCUMENTS ----------
                          Text(
                            "Uploaded Documents",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          _isLoadingDocs
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : _uploadedDocs.isEmpty
                              ? const Text(
                                  "No documents uploaded",
                                  style: TextStyle(color: Colors.white70),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _uploadedDocs.length,
                                  itemBuilder: (context, index) {
                                    final ref = _uploadedDocs[index];
                                    return GlassmorphismContainer(
                                      opacity: 0.1,
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.description,
                                          color: Colors.blueAccent,
                                        ),
                                        title: Text(
                                          ref.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        onTap: () async {
                                          final url = await ref
                                              .getDownloadURL();
                                          await launchUrl(
                                            Uri.parse(url),
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

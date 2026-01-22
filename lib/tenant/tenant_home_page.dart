import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

class TenantProfilePage extends StatefulWidget {
  final VoidCallback onBack; // callback for back button

  const TenantProfilePage({super.key, required this.onBack});

  @override
  TenantProfilePageState createState() => TenantProfilePageState();
}

class TenantProfilePageState extends State<TenantProfilePage> {
  // Updated DocumentField to handle PlatformFile for Web/Desktop
  List<DocumentField> userDocuments = [DocumentField()];
  final List<String> userDocOptions = [
    "Aadhar",
    "PAN",
    "License",
    "Birth Certificate",
  ];

  // --- State variables for fetched data ---
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true; // Loading indicator for initial fetch
  // --- NEW: State for User Documents ---
  List<Reference> _uploadedDocs = [];
  bool _isLoadingDocs = true;

  // --- NEW: State for Rented Homes (Fetched from trequests) ---
  List<Map<String, dynamic>> _rentedHomes = [];
  bool _isLoadingHomes = true;

  // --- initState to fetch data ---
  @override
  void initState() {
    super.initState();
    _fetchTenantData();
    _fetchUploadedDocuments(); // Fetch docs on init
    _fetchRentedHomes(); // Fetch rented homes on init
  }

  Future<void> _fetchTenantData() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;

    //if (mounted) setState(() => _isLoadingProfile = false);
    //return;

    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        // Fetch Name
        DocumentSnapshot tenantDoc = await FirebaseFirestore.instance
            .collection('tenant')
            .doc(uid)
            .get();
        if (tenantDoc.exists && mounted) {
          var data = tenantDoc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('fullName')) {
            setState(() {
              _tenantName = data['fullName'] as String?;
            });
          }
        }
        // Fetch Profile Pic
        ListResult result = await FirebaseStorage.instance
            .ref('$uid/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (result.items.isNotEmpty && mounted) {
          String url = await result.items.first.getDownloadURL();
          setState(() => _profilePicUrl = url);
        }
      } catch (e) {
        // Ignore errors
      } finally {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
    // 2. REST LOGIC (Web/Desktop)
    else {
      try {
        // Fetch Name
        final tenantUrl = Uri.parse(
          '$kFirestoreBaseUrl/tenant/$uid?key=$kFirebaseAPIKey',
        );
        final tenantRes = await http.get(tenantUrl);
        if (tenantRes.statusCode == 200) {
          final data = jsonDecode(tenantRes.body);
          if (data['fields'] != null && data['fields']['fullName'] != null) {
            setState(() {
              _tenantName = data['fields']['fullName']['stringValue'];
            });
          }
        }

        // Fetch Profile Pic
        final picUrl = Uri.parse(
          '$kStorageBaseUrl?prefix=$uid/profile_pic/&key=$kFirebaseAPIKey',
        );
        final picRes = await http.get(picUrl);
        if (picRes.statusCode == 200) {
          final data = jsonDecode(picRes.body);
          if (data['items'] != null && (data['items'] as List).isNotEmpty) {
            String objectName = data['items'][0]['name'];
            String encodedName = Uri.encodeComponent(objectName);
            String url =
                '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
            if (mounted) setState(() => _profilePicUrl = url);
          }
        }
      } catch (e) {
        // Ignore
      } finally {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
  }

  // --- NEW: Fetch User Documents from Storage ---
  Future<void> _fetchUploadedDocuments() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    //if (uid == null) return;

    // 1. SDK LOGIC
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final ListResult result = await FirebaseStorage.instance
            .ref('$uid/user_docs/')
            .listAll();
        if (mounted) {
          setState(() {
            _uploadedDocs = result.items;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingDocs = false);
      }
    }
    // 2. REST LOGIC
    else {
      try {
        final url = Uri.parse(
          '$kStorageBaseUrl?prefix=$uid/user_docs/&key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        List<Reference> mappedRefs = [];

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['items'] != null) {
            for (var item in data['items']) {
              String fullPath = item['name'];
              String fileName = fullPath.split('/').last;
              // Add to list via RestReference wrapper
              mappedRefs.add(
                RestReference(name: fileName, fullPath: fullPath) as Reference,
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _uploadedDocs = mappedRefs;
            _isLoadingDocs = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingDocs = false);
      }
    }
  }

  // --- NEW: Fetch Rented Homes from trequests ---
  Future<void> _fetchRentedHomes() async {
    //final String? uid = FirebaseAuth.instance.currentUser?.uid;
    /*if (uid == null) {
      if (mounted) setState(() => _isLoadingHomes = false);
      return;
    }*/

    // 1. SDK LOGIC
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('trequests')
            .doc(uid)
            .get();

        if (doc.exists && mounted) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('requests')) {
            List<dynamic> allRequests = data['requests'];
            List<Map<String, dynamic>> accepted = allRequests
                .where((req) => req['status'] == 'accepted')
                .map((req) => req as Map<String, dynamic>)
                .toList();

            setState(() {
              _rentedHomes = accepted;
              _isLoadingHomes = false;
            });
          } else {
            if (mounted) setState(() => _isLoadingHomes = false);
          }
        } else {
          if (mounted) setState(() => _isLoadingHomes = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingHomes = false);
      }
    }
    // 2. REST LOGIC
    else {
      try {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/trequests/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['requests'] != null) {
            var rawList =
                data['fields']['requests']['arrayValue']['values'] as List?;
            if (rawList != null) {
              List<Map<String, dynamic>> accepted = [];
              for (var item in rawList) {
                if (item['mapValue'] != null &&
                    item['mapValue']['fields'] != null) {
                  Map<String, dynamic> cleanMap = {};
                  item['mapValue']['fields'].forEach((key, val) {
                    cleanMap[key] = _parseFirestoreRestValue(val);
                  });
                  if (cleanMap['status'] == 'accepted') {
                    accepted.add(cleanMap);
                  }
                }
              }
              if (mounted) {
                setState(() {
                  _rentedHomes = accepted;
                  _isLoadingHomes = false;
                });
                return;
              }
            }
          }
        }
        if (mounted) setState(() => _isLoadingHomes = false);
      } catch (e) {
        if (mounted) setState(() => _isLoadingHomes = false);
      }
    }
  }

  // --- NEW: Update Existing Document from List ---
  Future<void> _updateExistingDocument(Reference ref) async {
    // FIX: Use PlatformFile for Web/Desktop compatibility
    PlatformFile? pickedFile = await _pickDocument();
    if (pickedFile != null) {
      //final String? uid = FirebaseAuth.instance.currentUser?.uid;
      //if (uid == null) return;

      try {
        // 1. Delete old file logic
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          await ref.delete();
        } else {
          // REST Delete logic
          String encodedPath = Uri.encodeComponent(
            (ref as RestReference).fullPath,
          );
          final delUrl = Uri.parse(
            '$kStorageBaseUrl/$encodedPath?key=$kFirebaseAPIKey',
          );
          await http.delete(delUrl);
        }

        // 2. Construct new name
        String oldName = ref.name;
        String baseName = oldName.contains('.')
            ? oldName.substring(0, oldName.lastIndexOf('.'))
            : oldName;
        String extension = pickedFile.name.split('.').last;
        String newFileName = '$baseName.$extension';

        // 3. Upload new file
        await _uploadFileToStorage(pickedFile, '$uid/user_docs/$newFileName');

        // 4. Refresh list
        _fetchUploadedDocuments();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error updating file: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- FIX: Returns PlatformFile to handle bytes on Web/Desktop ---
  Future<PlatformFile?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      withData: true, // REQUIRED for Web/Desktop bytes
    );
    if (result != null) {
      return result.files.single;
    }
    return null;
  }

  // --- FIX: Accepts PlatformFile to handle uploads on all platforms ---
  Future<String?> _uploadFileToStorage(
    PlatformFile pFile,
    String storagePath,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Uploading ${storagePath.split('/').last}...'),
        duration: const Duration(minutes: 1),
      ),
    );

    try {
      String? downloadUrl;

      // 1. SDK LOGIC
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        if (pFile.path != null) {
          File file = File(pFile.path!);
          final ref = FirebaseStorage.instance.ref().child(storagePath);
          UploadTask uploadTask = ref.putFile(file);
          TaskSnapshot snapshot = await uploadTask;
          downloadUrl = await snapshot.ref.getDownloadURL();
        }
      }
      // 2. REST LOGIC
      else {
        if (pFile.bytes != null) {
          String encodedPath = Uri.encodeComponent(storagePath);
          String uploadUrl =
              "$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey";

          var response = await http.post(
            Uri.parse(uploadUrl),
            body: pFile.bytes,
            headers: {"Content-Type": "application/octet-stream"},
          );

          if (response.statusCode == 200) {
            downloadUrl =
                "$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey";
          }
        }
      }

      scaffoldMessenger.hideCurrentSnackBar();
      if (downloadUrl != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              '${storagePath.split('/').last} uploaded successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        return downloadUrl;
      } else {
        throw "Upload failed or returned null URL";
      }
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to upload ${storagePath.split('/').last}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  // --- Function to handle picking AND uploading user document ---
  Future<void> _pickAndUploadUserDocument(int index) async {
    final docField = userDocuments[index];
    if (docField.selectedDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select document type first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    PlatformFile? pickedFile = await _pickDocument(); // Changed to PlatformFile
    if (pickedFile != null) {
      setState(() {
        docField.pickedFile =
            pickedFile; // Ensure DocumentField supports PlatformFile
      });

      //final String? uid = FirebaseAuth.instance.currentUser?.uid;
      /* if (uid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }*/

      // Check and replace existing
      for (var existingRef in _uploadedDocs) {
        String existingName = existingRef.name;
        String existingBase = existingName.contains('.')
            ? existingName.substring(0, existingName.lastIndexOf('.'))
            : existingName;

        if (existingBase == docField.selectedDoc) {
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
            await existingRef.delete();
          } else {
            // REST Delete
            String encodedPath = Uri.encodeComponent(
              (existingRef as RestReference).fullPath,
            );
            await http.delete(
              Uri.parse('$kStorageBaseUrl/$encodedPath?key=$kFirebaseAPIKey'),
            );
          }
        }
      }

      String fileName = docField.selectedDoc!;
      String extension = pickedFile.name.split('.').last;
      if (extension.isNotEmpty && extension.length <= 4) {
        fileName += '.$extension';
      }
      String storagePath = '$uid/user_docs/$fileName';

      String? downloadUrl = await _uploadFileToStorage(pickedFile, storagePath);

      if (downloadUrl != null && mounted) {
        _fetchUploadedDocuments();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const AnimatedGradientBackground(),
            SafeArea(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
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
                                          color: Colors.deepPurple,
                                        )
                                      : null),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _tenantName ?? "Tenant Name",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            "User Documents",
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
                              : (_uploadedDocs.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          "No documents uploaded",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemCount: _uploadedDocs.length,
                                        itemBuilder: (context, index) {
                                          final ref = _uploadedDocs[index];
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: GlassmorphismContainer(
                                              opacity: 0.1,
                                              child: ListTile(
                                                onTap: () async {
                                                  try {
                                                    String url = await ref
                                                        .getDownloadURL();
                                                    final Uri uri = Uri.parse(
                                                      url,
                                                    );
                                                    if (await canLaunchUrl(
                                                      uri,
                                                    )) {
                                                      await launchUrl(
                                                        uri,
                                                        mode: LaunchMode
                                                            .externalApplication,
                                                      );
                                                    } else {
                                                      throw 'Could not launch $url';
                                                    }
                                                  } catch (e) {
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          "Could not open file: $e",
                                                        ),
                                                        backgroundColor:
                                                            Colors.red,
                                                      ),
                                                    );
                                                  }
                                                },
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
                                                trailing: ElevatedButton(
                                                  onPressed: () =>
                                                      _updateExistingDocument(
                                                        ref,
                                                      ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.orange.shade700,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 8,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    "Update",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      )),
                          const SizedBox(height: 30),
                          Text(
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: userDocuments.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildUserDocField(i),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                userDocuments.add(DocumentField());
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Document",
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            "My Rented Homes",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _isLoadingHomes
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : (_rentedHomes.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Text(
                                          "No rented homes found.",
                                          style: TextStyle(
                                            color: Colors.white70,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: _rentedHomes.length,
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          final req = _rentedHomes[index];
                                          final String name =
                                              req['apartmentName'] ??
                                              "Rented Property";
                                          final String landlord =
                                              req['landlordName'] ??
                                              "Unknown Landlord";

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: GlassmorphismContainer(
                                              opacity: 0.1,
                                              child: ListTile(
                                                leading: const Icon(
                                                  Icons.home,
                                                  color: Colors.greenAccent,
                                                ),
                                                title: Text(
                                                  name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                subtitle: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Landlord: $landlord",
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                    const Text(
                                                      "Status: Accepted",
                                                      style: TextStyle(
                                                        color: Colors
                                                            .lightGreenAccent,
                                                        fontSize: 12,
                                                        fontStyle:
                                                            FontStyle.italic,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      )),
                          const SizedBox(height: 40),
                          Text(
                            "Landlord Reviews",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            children: [
                              _buildReviewCard(
                                landlordName: "Mr. Sharma",
                                rating: 4.5,
                                review:
                                    "Great tenant! Paid rent on time and kept the property clean.",
                              ),
                              const SizedBox(height: 12),
                              _buildReviewCard(
                                landlordName: "Mrs. Fernandes",
                                rating: 5.0,
                                review:
                                    "Very cooperative and responsible tenant. Would definitely rent again.",
                              ),
                              const SizedBox(height: 12),
                              _buildReviewCard(
                                landlordName: "Mr. Khan",
                                rating: 4.0,
                                review:
                                    "Good experience overall. Communication could be a bit faster, but otherwise great!",
                              ),
                            ],
                          ),
                          const SizedBox(height: 60),
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

  Widget _buildReviewCard({
    required String landlordName,
    required double rating,
    required String review,
  }) {
    return GlassmorphismContainer(
      opacity: 0.1,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  landlordName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              review,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDocField(int index) {
    final docField = userDocuments[index];
    final selectedDocs = userDocuments
        .map((e) => e.selectedDoc)
        .whereType<String>()
        .toList();
    final availableOptions = userDocOptions
        .where(
          (doc) => !selectedDocs.contains(doc) || doc == docField.selectedDoc,
        )
        .toList();

    return GlassmorphismContainer(
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Document",
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: availableOptions
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc,
                      child: Text(
                        doc,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() => docField.selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.name, // FIX: Use .name for Web safety
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              tooltip: "Clear selected file",
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: () => _pickAndUploadUserDocument(index),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: const Text(
                "Upload",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document row",
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
        ],
      ),
    );
  }
}

class DocumentField {
  String? selectedDoc;
  PlatformFile? pickedFile; // Changed from File? to PlatformFile?
  String? downloadUrl;

  DocumentField({this.selectedDoc, this.pickedFile, this.downloadUrl});
}

dynamic _parseFirestoreRestValue(Map<String, dynamic> valueMap) {
  if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
  if (valueMap.containsKey('integerValue')) {
    return int.tryParse(valueMap['integerValue'] ?? '0');
  }
  if (valueMap.containsKey('doubleValue')) {
    return double.tryParse(valueMap['doubleValue'] ?? '0.0');
  }
  if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];

  // Handle Array (Recursion)
  if (valueMap.containsKey('arrayValue')) {
    var values = valueMap['arrayValue']['values'] as List?;
    if (values == null) return [];
    return values.map((v) => _parseFirestoreRestValue(v)).toList();
  }

  // Handle Map (Recursion)
  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    var result = <String, dynamic>{};
    fields.forEach((key, value) {
      result[key] = _parseFirestoreRestValue(value);
    });
    return result;
  }

  return null;
}

/// A Mock class to simulate a Firebase Reference for REST calls
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

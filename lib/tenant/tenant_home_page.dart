import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:main_project/landlord/landlord.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:main_project/config.dart';

class TenantProfilePage extends StatefulWidget {
  final VoidCallback onBack;

  const TenantProfilePage({super.key, required this.onBack});

  @override
  TenantProfilePageState createState() => TenantProfilePageState();
}

class TenantProfilePageState extends State<TenantProfilePage> {
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
  bool _isLoadingProfile = true;

  // --- User Documents ---
  List<Reference> _uploadedDocs = [];
  bool _isLoadingDocs = true;
  bool _isUploadingNewDocs = false; // NEW: State for bulk upload button

  // --- Rented Homes ---
  List<Map<String, dynamic>> _rentedHomes = [];
  bool _isLoadingHomes = true;

  @override
  void initState() {
    super.initState();
    _fetchTenantData();
    _fetchUploadedDocuments();
    _fetchRentedHomes();
  }

  Future<void> _fetchTenantData() async {
    // 1. SDK LOGIC (Android/iOS)
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
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

  Future<void> _fetchUploadedDocuments() async {
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

  Future<void> _fetchRentedHomes() async {
    // 1. SDK LOGIC
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        // CHANGED: Querying the 'tagreements' collection instead of 'trequests'
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('tagreements')
            .doc(uid)
            .get();

        if (doc.exists && mounted) {
          Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('agreements')) {
            // CHANGED: Key is 'agreements'
            List<dynamic> allAgreements = data['agreements'];
            // Removed status check, all entries in this array are valid agreements
            List<Map<String, dynamic>> parsedAgreements = allAgreements
                .map((req) => req as Map<String, dynamic>)
                .toList();

            setState(() {
              _rentedHomes = parsedAgreements;
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
        // CHANGED: URL points to 'tagreements'
        final url = Uri.parse(
          '$kFirestoreBaseUrl/tagreements/$uid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null && data['fields']['agreements'] != null) {
            // CHANGED: Key is 'agreements'
            var rawList =
                data['fields']['agreements']['arrayValue']['values'] as List?;
            if (rawList != null) {
              List<Map<String, dynamic>> parsedAgreements = [];
              for (var item in rawList) {
                if (item['mapValue'] != null &&
                    item['mapValue']['fields'] != null) {
                  Map<String, dynamic> cleanMap = {};
                  item['mapValue']['fields'].forEach((key, val) {
                    cleanMap[key] = parseFirestoreRestValue(val);
                  });
                  parsedAgreements.add(cleanMap);
                }
              }
              if (mounted) {
                setState(() {
                  _rentedHomes = parsedAgreements;
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

  Future<void> _updateExistingDocument(Reference ref) async {
    PlatformFile? pickedFile = await _pickDocument();
    if (pickedFile != null) {
      try {
        // 1. Delete old file logic
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          await ref.delete();
        } else {
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

  Future<PlatformFile?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
      withData: true,
    );
    if (result != null) {
      return result.files.single;
    }
    return null;
  }

  Future<String?> _uploadFileToStorage(
    PlatformFile pFile,
    String storagePath,
  ) async {
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
        Uint8List? fileBytes = pFile.bytes;
        // FIX: Read bytes from path if bytes are null (Windows/Linux)
        if (fileBytes == null && pFile.path != null) {
          fileBytes = await File(pFile.path!).readAsBytes();
        }

        if (fileBytes != null) {
          String encodedPath = Uri.encodeComponent(storagePath);
          String uploadUrl =
              "$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey";

          var response = await http.post(
            Uri.parse(uploadUrl),
            body: fileBytes,
            headers: {"Content-Type": "application/octet-stream"},
          );

          if (response.statusCode == 200) {
            downloadUrl =
                "$kStorageBaseUrl/$encodedPath?alt=media&key=$kFirebaseAPIKey";
          }
        }
      }
      return downloadUrl;
    } catch (e) {
      return null;
    }
  }

  // --- NEW: Helper to pick a file for a specific row ---
  Future<void> _pickFileForField(int index) async {
    PlatformFile? picked = await _pickDocument();
    if (picked != null) {
      setState(() {
        userDocuments[index].pickedFile = picked;
      });
    }
  }

  // --- NEW: Bulk Upload Function ---
  Future<void> _uploadSelectedDocuments() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // --- FIX: Validation Phase ---
    // Iterate through all rows to check for incomplete pairs
    for (int i = 0; i < userDocuments.length; i++) {
      var doc = userDocuments[i];
      // Case 1: File picked but Document Type NOT selected
      if (doc.pickedFile != null && doc.selectedDoc == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              "Please select a document type for the file: ${doc.pickedFile!.name}",
            ),
            backgroundColor: Colors.red,
          ),
        );
        return; // Stop execution immediately
      }
      // Case 2: Document Type selected but File NOT picked
      if (doc.selectedDoc != null && doc.pickedFile == null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text("Please pick a file for ${doc.selectedDoc}"),
            backgroundColor: Colors.red,
          ),
        );
        return; // Stop execution immediately
      }
    }
    // ----------------------------

    setState(() => _isUploadingNewDocs = true);

    try {
      bool anyUploaded = false;
      for (var doc in userDocuments) {
        if (doc.selectedDoc != null && doc.pickedFile != null) {
          // Delete existing with same name (Replace logic)
          for (var existingRef in _uploadedDocs) {
            String existingName = existingRef.name;
            String existingBase = existingName.contains('.')
                ? existingName.substring(0, existingName.lastIndexOf('.'))
                : existingName;

            if (existingBase == doc.selectedDoc) {
              if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
                await existingRef.delete();
              } else {
                String encodedPath = Uri.encodeComponent(
                  (existingRef as RestReference).fullPath,
                );
                await http.delete(
                  Uri.parse(
                    '$kStorageBaseUrl/$encodedPath?key=$kFirebaseAPIKey',
                  ),
                );
              }
            }
          }

          String fileName = doc.selectedDoc!;
          String extension = doc.pickedFile!.name.split('.').last;
          if (extension.isNotEmpty && extension.length <= 4) {
            fileName += '.$extension';
          }
          String storagePath = '$uid/user_docs/$fileName';

          await _uploadFileToStorage(doc.pickedFile!, storagePath);
          anyUploaded = true;
        }
      }

      if (anyUploaded) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Documents Uploaded Successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          userDocuments = [DocumentField()]; // Reset
        });
        _fetchUploadedDocuments(); // Refresh list
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('No documents selected to upload.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error uploading: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingNewDocs = false);
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
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      userDocuments.add(DocumentField());
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.add,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Add Document",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          if (userDocuments.any((d) => d.pickedFile != null))
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isUploadingNewDocs
                                    ? null
                                    : _uploadSelectedDocuments,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                ),
                                child: _isUploadingNewDocs
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Upload Selected Documents",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
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
                                          // CHANGED: Mapped correctly to the new 'agreements' structure
                                          final String name =
                                              req['apartmentName'] ??
                                              "Rented Property";
                                          final String landlord =
                                              req['landlordName'] ??
                                              "Unknown Landlord";
                                          final String location =
                                              req['panchayat'] ??
                                              "Unknown Location";

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
                                                      location,
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Landlord: $landlord",
                                                      style: const TextStyle(
                                                        color: Colors.white70,
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

    // Filter options: Only show options not selected in OTHER rows
    final selectedInOtherRows = userDocuments
        .where((d) => d != docField && d.selectedDoc != null)
        .map((d) => d.selectedDoc!)
        .toSet();

    final availableOptions = userDocOptions
        .where((doc) => !selectedInOtherRows.contains(doc))
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

          if (docField.pickedFile != null)
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      docField.pickedFile!.name,
                      style: const TextStyle(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white54),
                    tooltip: "Clear selected file",
                    onPressed: () => setState(() => docField.pickedFile = null),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: () => _pickFileForField(index), // Picks locally only
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: const Text(
                "Pick File",
                style: TextStyle(color: Colors.white),
              ),
            ),

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
  PlatformFile? pickedFile;
  String? downloadUrl;

  DocumentField({this.selectedDoc, this.pickedFile, this.downloadUrl});
}

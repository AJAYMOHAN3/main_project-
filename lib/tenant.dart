import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'main.dart';
import 'landlord.dart';
import 'package:http/http.dart' as http; // Add http to pubspec.yaml
import 'dart:convert';

class DocumentField {
  String? selectedDoc;
  PlatformFile? pickedFile; // Changed from File? to PlatformFile?
  String? downloadUrl;

  DocumentField({this.selectedDoc, this.pickedFile, this.downloadUrl});
}

class TenantHomePage extends StatefulWidget {
  const TenantHomePage({super.key});

  @override
  TenantHomePageState createState() => TenantHomePageState();
}

class TenantHomePageState extends State<TenantHomePage> {
  int _currentIndex = 0;
  final List<int> _navigationStack = [0]; // history of visited tabs

  // The pages are initialized in initState so they can receive the custom callback
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Initialize pages, passing the custom back handler to each root tab
    _pages = [
      TenantProfilePage(
        onBack: () {
          // Custom back logic for profile page
          if (_navigationStack.length > 1) {
            _handleCustomBack();
          } else {
            // Do nothing: stay on this page instead of popping
          }
        },
      ),
      AgreementsPage2(onBack: _handleCustomBack),
      SearchPage(onBack: _handleCustomBack),
      RequestsPage2(onBack: _handleCustomBack),
      PaymentsPage2(onBack: _handleCustomBack),
      SettingsPage2(onBack: _handleCustomBack),
    ];
  }

  // Custom back logic for the top navigation bar and device back button
  void _handleCustomBack() {
    if (_navigationStack.length > 1) {
      setState(() {
        _navigationStack.removeLast();
        _currentIndex = _navigationStack.last;
      });
    } else {
      // If at the root of the tab navigation, exit the page/app shell.
      // This is what pops to the "unwanted page" if LandlordHomePage isn't the app root.
      Navigator.pop(context);
    }
  }

  // Handle device back button
  /*Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      _handleCustomBack(); // Use the custom tab history logic
      return false; // prevent default pop
    }
    return true; // allow app exit
  }*/

  // When bottom nav button is tapped
  void _onTabTapped(int index) {
    if (_currentIndex == index) return;
    setState(() {
      _currentIndex = index;
      // Add the new tab index to the history
      _navigationStack.add(index);
    });
  }

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
        backgroundColor: const Color(0xFF141E30),
        body: _pages[_currentIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
          backgroundColor: const Color(0xFF1F2C45),
          selectedItemColor: Colors.orange,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
            BottomNavigationBarItem(
              icon: Icon(Icons.description),
              label: 'Agreements',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
            BottomNavigationBarItem(
              icon: Icon(Icons.request_page),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.payments),
              label: 'Payments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- tenant PROFILE PAGE --------------------

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
// ================= HELPER FUNCTIONS & CLASSES =================
// Place this code at the very bottom of your file, outside the class.

/// Helper to parse Firestore REST values to Dart primitives
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

// ----------------- HOME RENTAL MODEL -----------------
class HomeRental {
  final String name;
  final String address;
  HomeRental({required this.name, required this.address});
}

class AnimatedGradientBackground extends StatefulWidget {
  const AnimatedGradientBackground({super.key});

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  final int _numberOfStars = 80; // More stars for better visibility
  late List<_TwinkleStar> _stars;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Speed of one full twinkle cycle
    )..repeat();

    // Generate stars once
    _stars = List.generate(
      _numberOfStars,
      (_) => _TwinkleStar(
        position: Offset(_random.nextDouble(), _random.nextDouble()),
        size: _random.nextDouble() * 2.0 + 0.5,
        blinkOffset:
            _random.nextDouble() *
            pi *
            2, // Random starting point in the blink cycle
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Ensure there is a dark background color
      color: const Color(0xFF0A0E1A),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _TwinklePainter(
              stars: _stars,
              animationValue: _controller.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _TwinkleStar {
  final Offset position;
  final double size;
  final double blinkOffset;

  _TwinkleStar({
    required this.position,
    required this.size,
    required this.blinkOffset,
  });
}

class _TwinklePainter extends CustomPainter {
  final List<_TwinkleStar> stars;
  final double animationValue;

  _TwinklePainter({required this.stars, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = Colors.white;

    for (var star in stars) {
      // Create a smooth pulsing effect using Sine
      // We add the blinkOffset so they don't pulse at the exact same time
      double opacity =
          (sin((animationValue * pi * 2) + star.blinkOffset) + 1) / 2;

      // Keep opacity between 0.15 (dim) and 0.9 (bright)
      opacity = 0.15 + (opacity * 0.75);

      paint.color = Colors.white.withValues(alpha: opacity);

      // Convert relative 0.0-1.0 coordinates to actual pixel coordinates
      final Offset drawPosition = Offset(
        star.position.dx * size.width,
        star.position.dy * size.height,
      );

      canvas.drawCircle(drawPosition, star.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter oldDelegate) => true;
}

class RequestsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage2({super.key, required this.onBack});

  @override
  State<RequestsPage2> createState() => _RequestsPageState2();
}

class _RequestsPageState2 extends State<RequestsPage2> {
  final String currentUserId = uid;

  // Helper to determine platform
  bool get useNativeSdk => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // --- REST API: Fetch Requests ---
  Future<List<dynamic>> _fetchRequestsRest() async {
    if (currentUserId.isEmpty) return [];
    try {
      final url = Uri.parse(
        '$kFirestoreBaseUrl/trequests/$currentUserId?key=$kFirebaseAPIKey',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Parse the Firestore JSON structure
        if (data['fields'] != null && data['fields']['requests'] != null) {
          // 'requests' is an arrayValue
          var rawList =
              data['fields']['requests']['arrayValue']['values'] as List?;
          if (rawList != null) {
            // Convert using the helper
            return rawList.map((v) => _parseFirestoreRestValues(v)).toList();
          }
        }
      }
      return [];
    } catch (e) {
      // print("REST Fetch Error: $e");
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(), // Assuming this widget exists globally
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Requests",
                  onBack: widget.onBack,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 10.0),
                  child: Center(
                    child: Text(
                      "My Requests",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: currentUserId.isEmpty
                      ? const Center(
                          child: Text("Please login to view requests"),
                        )
                      : useNativeSdk
                      // --- MOBILE: USE SDK (STREAM) ---
                      ? StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('trequests')
                              .doc(currentUserId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return _buildEmptyState();
                            }
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            final List<dynamic> requests =
                                data['requests'] ?? [];
                            return _buildRequestsList(requests);
                          },
                        )
                      // --- WEB/DESKTOP: USE HTTP (FUTURE) ---
                      : FutureBuilder<List<dynamic>>(
                          future: _fetchRequestsRest(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return _buildEmptyState();
                            }
                            return _buildRequestsList(snapshot.data!);
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

  Widget _buildEmptyState() {
    return const Center(
      child: Text(
        "No requests sent yet.",
        style: TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildRequestsList(List<dynamic> requests) {
    if (requests.isEmpty) return _buildEmptyState();

    return ListView.builder(
      itemCount: requests.length,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemBuilder: (context, index) {
        final reqData = requests[index] as Map<String, dynamic>;

        final String landlordUid = reqData['luid'] ?? '';
        final String status = reqData['status'] ?? 'pending';

        int propertyIndex = 0;
        if (reqData['propertyIndex'] is int) {
          propertyIndex = reqData['propertyIndex'];
        } else if (reqData['propertyIndex'] is String) {
          propertyIndex = int.tryParse(reqData['propertyIndex']) ?? 0;
        }

        return _RequestCard(
          landlordUid: landlordUid,
          propertyIndex: propertyIndex,
          status: status,
          useNativeSdk: useNativeSdk, // Pass platform flag
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper Widget: Fetches Property Data
// ---------------------------------------------------------------------------
class _RequestCard extends StatelessWidget {
  final String landlordUid;
  final int propertyIndex;
  final String status;
  final bool useNativeSdk;

  const _RequestCard({
    required this.landlordUid,
    required this.propertyIndex,
    required this.status,
    required this.useNativeSdk,
  });

  // --- Logic to Fetch House Data (Hybrid: SDK or REST) ---
  Future<Map<String, dynamic>?> _fetchHouseData() async {
    if (useNativeSdk) {
      // SDK Logic
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('house')
            .doc(landlordUid)
            .get();
        if (doc.exists) {
          return doc.data() as Map<String, dynamic>;
        }
      } catch (e) {
        return null;
      }
    } else {
      // REST Logic
      try {
        final url = Uri.parse(
          '$kFirestoreBaseUrl/house/$landlordUid?key=$kFirebaseAPIKey',
        );
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['fields'] != null) {
            // Convert the entire document fields to a clean Map
            Map<String, dynamic> cleanData = {};
            data['fields'].forEach((key, val) {
              cleanData[key] = _parseFirestoreRestValues(val);
            });
            return cleanData;
          }
        }
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    String displayStatus = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'accepted':
      case 'approved':
        statusColor = Colors.lightGreenAccent;
        break;
      case 'rejected':
      case 'declined':
        statusColor = Colors.redAccent;
        break;
      default:
        statusColor = Colors.amberAccent;
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchHouseData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            color: Colors.white.withValues(alpha: 0.1),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const SizedBox(
              height: 100,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox(); // Hide if house not found
        }

        final houseData = snapshot.data!;
        final List<dynamic> properties = houseData['properties'] ?? [];

        if (propertyIndex >= properties.length) {
          return const SizedBox();
        }

        final property = properties[propertyIndex];
        // Note: For REST, 'property' is already parsed into a Map by _parseFirestoreRestValue

        final String location = property['location'] ?? 'Unknown Location';
        final String rent = property['rent'].toString();
        final String roomType = property['apartmentName'] ?? "My Apartment";

        String imageUrl = '';
        if (property['houseImageUrls'] != null &&
            (property['houseImageUrls'] as List).isNotEmpty) {
          imageUrl = property['houseImageUrls'][0];
        }

        return Card(
          color: Colors.white.withValues(alpha: 0.1),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  color: Colors.black26,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.broken_image,
                                color: Colors.white54,
                              ),
                        )
                      : const Icon(Icons.home, color: Colors.white54),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Rent: ₹$rent",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Status: $displayStatus",
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Helper Function: Parse Firestore REST JSON
// ---------------------------------------------------------------------------
dynamic _parseFirestoreRestValues(Map<String, dynamic> valueMap) {
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
    return values.map((v) => _parseFirestoreRestValues(v)).toList();
  }

  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    Map<String, dynamic> result = {};
    fields.forEach((key, val) {
      result[key] = _parseFirestoreRestValues(val);
    });
    return result;
  }
  return null;
}

// -------------------- SEARCH PAGE --------------------
class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});

  @override
  SearchPageState createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  // Markers logic kept as requested
  final Set<Marker> _markers = {};

  final TextEditingController _searchController = TextEditingController();

  final Map<String, TextEditingController> _filterControllers = {
    "Price": TextEditingController(),
    "People": TextEditingController(),
  };

  String? _activeFilter;
  bool _showResults = false;
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];

  final Map<String, List<String>> filterSuggestions = {
    "Price": [
      "Below ₹5000",
      "₹5000 - ₹10000",
      "₹10000 - ₹20000",
      "Above ₹20000",
    ],
    "People": ["1 person", "2 people", "3 people", "4+ people"],
  };

  // --- Search Function (Updated for Multi-Platform) ---
  Future<void> _performSearch() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _showResults = true;
      _searchResults = [];
    });

    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
        _filterControllers["People"]!.text.isNotEmpty;

    final String searchTerm = isFilterActive
        ? ""
        : _searchController.text.trim().toLowerCase();

    final String priceFilter = _filterControllers["Price"]!.text.trim();
    final String peopleFilter = _filterControllers["People"]!.text.trim();

    List<Map<String, dynamic>> results = [];

    try {
      // 1. SDK LOGIC (Android/iOS)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        QuerySnapshot houseSnapshot = await FirebaseFirestore.instance
            .collection('house')
            .get();

        for (var doc in houseSnapshot.docs) {
          String landlordUid = doc.id;
          var houseData = doc.data() as Map<String, dynamic>?;

          if (houseData != null &&
              houseData.containsKey('properties') &&
              houseData['properties'] is List) {
            List<dynamic> properties = houseData['properties'];
            _filterAndAddProperties(
              properties,
              landlordUid,
              searchTerm,
              priceFilter,
              peopleFilter,
              results,
            );
          }
        }
      }
      // 2. REST LOGIC (Web/Windows/macOS/Linux)
      else {
        final url = Uri.parse('$kFirestoreBaseUrl/house?key=$kFirebaseAPIKey');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['documents'] != null) {
            for (var doc in data['documents']) {
              // Extract ID from name "projects/.../databases/.../documents/house/UID"
              String landlordUid = doc['name'].split('/').last;

              if (doc['fields'] != null &&
                  doc['fields']['properties'] != null &&
                  doc['fields']['properties']['arrayValue'] != null) {
                var values =
                    doc['fields']['properties']['arrayValue']['values']
                        as List?;
                if (values != null) {
                  // Convert Firestore JSON to Dart Map
                  List<dynamic> properties = values.map((v) {
                    if (v['mapValue'] != null &&
                        v['mapValue']['fields'] != null) {
                      Map<String, dynamic> cleanMap = {};
                      v['mapValue']['fields'].forEach((key, val) {
                        cleanMap[key] = _parseFirestoreRestValue(val);
                      });
                      return cleanMap;
                    }
                    return {};
                  }).toList();

                  _filterAndAddProperties(
                    properties,
                    landlordUid,
                    searchTerm,
                    priceFilter,
                    peopleFilter,
                    results,
                  );
                }
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;

          _markers.clear();
          for (var result in _searchResults) {
            var property = result['propertyDetails'];
            double lat =
                double.tryParse(property['latitude'].toString()) ?? 10.0;
            double lng =
                double.tryParse(property['longitude'].toString()) ?? 76.0;

            _markers.add(
              Marker(
                point: LatLng(lat, lng),
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () {},
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.orange,
                    size: 36,
                  ),
                ),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching houses: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Helper to reduce code duplication between SDK and REST loops ---
  void _filterAndAddProperties(
    List<dynamic> properties,
    String landlordUid,
    String searchTerm,
    String priceFilter,
    String peopleFilter,
    List<Map<String, dynamic>> results,
  ) {
    for (int i = 0; i < properties.length; i++) {
      var property = properties[i];
      if (property is Map<String, dynamic>) {
        String location = (property['location'] as String? ?? '').toLowerCase();
        String rentStr = property['rent'] as String? ?? '';
        String occupancyStr = property['maxOccupancy'] as String? ?? '';
        String roomType = property['roomType'] as String? ?? '';

        bool priceMatch =
            priceFilter.isEmpty || _checkPriceMatch(rentStr, priceFilter);
        bool peopleMatch =
            peopleFilter.isEmpty ||
            _checkOccupancyMatch(occupancyStr, peopleFilter);

        bool searchMatch =
            searchTerm.isEmpty ||
            location.contains(searchTerm) ||
            roomType.toLowerCase().contains(searchTerm) ||
            rentStr.contains(searchTerm) ||
            occupancyStr.toLowerCase().contains(searchTerm);

        if (priceMatch && peopleMatch && searchMatch) {
          results.add({
            'landlordUid': landlordUid,
            'propertyIndex': i,
            'displayInfo':
                '${roomType.isNotEmpty ? roomType : "Property"} - ${property['location'] ?? 'Unknown Location'}',
            'propertyDetails': property,
          });
        }
      }
    }
  }

  bool _checkPriceMatch(String rentStr, String priceFilter) {
    int? rent = int.tryParse(rentStr.replaceAll(RegExp(r'[^0-9]'), '').trim());
    if (rent == null) return false;

    switch (priceFilter) {
      case "Below ₹5000":
        return rent < 5000;
      case "₹5000 - ₹10000":
        return rent >= 5000 && rent <= 10000;
      case "₹10000 - ₹20000":
        return rent > 10000 && rent <= 20000;
      case "Above ₹20000":
        return rent > 20000;
      default:
        return true;
    }
  }

  bool _checkOccupancyMatch(String occupancyStr, String peopleFilter) {
    int? occupancy = int.tryParse(
      occupancyStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    );
    if (occupancy == null) return false;

    switch (peopleFilter) {
      case "1 person":
        return occupancy >= 1;
      case "2 people":
        return occupancy >= 2;
      case "3 people":
        return occupancy >= 3;
      case "4+ people":
        return occupancy >= 4;
      default:
        return true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterControllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
        _filterControllers["People"]!.text.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                // --- TOP SEARCH/FILTER AREA ---
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomTopNavBar(
                        showBack: true,
                        title: 'Search',
                        onBack: widget.onBack,
                      ),
                      const SizedBox(height: 10),

                      Center(
                        child: Text(
                          "SEARCH HOMES",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Filter buttons
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ["Price", "People"].map((filter) {
                            bool isActive = _activeFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ElevatedButton.icon(
                                icon: Icon(
                                  Icons.filter_alt,
                                  color: isActive ? Colors.black : Colors.white,
                                  size: 18,
                                ),
                                label: Text(
                                  filter,
                                  style: TextStyle(
                                    color: isActive
                                        ? Colors.black
                                        : Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? Colors.orange.shade300
                                      : Colors.white.withValues(alpha: 0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _activeFilter = isActive ? null : filter;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      // Active filter input
                      if (_activeFilter != null)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: _filterControllers[_activeFilter!],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText:
                                      "Enter ${_activeFilter!.toLowerCase()}...",
                                  hintStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onSubmitted: (_) => _performSearch(),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: filterSuggestions[_activeFilter!]!
                                    .map(
                                      (option) => ChoiceChip(
                                        label: Text(option),
                                        labelStyle: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.1),
                                        selectedColor: Colors.orange.shade700,
                                        selected:
                                            _filterControllers[_activeFilter!]!
                                                .text ==
                                            option,
                                        onSelected: (selected) {
                                          setState(() {
                                            _filterControllers[_activeFilter!]!
                                                .text = selected
                                                ? option
                                                : '';
                                            _activeFilter = null;
                                          });
                                          _performSearch();
                                        },
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Search bar
                      if (!isFilterActive)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: "Search homes, location, type...",
                                  hintStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => _performSearch(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _performSearch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Icon(
                                Icons.search,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                // --- RESULTS LIST AREA ---
                if (_showResults)
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.orange,
                            ),
                          )
                        : (_searchResults.isEmpty
                              ? const Center(
                                  child: Text(
                                    "No homes found matching your criteria.",
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  itemCount: _searchResults.length,
                                  itemBuilder: (context, index) {
                                    final result = _searchResults[index];
                                    final property = result['propertyDetails'];

                                    // Fetch first image from houseImageUrls
                                    String? imageUrl;
                                    if (property['houseImageUrls'] != null &&
                                        property['houseImageUrls'] is List &&
                                        (property['houseImageUrls'] as List)
                                            .isNotEmpty) {
                                      imageUrl = property['houseImageUrls'][0];
                                    }

                                    final String location =
                                        property['location'] ?? 'Unknown';
                                    final String rent =
                                        property['rent'] ?? 'N/A';
                                    final String roomType =
                                        property['roomType'] ?? 'Room';

                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                LandlordsearchProfilePage(
                                                  landlordUid:
                                                      result['landlordUid'],
                                                  propertyDetails:
                                                      result['propertyDetails'],
                                                  propertyIndex:
                                                      result['propertyIndex'],
                                                ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // --- 1. IMAGE PREVIEW ---
                                            ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.only(
                                                    topLeft: Radius.circular(
                                                      15,
                                                    ),
                                                    bottomLeft: Radius.circular(
                                                      15,
                                                    ),
                                                  ),
                                              child: SizedBox(
                                                width: 120,
                                                height: 110,
                                                child: imageUrl != null
                                                    ? Image.network(
                                                        imageUrl,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (
                                                              ctx,
                                                              err,
                                                              stack,
                                                            ) => Container(
                                                              color: Colors
                                                                  .grey[800],
                                                              child: const Icon(
                                                                Icons
                                                                    .broken_image,
                                                                color: Colors
                                                                    .white54,
                                                              ),
                                                            ),
                                                      )
                                                    : Container(
                                                        color: Colors.grey[800],
                                                        child: const Icon(
                                                          Icons.home,
                                                          color: Colors.white54,
                                                          size: 40,
                                                        ),
                                                      ),
                                              ),
                                            ),

                                            // --- 2. DETAILS ---
                                            Expanded(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12.0,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      roomType,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.location_on,
                                                          size: 14,
                                                          color: Colors.white70,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            location,
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 14,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      "₹$rent/mo",
                                                      style: const TextStyle(
                                                        color:
                                                            Colors.orangeAccent,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),

                                            // Chevron
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                right: 12.0,
                                              ),
                                              child: Icon(
                                                Icons.arrow_forward_ios,
                                                color: Colors.white30,
                                                size: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                )),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage2({super.key, required this.onBack});

  // Helper to check platform
  static bool get useNativeSdk =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> settingsOptions = [
      {
        'title': 'Edit Profile',
        'icon': Icons.person_outline,
        'color': Colors.blue,
        'action': (BuildContext context) => _showEditProfileDialog(context),
      },
      {
        'title': 'Change Password',
        'icon': Icons.lock_outline,
        'color': Colors.orange,
        'action': (BuildContext context) => _showChangePasswordDialog(context),
      },
      {
        'title': 'Notification ',
        'icon': Icons.notifications_none,
        'color': Colors.green,
        'action': (BuildContext context) {},
      },
      {
        'title': 'View My Profile',
        'icon': Icons.person, // suitable profile icon
        'color': Colors.purple,
        'action': (BuildContext context) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TenantsearchProfilePage2(
                onBack: () => Navigator.pop(context),
              ),
            ),
          );
        },
      },
      {
        'title': 'Help & Support',
        'icon': Icons.help_outline,
        'color': Colors.yellow.shade700,
        'action': (BuildContext context) => _showHelpDialog(context),
      },
    ];

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Settings",
                  onBack: onBack,
                ),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Account Settings",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ...settingsOptions.map((option) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassmorphismContainer(
                              borderRadius: 15,
                              opacity: 0.08,
                              onTap: () => option['action'](context),
                              child: Row(
                                children: [
                                  Icon(
                                    option['icon'],
                                    color: option['color'],
                                    size: 30,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option['title'],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white54,
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 30),
                        // -------------------- LOGOUT BUTTON --------------------
                        GlassmorphismContainer(
                          borderRadius: 15,
                          opacity: 0.08,
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) =>
                                  AlertDialog(
                                    backgroundColor: const Color(0xFF1E2A47),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    title: const Text(
                                      "Confirm Logout",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    content: const Text(
                                      "Are you sure you want to logout?",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text(
                                          "Cancel",
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                        ),
                                        onPressed: () async {
                                          await FirebaseAuth.instance.signOut();
                                          if (!context.mounted) {
                                            return;
                                          }
                                          Navigator.pop(dialogContext);
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const LoginPage(),
                                            ),
                                          );
                                        },
                                        child: const Text(
                                          "Logout",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.logout,
                                color: Colors.redAccent,
                                size: 30,
                              ),
                              SizedBox(width: 15),
                              Text(
                                'LOGOUT',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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

  // ---------------------- HELP & SUPPORT DIALOG ----------------------
  static void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          "Help & Support",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Contact Admin:\n\n📞 +91 9497320928 \n\n📞 +91 8281258530",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Close",
              style: TextStyle(color: Colors.blueAccent),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------- EDIT PROFILE DIALOG ----------------------
  static void _showEditProfileDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController = TextEditingController();
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController aadharController = TextEditingController();

    XFile? pickedImageFile;
    XFile? pickedSignFile;
    bool isUpdating = false;
    bool isFetching = true;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent close while loading
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          // --- PRE-FETCH DATA ---
          if (isFetching) {
            //final String? uid = FirebaseAuth.instance.currentUser?.uid;
            Future.delayed(Duration.zero, () async {
              try {
                Map<String, dynamic>? data;

                if (useNativeSdk) {
                  // SDK
                  DocumentSnapshot doc = await FirebaseFirestore.instance
                      .collection('tenant')
                      .doc(uid)
                      .get();
                  if (doc.exists) {
                    data = doc.data() as Map<String, dynamic>;
                  }
                } else {
                  // REST
                  final url = Uri.parse(
                    '$kFirestoreBaseUrl/tenant/$uid?key=$kFirebaseAPIKey',
                  );
                  final response = await http.get(url);
                  if (response.statusCode == 200) {
                    final jsonData = jsonDecode(response.body);
                    if (jsonData['fields'] != null) {
                      data = {};
                      jsonData['fields'].forEach((key, val) {
                        data![key] = _settingsParseFirestoreValue(val);
                      });
                    }
                  }
                }

                if (data != null) {
                  nameController.text = data['fullName'] ?? '';
                  idController.text = data['profileName'] ?? '';
                  phoneController.text = data['phoneNumber'] ?? '';
                  aadharController.text = data['aadharNumber'] ?? '';
                }
              } catch (e) {
                // Ignore errors during fetch
              } finally {
                stfSetState(() => isFetching = false);
              }
            });
          }

          if (isFetching) {
            return const Center(child: CircularProgressIndicator());
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              "Edit Profile",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      if (isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            pickedImageFile = image;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick image'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade700,
                      backgroundImage: pickedImageFile != null
                          ? (kIsWeb
                                ? NetworkImage(pickedImageFile!.path)
                                : FileImage(File(pickedImageFile!.path))
                                      as ImageProvider)
                          : const AssetImage('assets/profile_placeholder.png')
                                as ImageProvider,
                      child: const Align(
                        alignment: Alignment.bottomRight,
                        child: CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          radius: 14,
                          child: Icon(
                            Icons.edit,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildInputField(nameController, "Full Name"),
                  _buildInputField(idController, "User ID"),
                  _buildInputField(phoneController, "Phone Number"),
                  _buildInputField(aadharController, "Aadhar Number"),
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: () async {
                      if (isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            pickedSignFile = image;
                          });
                        }
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick signature'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade600),
                      ),
                      child: pickedSignFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: kIsWeb
                                  ? Image.network(
                                      pickedSignFile!.path,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(pickedSignFile!.path),
                                      fit: BoxFit.cover,
                                    ),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.draw, color: Colors.white54),
                                  SizedBox(height: 5),
                                  Text(
                                    "Tap to upload Signature",
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: isUpdating
                    ? null
                    : () async {
                        final String aadhar = aadharController.text.trim();
                        if (aadhar.isNotEmpty && aadhar.length != 12) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Aadhar Number must be exactly 12 digits',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        stfSetState(() => isUpdating = true);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);
                        final String? uid =
                            FirebaseAuth.instance.currentUser?.uid;

                        if (uid == null) return;

                        try {
                          // 1. Upload Profile Image
                          if (pickedImageFile != null) {
                            String filePath =
                                '$uid/profile_pic/profile_image.jpg';
                            await _settingsUploadFile(
                              pickedImageFile!,
                              filePath,
                            );
                          }

                          // 2. Upload Signature
                          if (pickedSignFile != null) {
                            String signPath = '$uid/sign/sign.jpg';
                            await _settingsUploadFile(
                              pickedSignFile!,
                              signPath,
                            );
                          }

                          // 3. Update Firestore
                          Map<String, dynamic> updateData = {};
                          final String newFullName = nameController.text.trim();
                          final String newProfileName = idController.text
                              .trim();
                          final String newPhoneNumber = phoneController.text
                              .trim();

                          if (newFullName.isNotEmpty) {
                            updateData['fullName'] = newFullName;
                          }
                          if (newProfileName.isNotEmpty) {
                            updateData['profileName'] = newProfileName;
                          }
                          if (newPhoneNumber.isNotEmpty) {
                            updateData['phoneNumber'] = newPhoneNumber;
                          }
                          if (aadhar.isNotEmpty) {
                            updateData['aadharNumber'] = aadhar;
                          }

                          if (updateData.isNotEmpty) {
                            if (useNativeSdk) {
                              // SDK Update
                              await FirebaseFirestore.instance
                                  .collection('tenant')
                                  .doc(uid)
                                  .update(updateData);

                              // Check/Add UserIds
                              if (newProfileName.isNotEmpty) {
                                final checkSnap = await FirebaseFirestore
                                    .instance
                                    .collection('UserIds')
                                    .where('UserId', isEqualTo: newProfileName)
                                    .limit(1)
                                    .get();
                                if (checkSnap.docs.isEmpty) {
                                  await FirebaseFirestore.instance
                                      .collection('UserIds')
                                      .add({'UserId': newProfileName});
                                }
                              }
                            } else {
                              // REST Update
                              Map<String, dynamic> fields = {};
                              updateData.forEach((key, value) {
                                fields[key] = {"stringValue": value};
                              });
                              String updateMask = updateData.keys
                                  .map((k) => "updateMask.fieldPaths=$k")
                                  .join("&");

                              final tUrl = Uri.parse(
                                '$kFirestoreBaseUrl/tenant/$uid?$updateMask&key=$kFirebaseAPIKey',
                              );
                              await http.patch(
                                tUrl,
                                body: jsonEncode({"fields": fields}),
                                headers: {"Content-Type": "application/json"},
                              );

                              // REST UserIds Check/Add
                              if (newProfileName.isNotEmpty) {
                                // Simplified: Just try adding (real check requires complex query syntax)
                                final addUrl = Uri.parse(
                                  '$kFirestoreBaseUrl/UserIds?key=$kFirebaseAPIKey',
                                );
                                await http.post(
                                  addUrl,
                                  body: jsonEncode({
                                    "fields": {
                                      "UserId": {"stringValue": newProfileName},
                                    },
                                  }),
                                  headers: {"Content-Type": "application/json"},
                                );
                              }
                            }
                          }

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop();
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Update failed: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() => isUpdating = false);
                          }
                        }
                      },
                child: isUpdating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Update",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------- CHANGE PASSWORD DIALOG ----------------------
  static void _showChangePasswordDialog(BuildContext context) {
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    bool isChangingPassword = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              "Change Password",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInputField(
                    newPassController,
                    "New Password",
                    isPassword: true,
                  ),
                  _buildInputField(
                    confirmPassController,
                    "Confirm Password",
                    isPassword: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: isChangingPassword
                    ? null
                    : () async {
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);
                        final String newPassword = newPassController.text;
                        final String confirmPassword =
                            confirmPassController.text;

                        if (newPassword.isEmpty || confirmPassword.isEmpty) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Please fill both fields'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (newPassword != confirmPassword) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Passwords do not match'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (newPassword.length < 6) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Password too short (min 6)'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        User? user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        stfSetState(() => isChangingPassword = true);

                        try {
                          if (useNativeSdk) {
                            // SDK Logic
                            await user.updatePassword(newPassword);
                          } else {
                            // REST Logic (Identity Toolkit)
                            String? token = await user.getIdToken();
                            if (token == null) throw "Token missing";

                            final url = Uri.parse(
                              'https://identitytoolkit.googleapis.com/v1/accounts:update?key=$kFirebaseAPIKey',
                            );
                            final response = await http.post(
                              url,
                              body: jsonEncode({
                                "idToken": token,
                                "password": newPassword,
                                "returnSecureToken": true,
                              }),
                              headers: {"Content-Type": "application/json"},
                            );

                            if (response.statusCode != 200) {
                              throw "API Error: ${response.body}";
                            }
                          }

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop();
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() => isChangingPassword = false);
                          }
                        }
                      },
                child: isChangingPassword
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "Update",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- HELPER: Build Input Field ---
  static Widget _buildInputField(
    TextEditingController controller,
    String hint, {
    bool isPassword = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // --- HELPER: Upload File (SDK vs HTTP) ---
  static Future<void> _settingsUploadFile(
    XFile file,
    String storagePath,
  ) async {
    if (useNativeSdk) {
      // SDK
      await FirebaseStorage.instance.ref(storagePath).putFile(File(file.path));
    } else {
      // REST
      final bytes = await file.readAsBytes();
      String encodedPath = Uri.encodeComponent(storagePath);
      final uploadUrl = Uri.parse(
        '$kStorageBaseUrl?name=$encodedPath&uploadType=media&key=$kFirebaseAPIKey',
      );

      final response = await http.post(
        uploadUrl,
        headers: {
          "Content-Type": "application/octet-stream",
          "Content-Length": bytes.length.toString(),
        },
        body: bytes,
      );

      if (response.statusCode != 200) {
        throw "Upload failed: ${response.body}";
      }
    }
  }

  // --- HELPER: Parse Firestore Value (Unique name) ---
  static dynamic _settingsParseFirestoreValue(Map<String, dynamic> valueMap) {
    if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
    if (valueMap.containsKey('integerValue')) {
      return int.tryParse(valueMap['integerValue'] ?? '0');
    }
    if (valueMap.containsKey('doubleValue')) {
      return double.tryParse(valueMap['doubleValue'] ?? '0.0');
    }
    if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];
    return null;
  }
}

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

// -------------------- PAYMENTS PAGE --------------------
class PaymentsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage2({super.key, required this.onBack});

  @override
  State<PaymentsPage2> createState() => _PaymentsPage2State();
}

class _PaymentsPage2State extends State<PaymentsPage2> {
  String? selectedMethod;
  final TextEditingController _amountController = TextEditingController();

  // Mock transactions
  final List<Map<String, dynamic>> mockTransactions = [
    {
      'amount': 499,
      'method': 'UPI',
      'date': '18 Oct 2025, 10:45 AM',
      'status': 'Success',
    },
    {
      'amount': 799,
      'method': 'Credit Card',
      'date': '15 Oct 2025, 2:22 PM',
      'status': 'Pending',
    },
    {
      'amount': 299,
      'method': 'Net Banking',
      'date': '10 Oct 2025, 9:10 PM',
      'status': 'Success',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---------- TOP NAV BAR ----------
                CustomTopNavBar(
                  showBack: true,
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                // ---------- SCROLLABLE CONTENT ----------
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Make a Payment",
                                  style: TextStyle(
                                    color: Colors.orange.shade300,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Choose your payment method (India):",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Payment method buttons
                                Wrap(
                                  spacing: 10,
                                  children: [
                                    _paymentButton(
                                      "UPI",
                                      Icons.account_balance_wallet,
                                    ),
                                    _paymentButton(
                                      "Credit/Debit Card",
                                      Icons.credit_card,
                                    ),
                                    _paymentButton(
                                      "Net Banking",
                                      Icons.account_balance,
                                    ),
                                    _paymentButton("Wallets", Icons.wallet),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Dynamic payment fields
                                if (selectedMethod != null)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    child: _buildPaymentFields(selectedMethod!),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),
                        // -------------------- TRANSACTION HISTORY --------------------
                        Text(
                          "Transaction History",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: mockTransactions.length,
                          itemBuilder: (context, index) {
                            var data = mockTransactions[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10,
                                  sigmaY: 10,
                                ),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.receipt_long,
                                      color: Colors.orange.shade400,
                                    ),
                                    title: Text(
                                      "₹${data['amount']} - ${data['method']}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    subtitle: Text(
                                      data['date'],
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                    trailing: Text(
                                      data['status'],
                                      style: TextStyle(
                                        color: data['status'] == "Success"
                                            ? Colors.greenAccent
                                            : Colors.orangeAccent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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
    );
  }

  // -------------------- PAYMENT BUTTON --------------------
  Widget _paymentButton(String title, IconData icon) {
    final bool isSelected = selectedMethod == title;
    return ElevatedButton.icon(
      onPressed: () => setState(() => selectedMethod = title),
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(title, style: const TextStyle(color: Colors.white)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected
            ? Colors.orange.shade700
            : Colors.white.withValues(alpha: 0.1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // -------------------- PAYMENT FIELDS --------------------
  Widget _buildPaymentFields(String method) {
    switch (method) {
      case "UPI":
        return Column(
          key: const ValueKey("UPI"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Enter UPI ID (e.g. name@okaxis)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Credit/Debit Card":
        return Column(
          key: const ValueKey("Card"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Card Number"),
            const SizedBox(height: 10),
            _textField("Card Holder Name"),
            const SizedBox(height: 10),
            _textField("Expiry (MM/YY)"),
            const SizedBox(height: 10),
            _textField("CVV", obscure: true),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Net Banking":
        return Column(
          key: const ValueKey("NetBanking"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Bank Name"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      case "Wallets":
        return Column(
          key: const ValueKey("Wallets"),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textField("Wallet Name (Paytm, PhonePe, etc.)"),
            const SizedBox(height: 10),
            _amountField(),
            _proceedButton(),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // -------------------- SHARED INPUTS --------------------
  Widget _textField(String hint, {bool obscure = false}) {
    return TextField(
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  Widget _amountField() {
    return TextField(
      controller: _amountController,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Enter Amount (₹)",
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
      ),
    );
  }

  Widget _proceedButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: ElevatedButton(
        onPressed: () {
          String amount = _amountController.text.trim();
          if (amount.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please enter an amount")),
            );
            return;
          }

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E2A47),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Payment of ₹$amount initiated via $selectedMethod",
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    "Confirm",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Center(
          child: Text(
            "Proceed to Pay",
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class TenantsearchProfilePage extends StatelessWidget {
  final String tenantName;
  final String propertyName;
  final VoidCallback onBack;

  const TenantsearchProfilePage({
    super.key,
    required this.tenantName,
    required this.propertyName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final dummyReviews = [
      {"reviewer": "Landlord A", "comment": "Great tenant, pays on time!"},
      {"reviewer": "Landlord B", "comment": "Clean and respectful."},
    ];

    final tenantRequirements = [
      "1 BHK apartment",
      "Budget: \$1200/month",
      "Prefers furnished",
      "Pet-friendly",
    ];

    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Tenant Profile",
                    onBack: onBack,
                  ),
                  const SizedBox(height: 16),

                  // Tenant Avatar + Info
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white24,
                    child: Text(
                      tenantName[0],
                      style: const TextStyle(fontSize: 40, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tenantName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Interested in $propertyName",
                    style: const TextStyle(color: Colors.white70),
                  ),

                  const SizedBox(height: 20),

                  // Requirements Section
                  const Text(
                    "Requirements",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...tenantRequirements.map(
                    (req) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        req,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Reviews Section
                  const Text(
                    "Reviews",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...dummyReviews.map(
                    (r) => Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        title: Text(
                          r["reviewer"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          r["comment"]!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Review Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    onPressed: () {},
                    child: const Text("Review"),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

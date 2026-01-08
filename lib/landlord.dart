import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'tenant.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

// Renamed from PropertyCard as requested
class LandlordPropertyForm {
  final TextEditingController apartmentNameController = TextEditingController();
  final TextEditingController roomTypeController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController rentController = TextEditingController();
  final TextEditingController maxOccupancyController = TextEditingController();

  // --- NEW: Added 4 Controllers ---
  final TextEditingController panchayatNameController = TextEditingController();
  final TextEditingController blockNoController = TextEditingController();
  final TextEditingController thandaperNoController = TextEditingController();
  final TextEditingController securityAmountController =
      TextEditingController();
  // -------------------------------

  List<DocumentField> documents;
  List<XFile> houseImages = [];

  LandlordPropertyForm({required this.documents});

  void dispose() {
    apartmentNameController.dispose();
    roomTypeController.dispose();
    locationController.dispose();
    rentController.dispose();
    maxOccupancyController.dispose();
    // Dispose new controllers
    panchayatNameController.dispose();
    blockNoController.dispose();
    thandaperNoController.dispose();
    securityAmountController.dispose();
  }
}

class LandlordProfilePage extends StatefulWidget {
  final VoidCallback onBack;

  const LandlordProfilePage({super.key, required this.onBack});

  @override
  _LandlordProfilePageState createState() => _LandlordProfilePageState();
}

class _LandlordProfilePageState extends State<LandlordProfilePage>
    with SingleTickerProviderStateMixin {
  // --- State variables ---
  late TabController _tabController;

  // Tab 1: User Docs
  List<DocumentField> newUserDocuments = [DocumentField()];
  List<Reference> _fetchedUserDocs = [];
  bool _isLoadingDocs = true;

  // Tab 2: Add Property
  List<LandlordPropertyForm> propertyCards = [
    LandlordPropertyForm(documents: [DocumentField()]),
  ];
  bool _isUploading = false;

  // Tab 3: My Apartments
  List<Map<String, dynamic>> _myApartments = [];
  bool _isLoadingApartments = true;

  String? _landlordName;
  String? _profilePicUrl;

  final List<String> userDocOptions = [
    "Aadhar",
    "PAN",
    "License",
    "Birth Certificate",
  ];
  final List<String> propertyDocOptions = [
    "Property Tax Receipt",
    "Land Ownership Proof",
    "Electricity Bill",
    "Water Bill",
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchLandlordData();
    _fetchUserDocs();
    _fetchMyApartments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var card in propertyCards) {
      card.dispose();
    }
    super.dispose();
  }

  // ================= 1. DATA FETCHING =================

  Future<void> _fetchLandlordData() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _landlordName = (doc.data() as Map<String, dynamic>)['fullName'];
        });
      }
      // Fetch Profile Pic
      final ref = FirebaseStorage.instance.ref('$uid/profile_pic/');
      final list = await ref.list(const ListOptions(maxResults: 1));
      if (list.items.isNotEmpty) {
        String url = await list.items.first.getDownloadURL();
        if (mounted) setState(() => _profilePicUrl = url);
      }
    } catch (e) {
      print("Profile fetch error: $e");
    }
  }

  Future<void> _fetchUserDocs() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      // List all files in the user_docs folder
      final list = await FirebaseStorage.instance
          .ref('$uid/user_docs/')
          .listAll();
      if (mounted) {
        setState(() {
          _fetchedUserDocs = list.items;
          _isLoadingDocs = false;
        });
      }
    } catch (e) {
      print("Docs fetch error: $e");
      if (mounted) setState(() => _isLoadingDocs = false);
    }
  }

  Future<void> _fetchMyApartments() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('house')
          .doc(uid)
          .get();
      if (doc.exists && mounted) {
        Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('properties')) {
          setState(() {
            _myApartments = List<Map<String, dynamic>>.from(data['properties']);
            _isLoadingApartments = false;
          });
          return;
        }
      }
      setState(() => _isLoadingApartments = false);
    } catch (e) {
      print("Apartments fetch error: $e");
      if (mounted) setState(() => _isLoadingApartments = false);
    }
  }

  // ================= 2. HELPERS (Picker, Open, Smart Upload) =================

  Future<File?> _pickDocument() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
    );
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  Future<void> _pickHouseImagesForCard(int index) async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty && mounted) {
      setState(() {
        propertyCards[index].houseImages.addAll(images);
      });
    }
  }

  /// **Smart Upload**: Prevents duplicates by checking for files with the same base name
  /// (e.g., 'Aadhar') but different extensions and deleting them before upload.
  Future<String?> _uploadFileWithReplace(
    File file,
    String folderPath,
    String fileNameWithoutExt,
  ) async {
    try {
      final folderRef = FirebaseStorage.instance.ref(folderPath);

      // 1. Check existing files to delete old versions (e.g. replacing .jpg with .pdf)
      try {
        final listResult = await folderRef.listAll();
        for (var item in listResult.items) {
          String baseName = item.name.split('.').first;
          if (baseName == fileNameWithoutExt) {
            print("Deleting old duplicate file: ${item.name}");
            await item.delete();
          }
        }
      } catch (e) {
        // Folder might not exist yet, which is fine
        print("Folder list check skipped: $e");
      }

      // 2. Upload new file
      String ext = file.path.split('.').last;
      String finalPath = '$folderPath/$fileNameWithoutExt.$ext';
      final ref = FirebaseStorage.instance.ref(finalPath);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      print("Upload error: $e");
      return null;
    }
  }

  Future<void> _openFile(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch file viewer")),
        );
      }
    } catch (e) {
      print("Error opening file: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ================= 3. LOGIC (Update, Delete, Add) =================

  // --- Logic: Get Safe Property Index ---
  // Calculates the next property number by looking at existing folder names.
  // Prevents naming collision if 'property1' exists and 'property1' (new) is tried.
  int _getNextPropertyFolderIndex() {
    int maxIndex = 0;
    for (var apt in _myApartments) {
      String folderName = apt['folderName'] ?? '';
      // Expected format "propertyX"
      if (folderName.startsWith('property')) {
        String numPart = folderName.replaceFirst('property', '');
        int? index = int.tryParse(numPart);
        if (index != null && index > maxIndex) {
          maxIndex = index;
        }
      }
    }
    return maxIndex + 1; // Always return 1 greater than the highest found
  }

  // --- Tab 1 Action: Update User Doc ---
  Future<void> _updateExistingDoc(Reference ref) async {
    File? file = await _pickDocument();
    if (file != null) {
      String baseName = ref.name.split('.').first; // e.g. "Aadhar"
      String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Updating document...")));

      // Upload with replacement logic
      await _uploadFileWithReplace(file, '$uid/user_docs', baseName);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Document updated!"),
          backgroundColor: Colors.green,
        ),
      );
      _fetchUserDocs(); // Refresh UI
    }
  }

  // --- Tab 2 Action: Add Property ---
  Future<void> _uploadNewProperty() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUploading = true);

    try {
      List<Map<String, dynamic>> newProps = [];

      // Get the starting index safely
      int nextFolderNum = _getNextPropertyFolderIndex();

      for (var card in propertyCards) {
        String folderName = 'property$nextFolderNum';
        List<String> docUrls = [];
        List<String> imageUrls = [];

        // Upload Property Docs
        for (var doc in card.documents) {
          if (doc.selectedDoc != null && doc.pickedFile != null) {
            String? url = await _uploadFileWithReplace(
              doc.pickedFile!,
              '$uid/$folderName',
              doc.selectedDoc!,
            );
            if (url != null) docUrls.add(url);
          }
        }

        // Upload Property Images
        for (int i = 0; i < card.houseImages.length; i++) {
          File f = File(card.houseImages[i].path);
          String? url = await _uploadFileWithReplace(
            f,
            '$uid/$folderName/images',
            'image_$i', // Naming convention for images
          );
          if (url != null) imageUrls.add(url);
        }

        newProps.add({
          // Existing fields
          'apartmentName': card.apartmentNameController.text,
          'roomType': card.roomTypeController.text,
          'location': card.locationController.text,
          'rent': card.rentController.text,
          'maxOccupancy': card.maxOccupancyController.text,
          'folderName': folderName, // Store this for delete logic
          'documentUrls': docUrls,
          'houseImageUrls': imageUrls,

          // --- NEW: Added Fields ---
          'panchayatName': card.panchayatNameController.text,
          'blockNo': card.blockNoController.text,
          'thandaperNo': card.thandaperNoController.text,
          'securityAmount': card.securityAmountController.text,
        });

        nextFolderNum++; // Increment for next card in this batch
      }

      // Upload New User Docs (if any)
      for (var doc in newUserDocuments) {
        if (doc.selectedDoc != null && doc.pickedFile != null) {
          await _uploadFileWithReplace(
            doc.pickedFile!,
            '$uid/user_docs',
            doc.selectedDoc!,
          );
        }
      }

      // Save to Firestore (Merge with existing array)
      await FirebaseFirestore.instance.collection('house').doc(uid).set({
        'properties': FieldValue.arrayUnion(newProps),
      }, SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Property Added Successfully!"),
          backgroundColor: Colors.green,
        ),
      );

      // Reset & Refresh
      setState(() {
        propertyCards = [
          LandlordPropertyForm(documents: [DocumentField()]),
        ];
        newUserDocuments = [DocumentField()];
        _isUploading = false;
      });
      _fetchMyApartments();
      _fetchUserDocs();
      _tabController.animateTo(2); // Auto-switch to "My Apartments"
    } catch (e) {
      print("Upload error: $e");
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // --- Tab 3 Action: Delete Apartment ---
  Future<void> _deleteApartment(int index) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E2A47),
            title: const Text(
              "Delete Property?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "This will mark the listing as deleted.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    Map<String, dynamic> prop = _myApartments[index];

    setState(() => _isLoadingApartments = true);

    try {
      // 1. Remove the original object from the array
      await FirebaseFirestore.instance.collection('house').doc(uid).update({
        'properties': FieldValue.arrayRemove([prop]),
      });

      // 2. Modify the local object to set status as deleted
      prop['status'] = 'deleted';

      // 3. Add the modified object back to the array
      await FirebaseFirestore.instance.collection('house').doc(uid).update({
        'properties': FieldValue.arrayUnion([prop]),
      });

      _fetchMyApartments(); // Refresh UI
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Property marked as deleted"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Delete error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Delete failed"),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoadingApartments = false);
    }
  }

  Future<void> _deleteStorageFolderContents(String path) async {
    try {
      final ref = FirebaseStorage.instance.ref(path);
      final list = await ref.listAll();
      for (var file in list.items) {
        await file.delete();
      }
    } catch (e) {
      print("Storage cleanup error ($path): $e (Folder likely empty/missing)");
    }
  }

  // --- Tab 3 Action: Update Apartment Files ---
  Future<void> _updateApartmentFiles(int index) async {
    // Simple implementation: Allows adding new images to the existing property folder
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    Map<String, dynamic> prop = _myApartments[index];
    String folderName = prop['folderName'] ?? 'property${index + 1}';

    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();

    if (images.isEmpty) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Uploading new images...")));

    List<String> newUrls = [];
    for (var img in images) {
      // Unique name for updates
      String name = 'image_update_${DateTime.now().millisecondsSinceEpoch}';
      String? url = await _uploadFileWithReplace(
        File(img.path),
        '$uid/$folderName/images',
        name,
      );
      if (url != null) newUrls.add(url);
    }

    // Append new URLs to existing list
    List<dynamic> existingUrls = prop['houseImageUrls'] ?? [];
    List<dynamic> updatedUrls = [...existingUrls, ...newUrls];

    // To update a field inside an object in an array, we must remove old and add new in Firestore.
    // 1. Remove old object
    await FirebaseFirestore.instance.collection('house').doc(uid).update({
      'properties': FieldValue.arrayRemove([prop]),
    });

    // 2. Modify object
    prop['houseImageUrls'] = updatedUrls;

    // 3. Add modified object
    await FirebaseFirestore.instance.collection('house').doc(uid).update({
      'properties': FieldValue.arrayUnion([prop]),
    });

    _fetchMyApartments();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Images updated!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onBack();
        return false;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Container(color: const Color(0xFF141E30)),
            // const TwinklingStarBackground(),
            SafeArea(
              child: Column(
                children: [
                  // --- TOP NAV ---
                  CustomTopNavBar(
                    showBack: true,
                    title: "Landlord Profile",
                    onBack: widget.onBack,
                  ),

                  // --- PROFILE HEADER ---
                  const SizedBox(height: 10),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white12,
                    backgroundImage: _profilePicUrl != null
                        ? NetworkImage(_profilePicUrl!)
                        : null,
                    child: _profilePicUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.deepPurple,
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _landlordName ?? "Landlord Name",
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 15),

                  // --- TABS ---
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.orange,
                    labelColor: Colors.orange,
                    unselectedLabelColor: Colors.white60,
                    isScrollable: false,
                    tabs: const [
                      Tab(text: "User Docs"),
                      Tab(text: "Add Property"),
                      Tab(text: "My Apartments"),
                    ],
                  ),

                  // --- TAB VIEW CONTENT ---
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // TAB 1: UPLOADED DOCS & VALIDATE USER
                        _buildUserDocsTab(),

                        // TAB 2: ADD PROPERTY (Compact UI)
                        _buildAddPropertyTab(),

                        // TAB 3: MY APARTMENTS
                        _buildMyApartmentsTab(),
                      ],
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

  // ================= TAB WIDGETS =================

  // --- TAB 1 ---
  Widget _buildUserDocsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. Uploaded Documents List
          Text(
            "Uploaded Documents",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          _isLoadingDocs
              ? const Center(child: CircularProgressIndicator())
              : _fetchedUserDocs.isEmpty
              ? const Text(
                  "No documents uploaded yet.",
                  style: TextStyle(color: Colors.white54),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _fetchedUserDocs.length,
                  itemBuilder: (ctx, i) {
                    final ref = _fetchedUserDocs[i];
                    return Card(
                      color: Colors.white10,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        onTap: () => _openFile(ref),
                        leading: const Icon(
                          Icons.description,
                          color: Colors.blueAccent,
                        ),
                        title: Text(
                          ref.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: SizedBox(
                          width: 80,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => _updateExistingDoc(ref),
                            child: const Text(
                              "Update",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

          const Divider(color: Colors.white24, height: 40),

          // B. Upload New Docs
          Text(
            "Upload New Documents",
            style: TextStyle(
              color: Colors.orange.shade700,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ListView.builder(
            itemCount: newUserDocuments.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) => _buildCompactDocRow(
              newUserDocuments[i],
              onRemove: () => setState(() => newUserDocuments.removeAt(i)),
              docOptions: userDocOptions,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () =>
                setState(() => newUserDocuments.add(DocumentField())),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              "Add Another Doc",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
          ),
          const SizedBox(height: 20),
          if (newUserDocuments.any((d) => d.pickedFile != null))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _uploadNewProperty, // Reuse logic (will only upload docs if no property added)
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text(
                  "Upload Selected Docs",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- TAB 2 ---
  Widget _buildAddPropertyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListView.builder(
            itemCount: propertyCards.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPropertyCard(i),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => setState(
              () => propertyCards.add(
                LandlordPropertyForm(documents: [DocumentField()]),
              ),
            ),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text(
              "Add Another Unit",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isUploading ? null : _uploadNewProperty,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isUploading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "UPLOAD PROPERTY",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 3 ---
  Widget _buildMyApartmentsTab() {
    if (_isLoadingApartments)
      return const Center(child: CircularProgressIndicator());
    if (_myApartments.isEmpty)
      return const Center(
        child: Text(
          "No apartments listed yet.",
          style: TextStyle(color: Colors.white70),
        ),
      );

    return RefreshIndicator(
      onRefresh: _fetchMyApartments,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _myApartments.length,
        itemBuilder: (ctx, index) {
          final apt = _myApartments[index];
          String folderName = 'property${index + 1}';
          List<dynamic> images = apt['houseImageUrls'] ?? [];
          String thumbUrl = images.isNotEmpty ? images.first : '';

          String displayName =
              (apt['apartmentName'] != null &&
                  apt['apartmentName'].toString().isNotEmpty)
              ? apt['apartmentName']
              : "My Apartment";

          return Card(
            color: Colors.white.withOpacity(0.1),
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    image: thumbUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(thumbUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: thumbUrl.isEmpty
                      ? const Center(
                          child: Icon(
                            Icons.home,
                            color: Colors.white54,
                            size: 40,
                          ),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              folderName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${apt['roomType'] ?? 'Unknown'} • ${apt['location'] ?? ''}",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        "Rent: ₹${apt['rent']}",
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => _updateApartmentFiles(index),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.blueAccent),
                            ),
                            child: const Text(
                              "Add Images",
                              style: TextStyle(color: Colors.blueAccent),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => _deleteApartment(index),
                            child: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ================= SMALLER WIDGETS =================

  // Named _buildCompactDocRow to avoid conflict with class DocumentField
  Widget _buildCompactDocRow(
    DocumentField docField, {
    required VoidCallback onRemove,
    required List<String> docOptions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              isDense: true, // COMPACT
              value: docField.selectedDoc,
              hint: const Text(
                "Select Doc",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              underline: Container(),
              items: docOptions
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
                  .toList(),
              onChanged: (val) => setState(() => docField.selectedDoc = val),
            ),
          ),
          if (docField.pickedFile != null) ...[
            Expanded(
              child: Text(
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ] else ...[
            TextButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                      File? picked = await _pickDocument();
                      if (picked != null)
                        setState(() => docField.pickedFile = picked);
                    },
              child: const Text("Pick", style: TextStyle(fontSize: 12)),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            onPressed: onRemove,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.only(left: 8),
          ),
        ],
      ),
    );
  }

  // --- COMPACT PROPERTY CARD ---
  Widget _buildPropertyCard(int index) {
    final property = propertyCards[index];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Property Details",
                style: TextStyle(
                  color: Colors.orange.shade300,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () {
                  property.dispose();
                  setState(() => propertyCards.removeAt(index));
                },
              ),
            ],
          ),
          // COMPACT TEXT FIELDS
          _compactTextField(property.apartmentNameController, "Apartment Name"),
          const SizedBox(height: 8),
          _compactTextField(property.roomTypeController, "Room Type (1BHK)"),
          const SizedBox(height: 8),
          _compactTextField(property.locationController, "Location"),
          const SizedBox(height: 8),

          // --- NEW: Added 4 Fields ---
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.panchayatNameController,
                  "Panchayat Name",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.blockNoController,
                  "Block No.",
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.thandaperNoController,
                  "Thandaper No.",
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.securityAmountController,
                  "Security Amount",
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ---------------------------
          Row(
            children: [
              Expanded(
                child: _compactTextField(
                  property.rentController,
                  "Rent",
                  isNumber: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactTextField(
                  property.maxOccupancyController,
                  "Max Occupants",
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Documents:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Column(
            children: property.documents
                .asMap()
                .entries
                .map(
                  (e) => _buildCompactDocRow(
                    property.documents[e.key],
                    onRemove: () =>
                        setState(() => property.documents.removeAt(e.key)),
                    docOptions: propertyDocOptions,
                  ),
                )
                .toList(),
          ),
          TextButton.icon(
            onPressed: () =>
                setState(() => property.documents.add(DocumentField())),
            icon: const Icon(Icons.add, size: 14),
            label: const Text("Add Doc", style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Divider(color: Colors.white12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Images:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 5),
          if (property.houseImages.isNotEmpty)
            SizedBox(
              height: 60, // Smaller height for compactness
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.houseImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(property.houseImages[i].path),
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => _pickHouseImagesForCard(index),
            icon: const Icon(Icons.image, size: 14),
            label: const Text("Select Images", style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _compactTextField(
    TextEditingController controller,
    String hint, {
    bool isNumber = false,
  }) {
    return SizedBox(
      height: 40, // Fixed small height
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ), // Centered text vertically
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class RequestsPage extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage({super.key, required this.onBack});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final String currentLandlordUid =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

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
                      "Pending Requests",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: currentLandlordUid.isEmpty
                      ? const Center(
                          child: Text(
                            "Please login.",
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      : StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('lrequests')
                              .doc(currentLandlordUid)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (!snapshot.hasData || !snapshot.data!.exists) {
                              return const Center(
                                child: Text(
                                  "No requests received yet.",
                                  style: TextStyle(color: Colors.white70),
                                ),
                              );
                            }

                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            final List<dynamic> requests =
                                data['requests'] ?? [];

                            // Filter for pending requests only
                            final pendingRequests = requests
                                .where((r) => r['status'] == 'pending')
                                .toList();

                            if (pendingRequests.isEmpty) {
                              return const Center(
                                child: Text(
                                  "No pending requests.",
                                  style: TextStyle(color: Colors.white70),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: pendingRequests.length,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemBuilder: (context, index) {
                                final req =
                                    pendingRequests[index]
                                        as Map<String, dynamic>;
                                final String tuid = req['tuid'] ?? '';
                                final int propertyIndex =
                                    req['propertyIndex'] ?? 0;

                                return _RequestItem(
                                  landlordUid: currentLandlordUid,
                                  tenantUid: tuid,
                                  propertyIndex: propertyIndex,
                                  requestData: req,
                                  requestIndex: requests.indexOf(
                                    req,
                                  ), // Original index for updates
                                );
                              },
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

// --- Helper Widget for Individual List Item with House Preview ---
class _RequestItem extends StatelessWidget {
  final String landlordUid;
  final String tenantUid;
  final int propertyIndex;
  final Map<String, dynamic> requestData;
  final int requestIndex;

  const _RequestItem({
    required this.landlordUid,
    required this.tenantUid,
    required this.propertyIndex,
    required this.requestData,
    required this.requestIndex,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Fetch House Data for Preview
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('house')
          .doc(landlordUid)
          .get(),
      builder: (context, houseSnapshot) {
        // 2. Fetch Tenant Name
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('tenant')
              .doc(tenantUid)
              .get(),
          builder: (context, tenantSnapshot) {
            if (houseSnapshot.connectionState == ConnectionState.waiting ||
                tenantSnapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                color: Colors.white10,
                child: SizedBox(
                  height: 80,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            // Parse House Data
            String location = "Unknown Location";
            String roomType = "Property";
            String? imageUrl;
            //String aptname = "My Apartment";

            if (houseSnapshot.hasData && houseSnapshot.data!.exists) {
              final houseData =
                  houseSnapshot.data!.data() as Map<String, dynamic>;
              final List<dynamic> properties = houseData['properties'] ?? [];

              if (propertyIndex < properties.length) {
                final prop = properties[propertyIndex] as Map<String, dynamic>;
                location = prop['location'] ?? "Unknown";
                roomType = prop['apartmentName'] ?? "My Apartment";
                //aptname = prop['apartmentName'] ?? "My Apartment";
                final List<dynamic> images = prop['houseImageUrls'] ?? [];
                if (images.isNotEmpty) imageUrl = images[0];
              }
            }

            // Parse Tenant Data
            String tenantName = "Unknown Tenant";
            if (tenantSnapshot.hasData && tenantSnapshot.data!.exists) {
              final tData = tenantSnapshot.data!.data() as Map<String, dynamic>;
              tenantName = tData['fullName'] ?? "Unknown Tenant";
            }

            return Card(
              color: Colors.white.withOpacity(0.1),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.all(8),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: Colors.black26,
                    child: imageUrl != null
                        ? Image.network(imageUrl, fit: BoxFit.cover)
                        : const Icon(Icons.home, color: Colors.white54),
                  ),
                ),
                title: Text(
                  tenantName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomType,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      location,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TenantProfilePage(
                        tenantUid: tenantUid,
                        tenantName: tenantName,
                        landlordUid: landlordUid,
                        propertyIndex: propertyIndex,
                        requestIndex: requestIndex,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// NEW PAGE: Tenant Profile Page (Accept/Reject & PDF Logic)
// ============================================================================

class TenantProfilePage extends StatefulWidget {
  final String tenantUid;
  final String tenantName;
  final String landlordUid;
  final int propertyIndex;
  final int requestIndex;

  const TenantProfilePage({
    super.key,
    required this.tenantUid,
    required this.tenantName,
    required this.landlordUid,
    required this.propertyIndex,
    required this.requestIndex,
  });

  @override
  State<TenantProfilePage> createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  String? _profilePicUrl;
  String? _apartmentName; // Stores the fetched apartment name
  List<Reference> _userDocs = []; // Stores the fetched documents
  bool _isLoadingImg = true;
  bool _isLoadingDocs = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _fetchTenantProfilePic();
    _fetchRequestDetails(); // Fetch apartment name
    _fetchUserDocs(); // Fetch tenant documents
  }

  // --- NEW: Fetch Apartment Name from lrequests ---
  Future<void> _fetchRequestDetails() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('lrequests')
          .doc(widget.landlordUid)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        List<dynamic> requests = data['requests'] ?? [];

        // Find the request at the specific index
        if (widget.requestIndex < requests.length) {
          Map<String, dynamic> reqData =
              requests[widget.requestIndex] as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              // Get 'apartmentName' field, fallback if null
              _apartmentName =
                  reqData['apartmentName'] ??
                  "Property #${widget.propertyIndex + 1}";
            });
          }
        }
      }
    } catch (e) {
      print("Error fetching request details: $e");
    }
  }

  // --- NEW: Fetch Tenant Documents from Storage ---
  Future<void> _fetchUserDocs() async {
    try {
      // Path: [TenantUID] / user_docs /
      final storageRef = FirebaseStorage.instance.ref(
        '${widget.tenantUid}/user_docs/',
      );
      final listResult = await storageRef.listAll();

      if (mounted) {
        setState(() {
          _userDocs = listResult.items;
          _isLoadingDocs = false;
        });
      }
    } catch (e) {
      print("Error fetching user docs: $e");
      if (mounted) setState(() => _isLoadingDocs = false);
    }
  }

  // --- Helper to Open Document ---
  Future<void> _openDocument(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open document")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

  Future<void> _fetchTenantProfilePic() async {
    try {
      final ref = FirebaseStorage.instance.ref(
        '${widget.tenantUid}/profile_pic/',
      );
      final list = await ref.list(const ListOptions(maxResults: 1));
      if (list.items.isNotEmpty) {
        String url = await list.items.first.getDownloadURL();
        if (mounted) setState(() => _profilePicUrl = url);
      }
    } catch (e) {
      print("Error fetching tenant profile: $e");
    } finally {
      if (mounted) setState(() => _isLoadingImg = false);
    }
  }

  // --- PDF GENERATION AND UPLOAD LOGIC ---
  // --- NEW: Helper to fetch image bytes safely ---
  Future<Uint8List?> _fetchImageBytes(
    String storagePath, {
    bool isListing = false,
  }) async {
    try {
      if (isListing) {
        final ref = FirebaseStorage.instance.ref(storagePath);
        final list = await ref.list(const ListOptions(maxResults: 1));
        if (list.items.isNotEmpty) {
          return await list.items.first.getData();
        }
      } else {
        final ref = FirebaseStorage.instance.ref(storagePath);
        return await ref.getData();
      }
    } catch (e) {
      print("Error fetching image at $storagePath: $e");
    }
    return null;
  }

  // --- PDF GENERATION AND UPLOAD LOGIC (UPDATED WITH ACTUAL AGREEMENT) ---
  Future<void> _handleAccept() async {
    setState(() => _isProcessing = true);
    try {
      // ====================================================
      // 1. FETCH ALL DATA FROM FIRESTORE
      // ====================================================

      // A. Tenant Data
      final tDoc = await FirebaseFirestore.instance
          .collection('tenant')
          .doc(widget.tenantUid)
          .get();
      final String tAadhaar = tDoc.data()?['aadharNumber'] ?? "N/A";

      // B. Landlord Data
      final lDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();
      final String lName = lDoc.data()?['fullName'] ?? "Landlord";
      final String lAadhaar = lDoc.data()?['aadharNumber'] ?? "N/A";

      // C. Property Data
      final hDoc = await FirebaseFirestore.instance
          .collection('house')
          .doc(widget.landlordUid)
          .get();
      final List<dynamic> properties = hDoc.data()?['properties'] ?? [];
      final Map<String, dynamic> propData =
          properties[widget.propertyIndex] as Map<String, dynamic>;

      final String panchayat = propData['panchayatName'] ?? "N/A";
      final String blockNo = propData['blockNo'] ?? "N/A";
      final String thandaperNo = propData['thandaperNo'] ?? "N/A";
      final String rentAmount = propData['rent'] ?? "0";
      final String securityAmount = propData['securityAmount'] ?? "0";

      // ====================================================
      // 2. FETCH ALL IMAGES FROM STORAGE
      // ====================================================

      // A. Signatures (Direct Path)
      final Uint8List? tSignBytes = await _fetchImageBytes(
        '${widget.tenantUid}/sign/sign.jpg',
      );
      final Uint8List? lSignBytes = await _fetchImageBytes(
        '${widget.landlordUid}/sign/sign.jpg',
      );

      // B. Profile Photos (List Folder)
      final Uint8List? tPhotoBytes = await _fetchImageBytes(
        '${widget.tenantUid}/profile_pic/',
        isListing: true,
      );
      final Uint8List? lPhotoBytes = await _fetchImageBytes(
        '${widget.landlordUid}/profile_pic/',
        isListing: true,
      );

      if (tSignBytes == null || lSignBytes == null) {
        throw "Signatures are missing for Tenant or Landlord.";
      }

      // ====================================================
      // 3. GENERATE PDF
      // ====================================================
      final pdf = pw.Document();

      // Process Images for PDF
      final pw.MemoryImage tSignImg = pw.MemoryImage(tSignBytes);
      final pw.MemoryImage lSignImg = pw.MemoryImage(lSignBytes);
      final pw.MemoryImage? tPhotoImg = tPhotoBytes != null
          ? pw.MemoryImage(tPhotoBytes)
          : null;
      final pw.MemoryImage? lPhotoImg = lPhotoBytes != null
          ? pw.MemoryImage(lPhotoBytes)
          : null;

      // Date Format
      final date = DateTime.now();
      final dateString = "${date.day}/${date.month}/${date.year}";

      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- TITLE ---
                pw.Center(
                  child: pw.Text(
                    "RENTAL AGREEMENT",
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),

                // --- DATE ---
                pw.Text(
                  "This Rental Agreement is made and executed on this $dateString.",
                ),
                pw.SizedBox(height: 15),

                // --- PARTIES (With Photos) ---
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left Side: Text Details
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "BETWEEN:",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text("1. $lName (LESSOR/Owner)"),
                          pw.Text("   Aadhaar No: $lAadhaar"),
                          pw.SizedBox(height: 10),
                          pw.Text(
                            "AND",
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text("2. ${widget.tenantName} (LESSEE/Tenant)"),
                          pw.Text("   Aadhaar No: $tAadhaar"),
                        ],
                      ),
                    ),
                    // Right Side: Photos
                    pw.Column(
                      children: [
                        if (lPhotoImg != null)
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Image(lPhotoImg, fit: pw.BoxFit.cover),
                          )
                        else
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Center(child: pw.Text("Owner")),
                          ),
                        pw.Text(
                          "Owner",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.SizedBox(height: 10),
                        if (tPhotoImg != null)
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Image(tPhotoImg, fit: pw.BoxFit.cover),
                          )
                        else
                          pw.Container(
                            width: 60,
                            height: 60,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(),
                            ),
                            child: pw.Center(child: pw.Text("Tenant")),
                          ),
                        pw.Text(
                          "Tenant",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),

                // --- WHEREAS (Property Details) ---
                pw.Text(
                  "WHEREAS:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  "The Lessor is the absolute owner of the residential building situated within the limits of $panchayat, bearing Block No: $blockNo and Thandaper No: $thandaperNo.",
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  "The Lessee has approached the Lessor to take the said schedule building on rent for residential purposes, and the Lessor has agreed to let out the same under the following terms and conditions.",
                ),
                pw.SizedBox(height: 20),

                // --- TERMS AND CONDITIONS ---
                pw.Text(
                  "TERMS AND CONDITIONS:",
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Bullet(
                  text:
                      "Rent Amount: The monthly rent is fixed at Rs. $rentAmount, payable on or before the 5th of every succeeding month.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Security Deposit: The Lessee has paid a sum of Rs. $securityAmount to the Lessor as an interest-free security deposit. Refundable at vacancy subject to deductions.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Period of Tenancy: The tenancy is for a period of 11 months, commencing from $dateString.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Utility Charges: Electricity and water charges shall be paid directly by the Lessee.",
                ),
                pw.SizedBox(height: 5),
                pw.Bullet(
                  text:
                      "Maintenance: The Lessee shall maintain the premises in good tenantable condition.",
                ),

                pw.Spacer(),

                // --- SIGNATURES ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 80,
                          height: 40,
                          child: pw.Image(lSignImg, fit: pw.BoxFit.contain),
                        ),
                        pw.Text("____________________"),
                        pw.Text("LESSOR (Owner)"),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Container(
                          width: 80,
                          height: 40,
                          child: pw.Image(tSignImg, fit: pw.BoxFit.contain),
                        ),
                        pw.Text("____________________"),
                        pw.Text("LESSEE (Tenant)"),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // ====================================================
      // 4. SAVE & UPLOAD TO FIREBASE STORAGE
      // ====================================================
      final Uint8List pdfBytes = await pdf.save();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "agreement_$timestamp.pdf";

      // Upload to Landlord Folder
      final lPdfRef = FirebaseStorage.instance.ref(
        'lagreement/${widget.landlordUid}/$fileName',
      );
      await lPdfRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );

      // Upload to Tenant Folder
      final tPdfRef = FirebaseStorage.instance.ref(
        'tagreement/${widget.tenantUid}/$fileName',
      );
      await tPdfRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );

      // ====================================================
      // 5. UPDATE FIRESTORE STATUS
      // ====================================================

      // Update LREQUESTS
      final lDocRef = FirebaseFirestore.instance
          .collection('lrequests')
          .doc(widget.landlordUid);
      final lDocSnap = await lDocRef.get();
      if (lDocSnap.exists) {
        List<dynamic> reqs = lDocSnap.data()!['requests'];
        if (widget.requestIndex < reqs.length) {
          reqs[widget.requestIndex]['status'] = 'accepted';
          await lDocRef.update({'requests': reqs});
        }
      }

      // Update TREQUESTS
      final tDocRef = FirebaseFirestore.instance
          .collection('trequests')
          .doc(widget.tenantUid);
      final tDocSnap = await tDocRef.get();
      if (tDocSnap.exists) {
        List<dynamic> tReqs = tDocSnap.data()!['requests'];
        for (var req in tReqs) {
          if (req['luid'] == widget.landlordUid &&
              req['propertyIndex'] == widget.propertyIndex &&
              req['status'] == 'pending') {
            req['status'] = 'accepted';
            break;
          }
        }
        await tDocRef.update({'requests': tReqs});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Rental Agreement Generated & Signed!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      print("Error generating agreement: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    setState(() => _isProcessing = true);
    try {
      final lDocRef = FirebaseFirestore.instance
          .collection('lrequests')
          .doc(widget.landlordUid);
      final lDocSnap = await lDocRef.get();
      if (lDocSnap.exists) {
        List<dynamic> reqs = lDocSnap.data()!['requests'];
        if (widget.requestIndex < reqs.length) {
          reqs[widget.requestIndex]['status'] = 'rejected';
          await lDocRef.update({'requests': reqs});
        }
      }

      final tDocRef = FirebaseFirestore.instance
          .collection('trequests')
          .doc(widget.tenantUid);
      final tDocSnap = await tDocRef.get();
      if (tDocSnap.exists) {
        List<dynamic> tReqs = tDocSnap.data()!['requests'];
        for (var req in tReqs) {
          if (req['luid'] == widget.landlordUid &&
              req['propertyIndex'] == widget.propertyIndex &&
              req['status'] == 'pending') {
            req['status'] = 'rejected';
            break;
          }
        }
        await tDocRef.update({'requests': tReqs});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Request Rejected"),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),
          SafeArea(
            child: SingleChildScrollView(
              // Made scrollable for documents list
              child: Column(
                children: [
                  CustomTopNavBar(
                    showBack: true,
                    title: "Tenant Profile",
                    onBack: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 40),

                  // Profile Pic
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage: _profilePicUrl != null
                        ? NetworkImage(_profilePicUrl!)
                        : null,
                    child: _isLoadingImg
                        ? const CircularProgressIndicator()
                        : (_profilePicUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.white,
                                )
                              : null),
                  ),
                  const SizedBox(height: 20),

                  // Tenant Name
                  Text(
                    widget.tenantName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // --- DISPLAY APARTMENT NAME ---
                  Text(
                    _apartmentName != null
                        ? "Applied for: $_apartmentName"
                        : "Loading property details...",
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),

                  const SizedBox(height: 30),

                  // --- NEW: USER DOCUMENTS LIST ---
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "User Documents",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (_isLoadingDocs)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else if (_userDocs.isEmpty)
                    const Text(
                      "No documents uploaded.",
                      style: TextStyle(color: Colors.white54),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Column(
                        children: _userDocs.map((ref) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.description,
                                color: Colors.blueAccent,
                              ),
                              title: Text(
                                ref.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: const Icon(
                                Icons.open_in_new,
                                color: Colors.white54,
                              ),
                              onTap: () => _openDocument(ref),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                  const SizedBox(height: 30),

                  // Action Buttons
                  if (_isProcessing)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 20,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _handleReject,
                              child: const Text(
                                "Decline",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _handleAccept,
                              child: const Text(
                                "Accept",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- SETTINGS PAGE --------------------
class GlassmorphismContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double opacity;
  final double blur;
  final VoidCallback? onTap;

  const GlassmorphismContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 15.0,
    this.opacity =
        0.05, // Default opacity lowered to 0.05 for more transparency
    this.blur = 10.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// LOGOUT CONFIRMATION DIALOG
// ====================================================================

class LogoutConfirmationDialog extends StatelessWidget {
  const LogoutConfirmationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: GlassmorphismContainer(
        borderRadius: 20.0,
        opacity: 0.12, // Opacity reduced from 0.2 to 0.12
        blur: 15.0,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Confirm Logout',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Are you sure you want to log out of Secure Homes?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // YES button (Proceed to Logout)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // 1. Close the confirmation dialog
                      Navigator.pop(context);

                      // 2. Proceed with logout (navigate to LoginPage and clear stack)
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const LoginPage(),
                        ),
                        (Route<dynamic> route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'YES, Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                // NO button (Cancel)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // Close the dialog (Cancel the logout)
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'NO, Stay',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TwinklingStarBackground extends StatefulWidget {
  const TwinklingStarBackground({super.key});

  @override
  State<TwinklingStarBackground> createState() =>
      _TwinklingStarBackgroundState();
}

class _TwinklingStarBackgroundState extends State<TwinklingStarBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final int _numberOfStars = 80; // INCREASED DENSITY from 50
  late List<Map<String, dynamic>> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        seconds: 15,
      ), // Longer duration for subtle movement
    )..repeat();

    // Initialize stars with random properties
    _stars = List.generate(_numberOfStars, (index) => _createRandomStar());
  }

  Map<String, dynamic> _createRandomStar() {
    return {
      'offset': Offset(Random().nextDouble(), Random().nextDouble()),
      'size':
          2.0 +
          Random().nextDouble() *
              3.0, // INCREASED SIZE range from 1.5-4.0 to 2.0-5.0
      'duration': Duration(
        milliseconds: 1500 + Random().nextInt(1500),
      ), // Twinkle duration
      'delay': Duration(
        milliseconds: Random().nextInt(10000),
      ), // Starting delay
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: _stars.map((star) {
              final double screenWidth = MediaQuery.of(context).size.width;
              final double screenHeight = MediaQuery.of(context).size.height;

              // Calculate twinkling effect based on controller time and star properties
              final double timeInMilliseconds =
                  _controller.value * _controller.duration!.inMilliseconds;
              final double timeOffset =
                  (timeInMilliseconds + star['delay'].inMilliseconds) /
                  star['duration'].inMilliseconds;

              // Use a sine wave for blinking effect, slightly offset to prevent perfect synchronization
              final double opacityFactor = (sin(timeOffset * pi * 2) + 1) / 2;

              // INCREASED INTENSITY/OPACITY: Opacity range from very dim (0.1) to bright (0.8)
              final double opacity =
                  0.1 +
                  (0.7 * opacityFactor); // Multiplier changed from 0.5 to 0.7

              return Positioned(
                left: star['offset'].dx * screenWidth,
                top: star['offset'].dy * screenHeight,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: star['size'],
                    height: star['size'],
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.5 * opacity),
                          blurRadius: star['size'] / 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
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

class SettingsPage extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> _settingsOptions = [
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
        'action': (BuildContext context) => print('Navigate to Notifications'),
      },
      {
        'title': 'View My Profile',
        'icon': Icons.person,
        'color': Colors.purple,
        'action': (BuildContext context) {
          final uid = FirebaseAuth.instance.currentUser!.uid;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Landlordsearch_ProfilePage2(
                landlordUid: uid,
                propertyDetails: {
                  'roomType': 'N/A',
                  'location': 'N/A',
                  'rent': 'N/A',
                  'maxOccupancy': 'N/A',
                },
                propertyIndex: 0,
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
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: "Settings",
                  onBack: onBack,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Account Settings",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ..._settingsOptions.map((option) {
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
                        }).toList(),

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
                                        onPressed: () {
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
          "Contact Admin:\n\n📞 +91 9497320928\n📞 +91 8281258530",
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
    // Keep controllers for fields being edited
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController =
        TextEditingController(); // Represents profileName (UserId)
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController aadharController =
        TextEditingController(); // --- NEW: Aadhar Controller ---

    // Variables for image picking
    XFile? _pickedImageFile;
    XFile? _pickedSignFile;
    bool _isUpdating = false;

    // --- Pre-fetch current data (Cannot be done easily in static function without passing data) ---

    showDialog(
      context: context,
      // Use StatefulBuilder to manage the state within the dialog
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep original color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep shape
            title: const Text(
              // Keep title style
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
                      // --- Image Picking Logic (Profile Pic) ---
                      if (_isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            // Use StatefulBuilder's setState
                            _pickedImageFile = image;
                          });
                          print("Image picked: ${image.path}");
                        } else {
                          print("Image picking cancelled.");
                        }
                      } catch (e) {
                        print("Error picking image: $e");
                        // Show error Snackbar using the original context
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to pick image'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      // Keep original CircleAvatar structure
                      radius: 40,
                      backgroundColor:
                          Colors.grey.shade700, // Keep placeholder background
                      backgroundImage: _pickedImageFile != null
                          ? FileImage(
                              File(_pickedImageFile!.path),
                            ) // Show picked file
                          : const AssetImage('assets/profile_placeholder.png')
                                as ImageProvider, // Keep placeholder
                      child: const Align(
                        // Keep edit icon overlay
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
                  const SizedBox(height: 15), // Keep spacing
                  // Use provided _buildInputField
                  _buildInputField(nameController, "Full Name"),
                  _buildInputField(
                    idController,
                    "User ID",
                  ), // Profile Name (UserId)
                  _buildInputField(phoneController, "Phone Number"),
                  _buildInputField(
                    aadharController,
                    "Aadhar Number",
                  ), // --- NEW: Aadhar Field ---
                  // --- NEW: Signature Picker UI ---
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: () async {
                      // --- Signature Picking Logic ---
                      if (_isUpdating) return;
                      final ImagePicker picker = ImagePicker();
                      try {
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (image != null) {
                          stfSetState(() {
                            _pickedSignFile = image;
                          });
                          print("Signature picked: ${image.path}");
                        }
                      } catch (e) {
                        print("Error picking signature: $e");
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
                      child: _pickedSignFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(_pickedSignFile!.path),
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
                  // --------------------------------
                ],
              ),
            ),
            actions: [
              // Keep original actions structure
              TextButton(
                onPressed: () =>
                    Navigator.pop(dialogContext), // Use dialogContext
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ), // Keep style
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Keep color
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isUpdating
                    ? null
                    : () async {
                        // --- UPDATE LOGIC ---
                        final String aadhar = aadharController.text.trim();

                        // --- NEW: Aadhar Validation Check ---
                        if (aadhar.isNotEmpty && aadhar.length != 12) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Aadhar Number must be exactly 12 digits',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return; // Stop update
                        }
                        // ------------------------------------

                        stfSetState(() {
                          _isUpdating = true;
                        });
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);

                        final String? uid =
                            FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Error Not logged in'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isUpdating = false;
                          });
                          return;
                        }

                        try {
                          // 1. Upload Profile Image if picked
                          if (_pickedImageFile != null) {
                            print("Uploading profile picture...");
                            // Path: uid/profile_pic/profile_image.jpg
                            String filePath =
                                '$uid/profile_pic/profile_image.jpg';
                            Reference storageRef = FirebaseStorage.instance
                                .ref()
                                .child(filePath);
                            UploadTask uploadTask = storageRef.putFile(
                              File(_pickedImageFile!.path),
                            );
                            await uploadTask;
                            print("Profile picture uploaded successfully.");
                          }

                          // --- NEW: Upload Signature if picked ---
                          if (_pickedSignFile != null) {
                            print("Uploading signature...");
                            // Path: uid/sign/sign.jpg
                            String signPath = '$uid/sign/sign.jpg';
                            Reference signRef = FirebaseStorage.instance
                                .ref()
                                .child(signPath);
                            UploadTask signUploadTask = signRef.putFile(
                              File(_pickedSignFile!.path),
                            );
                            await signUploadTask;
                            print("Signature uploaded successfully.");
                          }
                          // ---------------------------------------

                          // 2. Prepare data for Firestore update
                          final String newFullName = nameController.text.trim();
                          final String newProfileName = idController.text
                              .trim(); // User ID field is Profile Name
                          final String newPhoneNumber = phoneController.text
                              .trim();

                          Map<String, dynamic> updateData = {};
                          if (newFullName.isNotEmpty)
                            updateData['fullName'] = newFullName;
                          if (newProfileName.isNotEmpty)
                            updateData['profileName'] = newProfileName;
                          if (newPhoneNumber.isNotEmpty)
                            updateData['phoneNumber'] = newPhoneNumber;
                          if (aadhar
                              .isNotEmpty) // --- NEW: Add Aadhar to update map ---
                            updateData['aadharNumber'] = aadhar;

                          // 3. Update Firestore if there's data to update
                          if (updateData.isNotEmpty) {
                            print(
                              "Updating Firestore for UID: $uid with data: $updateData",
                            );
                            await FirebaseFirestore.instance
                                .collection('landlord')
                                .doc(uid)
                                .update(updateData);
                            print("Firestore update successful.");

                            // 4. Update unique UserId collection IF profileName changed
                            if (newProfileName.isNotEmpty) {
                              final checkSnap = await FirebaseFirestore.instance
                                  .collection('UserIds')
                                  .where('UserId', isEqualTo: newProfileName)
                                  .limit(1)
                                  .get();
                              if (checkSnap.docs.isEmpty) {
                                print(
                                  "Adding new unique profile name to UserIds collection.",
                                );
                                await FirebaseFirestore.instance
                                    .collection('UserIds')
                                    .add({'UserId': newProfileName});
                              } else {
                                print("New profile name might already exist.");
                              }
                            }
                          } else if (_pickedImageFile != null ||
                              _pickedSignFile != null) {
                            // Modified log to account for signature update
                            print(
                              "Only images updated, skipping Firestore field update.",
                            );
                          } else {
                            print(
                              "No fields changed and no new picture, skipping updates.",
                            );
                          }

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Profile updated successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop(); // Close dialog on success
                        } catch (e) {
                          print("Error updating profile: $e");
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text('Update failed ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() {
                              _isUpdating = false;
                            });
                          }
                        }
                      },
                child: _isUpdating
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
                      ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- UPDATED CHANGE PASSWORD DIALOG ---
  static void _showChangePasswordDialog(BuildContext context) {
    // Removed oldPassController
    final TextEditingController newPassController = TextEditingController();
    final TextEditingController confirmPassController = TextEditingController();
    bool _isChangingPassword = false; // Loading state

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        // Use StatefulBuilder for loading state
        builder: (stfContext, stfSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2A47), // Keep style
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ), // Keep style
            title: const Text(
              // Keep style
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
                  // Removed old password field
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
              // Keep style
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent, // Keep style
                  disabledBackgroundColor: Colors.grey.shade600,
                ),
                onPressed: _isChangingPassword
                    ? null
                    : () async {
                        // --- Simplified Password Change Logic ---
                        stfSetState(() {
                          _isChangingPassword = true;
                        });
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final navigator = Navigator.of(dialogContext);

                        final String newPassword =
                            newPassController.text; // No trim
                        final String confirmPassword =
                            confirmPassController.text; // No trim

                        // Validation
                        if (newPassword.isEmpty || confirmPassword.isEmpty) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Please fill both password fields'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isChangingPassword = false;
                          });
                          return;
                        }
                        if (newPassword != confirmPassword) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('New passwords do not match'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isChangingPassword = false;
                          });
                          return;
                        }
                        // Password complexity rules
                        if (newPassword.length < 6) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'New password must be at least 6 characters long',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isChangingPassword = false;
                          });
                          return;
                        }
                        if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(newPassword)) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'New password must contain only letters and numbers',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isChangingPassword = false;
                          });
                          return;
                        }

                        User? user = FirebaseAuth.instance.currentUser;
                        if (user == null) {
                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Error Not logged in'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          stfSetState(() {
                            _isChangingPassword = false;
                          });
                          return;
                        }

                        try {
                          // Directly update password (no re-authentication)
                          print("Attempting to update password directly...");
                          await user.updatePassword(newPassword);
                          print(
                            "Password updated successfully via direct method!",
                          );

                          scaffoldMessenger.showSnackBar(
                            const SnackBar(
                              content: Text('Password changed successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          navigator.pop(); // Close dialog on success
                        } on FirebaseAuthException catch (e) {
                          print(
                            "Error changing password directly: ${e.code} - ${e.message}",
                          );
                          String errorMsg =
                              'Failed to change password Please try again'; // Default
                          // Handle common errors from direct update
                          if (e.code == 'weak-password') {
                            errorMsg = 'New password is too weak';
                          } else if (e.code == 'requires-recent-login') {
                            // This error CAN still happen even without explicitly asking for re-auth
                            errorMsg =
                                'This action requires recent login Please log out and log in again';
                          } else {
                            errorMsg = 'Error ${e.message ?? e.code}';
                          }
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(errorMsg),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } catch (e) {
                          print("Generic error changing password: $e");
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to change password ${e.toString()}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (navigator.context.mounted) {
                            stfSetState(() {
                              _isChangingPassword = false;
                            });
                          }
                        }
                      },
                child:
                    _isChangingPassword // Show loading or text
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
                      ), // Keep style
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Provided _buildInputField ---
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
}

class AgreementsPage extends StatefulWidget {
  final VoidCallback onBack;
  const AgreementsPage({super.key, required this.onBack});

  @override
  State<AgreementsPage> createState() => _AgreementsPageState();
}

class _AgreementsPageState extends State<AgreementsPage> {
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  List<Reference> _agreementFiles = [];
  bool _isLoading = true;
  String? _error;

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
    } catch (e) {
      print("Error fetching agreements: $e");
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch PDF viewer")),
        );
      }
    } catch (e) {
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
                      color: Colors.white.withOpacity(0.8),
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
                                color: Colors.white.withOpacity(0.5),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "No agreements found.",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
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
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
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
class PaymentsPage extends StatefulWidget {
  final VoidCallback onBack;
  const PaymentsPage({super.key, required this.onBack});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  String? selectedMethod;
  final TextEditingController _amountController = TextEditingController();

  // Mock transactions (local list)
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Background layers
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top NavBar
                CustomTopNavBar(
                  showBack: true,
                  title: "Payments",
                  onBack: widget.onBack,
                ),
                const SizedBox(height: 15),

                // Flexible + Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset + 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------

                        // -------------------- TRANSACTION HISTORY --------------------
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0),
                          child: Text(
                            "Transaction History",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: mockTransactions.length,
                          itemBuilder: (context, index) {
                            var data = mockTransactions[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.2),
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
                                    color: Colors.white.withOpacity(0.7),
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
                            );
                          },
                        ),
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
            : Colors.white.withOpacity(0.1),
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
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
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
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
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
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
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

class Landlordsearch_ProfilePage extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property

  const Landlordsearch_ProfilePage({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  _Landlordsearch_ProfilePageState createState() =>
      _Landlordsearch_ProfilePageState();
}

class _Landlordsearch_ProfilePageState
    extends State<Landlordsearch_ProfilePage> {
  String? _landlordName;
  String? _landlordPhoneNumber;
  String? _landlordEmail;
  String? _landlordProfilePicUrl;
  List<String> _propertyImageUrls = []; // To store fetched image URLs

  // --- NEW: Variables for Property Documents ---
  List<Reference> _propertyDocs = [];
  bool _isLoadingDocs = true;
  String? _docError;
  // -------------------------------------------

  bool _isLoading = true; // Loading state for main data

  final List<Map<String, dynamic>> dummyReviews = [
    {
      "name": "Anjali R.",
      "rating": 4,
      "comment":
          "Very responsive landlord! The flat was clean and matches the photos.",
      "date": "Oct 20, 2025",
    },
    {
      "name": "Rahul N.",
      "rating": 5,
      "comment":
          "Had a great experience. The location is perfect and rent is reasonable.",
      "date": "Sep 14, 2025",
    },
    {
      "name": "Sneha T.",
      "rating": 3,
      "comment":
          "Property is good but communication could be faster. Still recommended.",
      "date": "Aug 30, 2025",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _fetchPropertyDocuments(); // Call the new function
  }

  // --- NEW: Function to Fetch Property Documents ---
  Future<void> _fetchPropertyDocuments() async {
    try {
      // Path: uid / property(n+1) / (files here)
      String propertyFolderName = 'property${widget.propertyIndex + 1}';
      String docPath = '${widget.landlordUid}/$propertyFolderName/';

      final storageRef = FirebaseStorage.instance.ref().child(docPath);
      final listResult = await storageRef.listAll();

      // items contains files, prefixes contains folders (like 'images')
      // We only want files in the root of property(n+1)
      if (mounted) {
        setState(() {
          _propertyDocs = listResult.items;
          _isLoadingDocs = false;
        });
      }
    } catch (e) {
      print("Error fetching docs: $e");
      if (mounted) {
        setState(() {
          _docError = "Error accessing files";
          _isLoadingDocs = false;
        });
      }
    }
  }

  // --- NEW: Helper to Open Document ---
  Future<void> _openDocument(Reference ref) async {
    try {
      String url = await ref.getDownloadURL();
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open document")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error opening file: $e")));
    }
  }

  Future<void> _fetchData() async {
    try {
      // 1. Fetch Landlord Details
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();

      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            _landlordName = data['fullName'] as String? ?? 'Name Not Available';
            _landlordPhoneNumber = data['phoneNumber'] as String?;
            _landlordEmail = data['email'] as String?;
          });
        } else {
          if (mounted)
            setState(() => _landlordName = 'Landlord Data Not Found');
        }
      } else {
        if (mounted) setState(() => _landlordName = 'Landlord Not Found');
      }

      // 2. Fetch Landlord Profile Pic
      try {
        ListResult profilePicResult = await FirebaseStorage.instance
            .ref('${widget.landlordUid}/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (profilePicResult.items.isNotEmpty && mounted) {
          String url = await profilePicResult.items.first.getDownloadURL();
          setState(() {
            _landlordProfilePicUrl = url;
          });
        }
      } catch (storageError) {
        print("Error fetching landlord profile pic: $storageError");
      }

      // 3. Fetch Property Images
      List<String> imageUrls = [];
      String propertyFolderName = 'property${widget.propertyIndex + 1}';
      String imageFolderPath =
          '${widget.landlordUid}/$propertyFolderName/images/';
      try {
        ListResult imageListResult = await FirebaseStorage.instance
            .ref(imageFolderPath)
            .listAll();
        for (var item in imageListResult.items) {
          String url = await item.getDownloadURL();
          imageUrls.add(url);
        }
        if (mounted) {
          setState(() {
            _propertyImageUrls = imageUrls;
          });
        }
      } catch (storageError) {
        print("Error fetching property images: $storageError");
      }
    } catch (e) {
      print("Error fetching data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading details: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- NEW: Handle Send Request Logic ---
  // --- NEW: Handle Send Request Logic (Updated to include apartmentName) ---
  Future<void> _handleSendRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You must be logged in to send a request."),
        ),
      );
      return;
    }

    try {
      String timestamp = DateTime.now().toIso8601String();

      // Get apartmentName from propertyDetails (or default if missing)
      String aptName =
          widget.propertyDetails['apartmentName'] ?? 'My Apartment';

      // 1. Prepare Tenant Request Data
      Map<String, dynamic> tRequestData = {
        'luid': widget.landlordUid,
        'tuid': user.uid,
        'landlordName': _landlordName ?? 'Unknown',
        'status': 'pending',
        'propertyIndex': widget.propertyIndex,
        'timestamp': timestamp,
        'apartmentName': aptName, // ADDED
      };

      // 2. Prepare Landlord Request Data
      Map<String, dynamic> lRequestData = {
        'tuid': user.uid,
        'propertyIndex': widget.propertyIndex,
        'timestamp': timestamp,
        'status': 'pending',
        'apartmentName': aptName, // ADDED
      };

      // 3. Update 'trequests' collection (Doc ID: Tenant UID)
      await FirebaseFirestore.instance
          .collection('trequests')
          .doc(user.uid)
          .set({
            'requests': FieldValue.arrayUnion([tRequestData]),
            'tenantUid': user.uid,
          }, SetOptions(merge: true));

      // 4. Update 'lrequests' collection (Doc ID: Landlord UID)
      await FirebaseFirestore.instance
          .collection('lrequests')
          .doc(widget.landlordUid)
          .set({
            'requests': FieldValue.arrayUnion([lRequestData]),
            'landlordUid': widget.landlordUid,
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request sent to the landlord!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("Error sending request: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to send request: $e")));
      }
    }
  }

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
                CustomTopNavBar(
                  showBack: true,
                  title: "Landlord Profile",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 20),

                _isLoading
                    ? const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ---------- Profile Header ----------
                              Center(
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 50,
                                      backgroundColor: Colors.white.withOpacity(
                                        0.3,
                                      ),
                                      backgroundImage:
                                          _landlordProfilePicUrl != null
                                          ? NetworkImage(
                                              _landlordProfilePicUrl!,
                                            )
                                          : null,
                                      child: _landlordProfilePicUrl == null
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                              size: 60,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _landlordName ?? "...",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      widget.propertyDetails['location'] ??
                                          "Location Unknown",
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 25),

                              // ---------- Send Request Button ----------
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _handleSendRequest, // UPDATED LOGIC
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 26,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Send Request",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 25),

                              // ---------- Property Photos ----------
                              const Text(
                                "Property Photos",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 140,
                                child: _propertyImageUrls.isEmpty
                                    ? Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Center(
                                          child: const Icon(
                                            Icons.hide_image_outlined,
                                            color: Colors.white70,
                                            size: 40,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _propertyImageUrls.length,
                                        itemBuilder: (context, index) {
                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => Scaffold(
                                                    backgroundColor:
                                                        Colors.black,
                                                    appBar: AppBar(
                                                      backgroundColor:
                                                          Colors.black,
                                                      iconTheme:
                                                          const IconThemeData(
                                                            color: Colors.white,
                                                          ),
                                                    ),
                                                    body: Center(
                                                      child: InteractiveViewer(
                                                        panEnabled: true,
                                                        minScale: 0.5,
                                                        maxScale: 4.0,
                                                        child: Image.network(
                                                          _propertyImageUrls[index],
                                                          fit: BoxFit.contain,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Container(
                                              width: 160,
                                              margin: const EdgeInsets.only(
                                                right: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.2,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                image: DecorationImage(
                                                  image: NetworkImage(
                                                    _propertyImageUrls[index],
                                                  ),
                                                  fit: BoxFit.cover,
                                                  onError:
                                                      (exception, stackTrace) {
                                                        print(
                                                          "Error loading image",
                                                        );
                                                      },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 25),

                              // ---------- NEW: Property Documents Section ----------
                              const Text(
                                "Property Document",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_isLoadingDocs)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              else if (_docError != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.redAccent),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Colors.redAccent,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _docError!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_propertyDocs.isEmpty)
                                const Text(
                                  "No documents available.",
                                  style: TextStyle(color: Colors.white54),
                                )
                              else
                                Column(
                                  children: _propertyDocs.map((ref) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.description_outlined,
                                          color: Colors.blueAccent,
                                        ),
                                        title: Text(
                                          ref.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.open_in_new,
                                          color: Colors.white54,
                                          size: 20,
                                        ),
                                        onTap: () => _openDocument(ref),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 30),
                              // -----------------------------------------------------

                              // ---------- About Property ----------
                              _infoContainer("About Property", [
                                _infoRow(
                                  Icons.home,
                                  widget.propertyDetails['roomType'] ?? 'N/A',
                                ),
                                _infoRow(
                                  Icons.location_on,
                                  widget.propertyDetails['location'] ?? 'N/A',
                                ),
                                _infoRow(
                                  Icons.attach_money,
                                  "Rent: ₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                                ),
                                _infoRow(
                                  Icons.security,
                                  "Security: ₹${widget.propertyDetails['securityAmount'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.people,
                                  "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                                ),
                                // --- NEW FIELDS ---
                                _infoRow(
                                  Icons.location_city,
                                  "Panchayat: ${widget.propertyDetails['panchayatName'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.map,
                                  "Block No: ${widget.propertyDetails['blockNo'] ?? 'N/A'}",
                                ),
                                _infoRow(
                                  Icons.confirmation_number,
                                  "Thandaper No: ${widget.propertyDetails['thandaperNo'] ?? 'N/A'}",
                                ),
                              ]),
                              const SizedBox(height: 25),

                              // ---------- Contact Section ----------
                              _infoContainer("Contact Details", [
                                _infoRow(
                                  Icons.phone,
                                  _landlordPhoneNumber ?? 'Not Available',
                                ),
                                _infoRow(
                                  Icons.email,
                                  _landlordEmail ?? 'Not Available',
                                ),
                              ]),
                              const SizedBox(height: 25),

                              // ---------- Write a Review Button ----------
                              Center(
                                child: ElevatedButton.icon(
                                  onPressed: () => _showReviewDialog(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.reviews,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    "Write a Review",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 35),

                              // ---------- Reviews Section ----------
                              const Text(
                                "Reviews",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...dummyReviews.map((review) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Colors.orange
                                                .withOpacity(0.8),
                                            child: Text(
                                              review['name'][0],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                review['name'],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Row(
                                                children: List.generate(
                                                  5,
                                                  (index) => Icon(
                                                    index < review['rating']
                                                        ? Icons.star
                                                        : Icons.star_border,
                                                    size: 18,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            review['date'],
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        review['comment'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
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
    );
  }

  static Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _infoContainer(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  void _showReviewDialog(BuildContext context) {
    final TextEditingController reviewController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Write a Review",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: reviewController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Enter your review here...",
            hintStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Review submitted: ${reviewController.text}"),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
            ),
            child: const Text("Submit", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
} // End of _Landlordsearch_ProfilePageState // End of _Landlordsearch_ProfilePageState

class Landlordsearch_ProfilePage2 extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property for image path

  const Landlordsearch_ProfilePage2({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  _Landlordsearch_ProfilePage2State createState() =>
      _Landlordsearch_ProfilePage2State();
}

class _Landlordsearch_ProfilePage2State
    extends State<Landlordsearch_ProfilePage2> {
  String? _landlordName;
  String? _landlordPhoneNumber;
  String? _landlordEmail;
  String? _landlordProfilePicUrl;
  List<String> _propertyImageUrls = []; // To store fetched image URLs
  bool _isLoading = true; // Loading state

  // Dummy reviews remain the same
  final List<Map<String, dynamic>> dummyReviews = [
    {
      "name": "Anjali R.",
      "rating": 4,
      "comment":
          "Very responsive landlord! The flat was clean and matches the photos.",
      "date": "Oct 20, 2025",
    },
    {
      "name": "Rahul N.",
      "rating": 5,
      "comment":
          "Had a great experience. The location is perfect and rent is reasonable.",
      "date": "Sep 14, 2025",
    },
    {
      "name": "Sneha T.",
      "rating": 3,
      "comment":
          "Property is good but communication could be faster. Still recommended.",
      "date": "Aug 30, 2025",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    // No need to set isLoading true here, already true initially
    // setState(() { _isLoading = true; });
    try {
      // 1. Fetch Landlord Details from 'landlord' collection
      print(
        "Fetching landlord details for UID: ${widget.landlordUid}",
      ); // Debug print
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();

      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          print("Landlord data found: $data"); // Debug print
          setState(() {
            _landlordName = data['fullName'] as String? ?? 'Name Not Available';
            _landlordPhoneNumber = data['phoneNumber'] as String?;
            _landlordEmail = data['email'] as String?;
            // Assuming profile pic URL isn't stored in landlord doc, fetch from storage next
          });
        } else {
          print("Landlord document data is null."); // Debug print
          if (mounted)
            setState(() => _landlordName = 'Landlord Data Not Found');
        }
      } else {
        print(
          "Landlord document not found for UID: ${widget.landlordUid}",
        ); // Debug print
        if (mounted) setState(() => _landlordName = 'Landlord Not Found');
      }

      // 2. Fetch Landlord Profile Pic from Storage
      print("Fetching landlord profile picture..."); // Debug print
      try {
        ListResult profilePicResult = await FirebaseStorage.instance
            .ref('${widget.landlordUid}/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (profilePicResult.items.isNotEmpty && mounted) {
          String url = await profilePicResult.items.first.getDownloadURL();
          print("Profile picture URL fetched: $url"); // Debug print
          setState(() {
            _landlordProfilePicUrl = url;
          });
        } else {
          print("No profile picture found in storage."); // Debug print
        }
      } catch (storageError) {
        print(
          "Error fetching landlord profile pic: $storageError",
        ); // Keep default icon
      }

      // 3. Fetch Property Images from Storage
      List<String> imageUrls = [];
      String propertyFolderName =
          'property${widget.propertyIndex + 1}'; // property1, property2 etc.
      String imageFolderPath =
          '${widget.landlordUid}/$propertyFolderName/images/';
      print("Fetching property images from: $imageFolderPath"); // Debug print
      try {
        ListResult imageListResult = await FirebaseStorage.instance
            .ref(imageFolderPath)
            .listAll();
        print(
          "Found ${imageListResult.items.length} images in storage.",
        ); // Debug print
        for (var item in imageListResult.items) {
          String url = await item.getDownloadURL();
          imageUrls.add(url);
        }
        if (mounted) {
          print(
            "Setting ${imageUrls.length} property image URLs.",
          ); // Debug print
          setState(() {
            _propertyImageUrls = imageUrls;
          });
        }
      } catch (storageError) {
        print(
          "Error fetching property images from $imageFolderPath: $storageError",
        ); // Will show placeholders
      }
    } catch (e) {
      print("Error fetching landlord/property data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading details: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        print(
          "Finished fetching data, setting isLoading = false.",
        ); // Debug print
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget _infoContainer(String title, List<Widget> children) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
    }

    Widget _infoRow(IconData icon, String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: Colors.orange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }

    // --- NO UI STRUCTURE CHANGES, only displaying fetched data ---
    return Scaffold(
      resizeToAvoidBottomInset: true, // Keep original
      body: Stack(
        children: [
          const AnimatedGradientBackground(), // Keep original
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTopNavBar(
                  // Keep original
                  showBack: true,
                  title: "Landlord Profile",
                  onBack: () => Navigator.pop(context),
                ),
                const SizedBox(height: 20), // Keep spacing

                _isLoading
                    ? const Expanded(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                        ),
                      )
                    : Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ---------- Profile Header ----------
                              Center(
                                // Keep original structure
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      // Display fetched or placeholder image
                                      radius: 50,
                                      backgroundColor: Colors.white.withOpacity(
                                        0.3,
                                      ),
                                      backgroundImage:
                                          _landlordProfilePicUrl != null
                                          ? NetworkImage(
                                              _landlordProfilePicUrl!,
                                            )
                                          : null,
                                      child: _landlordProfilePicUrl == null
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                              size: 60,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      // Display fetched name
                                      _landlordName ??
                                          "...", // Show fetched name or placeholder
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      // Display fetched property location if available
                                      widget.propertyDetails['location'] ??
                                          "Location Unknown",
                                      // Fetch from passed details
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 25),

                              // Keep spacing
                              // ---------- Send Request Button (Keep original) ----------
                              const SizedBox(height: 25),
                              // Keep spacing
                              // ---------- Property Photos ----------
                              const Text(
                                "Property Photos",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Keep style
                              const SizedBox(height: 10),
                              // Keep spacing
                              SizedBox(
                                height: 140,
                                child:
                                    _propertyImageUrls
                                        .isEmpty // Check if images were fetched
                                    ? Container(
                                        // Show placeholder if no images or still loading
                                        width: double
                                            .infinity, // Take available width
                                        margin: const EdgeInsets.only(
                                          right: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Center(
                                          child: _isLoading
                                              ? const CircularProgressIndicator(
                                                  color: Colors.white54,
                                                )
                                              : const Icon(
                                                  Icons.hide_image_outlined,
                                                  color: Colors.white70,
                                                  size: 40,
                                                ),
                                        ),
                                      )
                                    : ListView.builder(
                                        // Use ListView.builder for fetched images
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _propertyImageUrls.length,
                                        itemBuilder: (context, index) {
                                          return Container(
                                            width: 160,
                                            margin: const EdgeInsets.only(
                                              right: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(
                                                0.2,
                                              ), // Background while loading
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              image: DecorationImage(
                                                image: NetworkImage(
                                                  _propertyImageUrls[index],
                                                ),
                                                // Use NetworkImage
                                                fit: BoxFit.cover,
                                                // Optional: Add error builder for NetworkImage
                                                onError: (exception, stackTrace) {
                                                  print(
                                                    "Error loading image URL ${_propertyImageUrls[index]}: $exception",
                                                  );
                                                  // Optionally return a placeholder widget here too
                                                },
                                              ),
                                            ),
                                            // Removed overlay icon from original example
                                          );
                                        },
                                      ),
                              ),
                              const SizedBox(height: 30),
                              // Keep spacing
                              // ---------- About Property (Display fetched data) ----------
                              _infoContainer("About Property", [
                                _infoRow(
                                  Icons.home,
                                  widget.propertyDetails['roomType'] ?? 'N/A',
                                ),
                                _infoRow(
                                  Icons.location_on,
                                  widget.propertyDetails['location'] ?? 'N/A',
                                ),
                                _infoRow(
                                  Icons.attach_money,
                                  "₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                                ),
                                _infoRow(
                                  Icons.people,
                                  "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                                ), // Slightly clearer text
                              ]),
                              const SizedBox(height: 25),
                              // Keep spacing
                              // ---------- Contact Section (Display fetched data) ----------
                              _infoContainer("Contact Details", [
                                _infoRow(
                                  Icons.phone,
                                  _landlordPhoneNumber ?? 'Not Available',
                                ),
                                _infoRow(
                                  Icons.email,
                                  _landlordEmail ?? 'Not Available',
                                ),
                              ]),
                              const SizedBox(height: 25),

                              // Keep spacing
                              const SizedBox(height: 35),
                              // Keep spacing
                              // ---------- Reviews Section (Keep original dummy data) ----------
                              const Text(
                                "Reviews",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Keep style
                              const SizedBox(height: 10),
                              // Keep spacing
                              ...dummyReviews.map((review) {
                                // Keep original review display structure
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    // Keep original review content structure
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: Colors.orange
                                                .withOpacity(0.8),
                                            child: Text(
                                              review['name'][0],
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                review['name'],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Row(
                                                children: List.generate(
                                                  5,
                                                  (index) => Icon(
                                                    index < review['rating']
                                                        ? Icons.star
                                                        : Icons.star_border,
                                                    size: 18,
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Text(
                                            review['date'],
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        review['comment'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 40),
                              // Keep spacing
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

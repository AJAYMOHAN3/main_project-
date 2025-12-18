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
class LandlordProfilePage extends StatefulWidget {
  final VoidCallback onBack;// Assuming this is passed in

  const LandlordProfilePage({super.key, required this.onBack});

  @override
  _LandlordProfilePageState createState() => _LandlordProfilePageState();
}

class _LandlordProfilePageState extends State<LandlordProfilePage> {
  // --- State variables ---
  List<DocumentField> userDocuments = [DocumentField()];
  List<PropertyCard> propertyCards = [
    PropertyCard(documents: [DocumentField()]),
  ];
  // List<XFile> houseImages = []; // REMOVED Global list
  bool _isUploadingAll = false;
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
  // Removed global image picker instance

  // Dummy tenant reviews remain
  final List<Map<String, dynamic>> tenantReviews = [
    {
      "tenant": "John Doe",
      "rating": 5,
      "comment": "Great landlord! Very responsive and cooperative.",
    },
    {
      "tenant": "Emma Wilson",
      "rating": 4,
      "comment": "Nice experience overall. The property was well maintained.",
    },
    {
      "tenant": "Michael Smith",
      "rating": 5,
      "comment": "Best renting experience ever. Highly recommend!",
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLandlordData();
  }

  Future<void> _fetchLandlordData() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // Fetch Name
    try {
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(uid)
          .get();
      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('fullName')) {
          setState(() {
            _landlordName = data['fullName'] as String?;
          });
        }
      }
    } catch (e) {
      print("Error fetching landlord name: $e");
    }
    // Fetch Profile Picture URL
    try {
      ListResult result = await FirebaseStorage.instance
          .ref('$uid/profile_pic/')
          .list(const ListOptions(maxResults: 1));
      if (result.items.isNotEmpty && mounted) {
        String url = await result.items.first.getDownloadURL();
        setState(() {
          _profilePicUrl = url;
        });
      } else {
        print("No profile picture found in storage.");
      }
    } catch (e) {
      print("Error fetching profile picture: $e");
    }
  }

  @override
  void dispose() {
    for (var card in propertyCards) {
      card.dispose();
    }
    super.dispose();
  }

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

  // --- MODIFIED: Function to pick images FOR A SPECIFIC PROPERTY ---
  Future<void> _pickHouseImages(int propertyIndex) async {
    // Check bounds
    if (propertyIndex < 0 || propertyIndex >= propertyCards.length) return;

    final ImagePicker picker = ImagePicker(); // Create picker instance locally
    final List<XFile> pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty && mounted) {
      setState(() {
        // Add picked images to the specific property card's list
        propertyCards[propertyIndex].houseImages.addAll(pickedFiles);
      });
    }
  }

  Future<String?> _uploadFileToStorage(File file, String storagePath) async {
    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print("Uploaded ${file.path} to $storagePath. URL: $downloadUrl");
      return downloadUrl;
    } catch (e) {
      print("Error uploading file $storagePath: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload ${storagePath.split('/').last}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  void _resetFormState() {
    setState(() {
      userDocuments = [DocumentField()];
      for (var card in propertyCards) {
        card.dispose();
      }
      propertyCards = [
        PropertyCard(documents: [DocumentField()]),
      ]; // Creates new cards, implicitly clearing images
      _isUploadingAll = false;
    });
    print("--- Form state reset ---");
  }

  Future<void> _uploadAllData() async {
    if (_isUploadingAll) return;

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not logged in'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isUploadingAll = true;
    });
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Text('Uploading all data Please wait'),
        duration: Duration(minutes: 5),
      ),
    );

    bool uploadErrorOccurred = false;
    List<String> userDocUrls = [];
    List<Map<String, dynamic>> propertiesData = [];

    try {
      // 1. Upload User Documents
      print("--- Uploading User Documents ---");
      for (int i = 0; i < userDocuments.length; i++) {
        DocumentField docField = userDocuments[i];
        if (docField.selectedDoc != null && docField.pickedFile != null) {
          String fileName = docField.selectedDoc!;
          String path = '$uid/user_docs/$fileName';
          String? url = await _uploadFileToStorage(docField.pickedFile!, path);
          if (url != null) {
            userDocUrls.add(url);
            docField.downloadUrl = url;
          } else {
            uploadErrorOccurred = true;
          }
        } else if (docField.selectedDoc != null ||
            docField.pickedFile != null) {
          print("Skipping incomplete user document at index $i.");
          // uploadErrorOccurred = true; // Optional: Treat incomplete as error
          // throw Exception("Please pick a file for selected user document '${docField.selectedDoc ?? '...'}'");
        } else {
          print("Skipping empty user document row at index $i.");
        }
      }
      print("--- Finished User Documents ---");

      // 2. Upload Property Documents, Images and Collect Property Data
      print("--- Uploading Property Data, Documents & Images ---");
      for (int i = 0; i < propertyCards.length; i++) {
        PropertyCard card = propertyCards[i];
        List<String> propertyDocUrls = [];
        List<String> currentPropertyImageUrls =
        []; // List for this property's images
        String propertyFolderName = 'property${i + 1}';

        // Upload property docs
        for (int j = 0; j < card.documents.length; j++) {
          DocumentField docField = card.documents[j];
          if (docField.selectedDoc != null && docField.pickedFile != null) {
            String fileName = docField.selectedDoc!;
            String path =
                '$uid/$propertyFolderName/$fileName'; // Docs still go in property folder root
            String? url = await _uploadFileToStorage(
              docField.pickedFile!,
              path,
            );
            if (url != null) {
              propertyDocUrls.add(url);
              docField.downloadUrl = url;
            } else {
              uploadErrorOccurred = true;
            }
          } else if (docField.selectedDoc != null ||
              docField.pickedFile != null) {
            print(
              "Skipping incomplete property document at index $j for property $i.",
            );
          } else {
            print(
              "Skipping empty property document row at index $j for property $i.",
            );
          }
        }

        // --- Upload house images for THIS property ---
        print("--- Uploading House Images for Property ${i + 1} ---");
        if (card.houseImages.isNotEmpty) {
          for (int k = 0; k < card.houseImages.length; k++) {
            XFile imageFile = card.houseImages[k];
            String imgFileName =
                'house_image_$k.${imageFile.path.split('.').last}';
            // --- UPDATED PATH: uid/propertyX/images/imagename ---
            String imgPath = '$uid/$propertyFolderName/images/$imgFileName';
            String? imgUrl = await _uploadFileToStorage(
              File(imageFile.path),
              imgPath,
            );
            if (imgUrl != null) {
              currentPropertyImageUrls.add(imgUrl);
            } else {
              uploadErrorOccurred = true;
            }
          }
        } else {
          print("--- No house images to upload for Property ${i + 1} ---");
        }
        print("--- Finished House Images for Property ${i + 1} ---");

        // Collect details including the image URLs for this property
        propertiesData.add({
          'roomType': card.roomTypeController.text.trim(),
          'location': card.locationController.text.trim(),
          'rent': card.rentController.text.trim(),
          'maxOccupancy': card.maxOccupancyController.text.trim(),
          'documentUrls': propertyDocUrls,
          'houseImageUrls': currentPropertyImageUrls, // Add image URLs here
        });
      }
      print("--- Finished Property Data, Documents & Images ---");

      // 3. Upload House Images (REMOVED - now handled per property)

      // 4. Save to Firestore (Structure now includes image URLs per property)
      if (!uploadErrorOccurred) {
        print("--- Saving data to Firestore collection 'house' doc '$uid' ---");
        await FirebaseFirestore.instance.collection('house').doc(uid).set({
          'properties':
          propertiesData, // This list now contains image URLs within each map
          // 'houseImageUrls': houseImageUrls, // REMOVED top-level list
          'userDocumentUrls': userDocUrls,
        }, SetOptions(merge: true));
        print("--- Firestore set SUCCEEDED ---");

        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('All data uploaded successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _resetFormState(); // Reset form state on success
      } else {
        print("--- Firestore save skipped due to upload errors ---");
        throw Exception('Some file uploads failed Check logs');
      }
    } catch (e) {
      print("--- _uploadAllData FAILED: $e ---");
      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              'Upload failed ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAll = false;
        });
      }
    }
  }
  // --- END FINAL UPLOAD FUNCTION ---

  @override
  Widget build(BuildContext context) {
    // --- UI CHANGES MINIMIZED, MAINLY REMOVING/MOVING IMAGE SECTION ---
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
            const TwinklingStarBackground(),
            SafeArea(
              minimum: EdgeInsets.zero,
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
                            child: _profilePicUrl == null
                                ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.deepPurple,
                            )
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _landlordName ?? "Landlord Name",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
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
                            "Validate Property",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: propertyCards.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildPropertyCard(
                                i,
                              ), // This now includes house images section internally
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                propertyCards.add(
                                  PropertyCard(documents: [DocumentField()]),
                                );
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Property",
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // --- REMOVED Standalone House Images Section ---

                          // --- FINAL UPLOAD BUTTON (MOVED HERE) ---
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isUploadingAll
                                  ? null
                                  : _uploadAllData,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                disabledBackgroundColor: Colors.grey.shade600,
                              ),
                              child: _isUploadingAll
                                  ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                                  : const Text(
                                "SAVE & UPLOAD ALL",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40), // Space after button
                          // --- END FINAL UPLOAD BUTTON ---
                          Text(
                            "Tenant Reviews",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            itemCount: tenantReviews.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final review = tenantReviews[index];
                              // --- Original Tenant Review Card ---
                              return Card(
                                color: Colors.white.withOpacity(0.08),
                                margin: const EdgeInsets.symmetric(
                                  vertical: 6,
                                  horizontal: 4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.person,
                                            color: Colors.white70,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            review["tenant"],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: List.generate(
                                          review["rating"],
                                              (i) => const Icon(
                                            Icons.star,
                                            color: Colors.amber,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        review["comment"],
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                              // --- End Original Tenant Review Card ---
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
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
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
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                File? picked = await _pickDocument();
                if (picked != null) {
                  setState(() => docField.pickedFile = picked);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                disabledBackgroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text(
                "Pick File",
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

  // --- UPDATED PROPERTY CARD BUILDER (Includes House Images section) ---
  Widget _buildPropertyCard(int index) {
    final property = propertyCards[index];

    return GlassmorphismContainer(
      opacity: 0.12,
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              const Text(
                "Property Details & Validation",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                tooltip: "Remove this property card",
                onPressed: () {
                  property.dispose();
                  setState(() => propertyCards.removeAt(index));
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: property.roomTypeController,
            hintText: "Room Type (e.g., 1BHK, 2BHK)",
          ),
          const SizedBox(height: 10),
          CustomTextField(
            controller: property.locationController,
            hintText: "Location (Area/Street)",
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: property.rentController,
                  hintText: "Rent Amount",
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomTextField(
                  controller: property.maxOccupancyController,
                  hintText: "Max Occupancy",
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            "Property Documents:",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 5),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: property.documents
                .asMap()
                .entries
                .map((entry) => _buildPropertyDocField(index, entry.key))
                .toList(),
          ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  property.documents.add(DocumentField());
                });
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                "Add Document",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
            ),
          ),

          // --- ADDED House Images Section WITHIN Property Card ---
          const SizedBox(height: 20),
          const Text("House Images:", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          if (property.houseImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.houseImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, imgIndex) {
                  final imageFile = property.houseImages[imgIndex];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(imageFile.path),
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 100,
                                height: 100,
                                color: Colors.white12,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: 50,
                                ),
                              ),
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              property.houseImages.removeAt(imgIndex);
                            });
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          else
            const Text(
              "No images added for this property yet.",
              style: TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 10),
          Center(
            child: ElevatedButton.icon(
              onPressed: () => _pickHouseImages(
                index,
              ), // Call image picker for THIS property
              icon: const Icon(Icons.add_a_photo, color: Colors.white),
              label: const Text(
                "Add Image",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
              ),
            ),
          ),

          // --- END House Images Section ---
        ],
      ),
    );
  }

  Widget _buildPropertyDocField(int propIndex, int docIndex) {
    final property = propertyCards[propIndex];
    final docField = property.documents[docIndex];
    final selectedDocs = property.documents
        .map((e) => e.selectedDoc)
        .whereType<String>()
        .toList();
    final availableOptions = propertyDocOptions
        .where(
          (doc) => !selectedDocs.contains(doc) || doc == docField.selectedDoc,
    )
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                  .map((doc) => DropdownMenuItem(value: doc, child: Text(doc)))
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
                docField.pickedFile!.path.split('/').last,
                style: const TextStyle(color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.white54),
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: docField.selectedDoc == null
                  ? null
                  : () async {
                File? picked = await _pickDocument();
                if (picked != null) {
                  setState(() => docField.pickedFile = picked);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                disabledBackgroundColor: Colors.grey.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text(
                "Pick File",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document",
            onPressed: () {
              setState(() {
                property.documents.removeAt(docIndex);
              });
            },
          ),
        ],
      ),
    );
  }
} // End of _LandlordProfilePageState

class RequestsPage extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage({super.key, required this.onBack});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  final List<Map<String, String>> pendingRequests = [
    {"name": "John Doe", "property": "Sunset Apartments"},
    {"name": "Emma Wilson", "property": "Greenwood Villa"},
    {"name": "Michael Smith", "property": "Oceanview Residences"},
  ];

  final List<Map<String, String>> acceptedRequests = [];

  void _handleAction(
      BuildContext context,
      Map<String, String> tenant,
      bool accept,
      ) async {
    final action = accept ? "accept" : "decline";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E2A47),
        title: Text(
          "Confirm $action",
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          "Are you sure you want to $action ${tenant['name']}'s request?",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              action.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        pendingRequests.remove(tenant);
        if (accept) acceptedRequests.add(tenant);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background layers
          Container(color: const Color(0xFF141E30)),
          const TwinklingStarBackground(),

          SafeArea(
            child: SingleChildScrollView(
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

                  // Pending Requests List
                  ...pendingRequests.map(
                        (tenant) => Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        title: Text(
                          tenant["name"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          tenant["property"]!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Tenantsearch_ProfilePage(
                                tenantName: tenant["name"]!,
                                propertyName: tenant["property"]!,
                                onBack: () => Navigator.pop(context),
                              ),
                            ),
                          );
                        },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () =>
                                  _handleAction(context, tenant, true),
                              child: const Text("Accept"),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () =>
                                  _handleAction(context, tenant, false),
                              child: const Text("Decline"),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Accepted Requests Section
                  if (acceptedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Accepted Requests",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...acceptedRequests.map(
                          (tenant) => Card(
                        color: Colors.green.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            tenant["property"]!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => Tenantsearch_ProfilePage(
                                  tenantName: tenant["name"]!,
                                  propertyName: tenant["property"]!,
                                  onBack: () => Navigator.pop(context),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
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
        'title': 'Privacy & Security',
        'icon': Icons.security,
        'color': Colors.purple,
        'action': (BuildContext context) => print('Navigate to Privacy'),
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
    // Removed email and address controllers

    // Variables for image picking and loading state need to be managed within StatefulBuilder
    XFile? _pickedImageFile;
    bool _isUpdating = false;

    // --- Pre-fetch current data (Cannot be done easily in static function without passing data) ---
    // --- User will have to re-type existing values or logic needs adjustment ---

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
                      // --- Image Picking Logic ---
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
                      // --- TODO: Fetch and display current image here if desired, requires passing URL or fetching ---
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
                  // Email and Address fields removed as requested
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
                    // 1. Upload Image if picked
                    if (_pickedImageFile != null) {
                      print("Uploading profile picture...");
                      // Path: uid/profile_pic/profile_image.jpg (overwrites previous)
                      String filePath =
                          '$uid/profile_pic/profile_image.jpg';
                      Reference storageRef = FirebaseStorage.instance
                          .ref()
                          .child(filePath);
                      UploadTask uploadTask = storageRef.putFile(
                        File(_pickedImageFile!.path),
                      );
                      await uploadTask; // Wait for upload to complete
                      print("Profile picture uploaded successfully.");
                      // imageUrl = await snapshot.ref.getDownloadURL(); // Get URL only if needed
                    }

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

                    // 3. Update Firestore if there's data to update
                    if (updateData.isNotEmpty) {
                      print(
                        "Updating Firestore for UID: $uid with data: $updateData",
                      );
                      // Assuming user is landlord based on function context
                      await FirebaseFirestore.instance
                          .collection('landlord')
                          .doc(uid)
                          .update(updateData);
                      print("Firestore update successful.");

                      // 4. Update unique UserId collection IF profileName changed
                      // Warning: This only adds, doesn't check uniqueness thoroughly again or remove old.
                      if (newProfileName.isNotEmpty) {
                        // Optional: Re-check uniqueness before adding for robustness
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
                          // Note: Does not remove the old profile name.
                        } else {
                          print(
                            "New profile name might already exist (race condition/old data?). Not adding again.",
                          );
                          // Decide handling: ignore (current), or throw error?
                          // throw Exception('Profile name already exists');
                        }
                      }
                    } else if (_pickedImageFile != null) {
                      print(
                        "Only profile picture was updated, skipping Firestore field update.",
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
                    // Keep dialog open on error
                  } finally {
                    // Ensure loading state is reset
                    if (navigator.context.mounted) {
                      stfSetState(() {
                        _isUpdating = false;
                      });
                    }
                  }
                },
                child:
                _isUpdating // Show loading indicator or text
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

// -------------------- AGREEMENTS PAGE --------------------
class AgreementsPage extends StatelessWidget {
  final VoidCallback onBack;
  const AgreementsPage({super.key, required this.onBack});

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
                  onBack: onBack,
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
  final int propertyIndex; // Index of the property for image path

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
                                    "Location Unknown", // Fetch from passed details
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Send Request Button (Keep original) ----------
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Request sent to the landlord!',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              // Add actual request sending logic here if needed
                            },
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
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Property Photos ----------
                        const Text(
                          "Property Photos",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ), // Keep style
                        const SizedBox(height: 10), // Keep spacing
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
                                    ), // Use NetworkImage
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
                        const SizedBox(height: 30), // Keep spacing
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
                        const SizedBox(height: 25), // Keep spacing
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
                        const SizedBox(height: 25), // Keep spacing
                        // ---------- Write a Review Button (Keep original) ----------
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
                        const SizedBox(height: 35), // Keep spacing
                        // ---------- Reviews Section (Keep original dummy data) ----------
                        const Text(
                          "Reviews",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ), // Keep style
                        const SizedBox(height: 10), // Keep spacing
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
                        const SizedBox(height: 40), // Keep spacing
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

  // ---------- Helper Widgets (Keep Original) ----------
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

  // --- Review Dialog (Keep Original Dummy Logic) ---
  void _showReviewDialog(BuildContext context) {
    final TextEditingController reviewController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Use dialogContext
        backgroundColor: Colors.black87, // Keep style
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ), // Keep style
        title: const Text(
          "Write a Review",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ), // Keep style
        content: TextField(
          // Keep style
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
          // Keep style
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Use dialogContext
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Review submitted: ${reviewController.text}"),
                ),
              ); // Keep logic
              // Add actual review saving logic here
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

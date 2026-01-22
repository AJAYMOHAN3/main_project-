import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:main_project/main.dart';
import 'package:main_project/tenant/tenant.dart';

class LandlordsearchProfilePage2 extends StatefulWidget {
  final String landlordUid; // Landlord's UID from search
  final Map<String, dynamic> propertyDetails; // Specific property details
  final int propertyIndex; // Index of the property for image path

  const LandlordsearchProfilePage2({
    super.key,
    required this.landlordUid,
    required this.propertyDetails,
    required this.propertyIndex,
  });

  @override
  LandlordsearchProfilePage2State createState() =>
      LandlordsearchProfilePage2State();
}

class LandlordsearchProfilePage2State
    extends State<LandlordsearchProfilePage2> {
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
      //print(
      //"Fetching landlord details for UID: ${widget.landlordUid}",
      //); // Debug print
      DocumentSnapshot landlordDoc = await FirebaseFirestore.instance
          .collection('landlord')
          .doc(widget.landlordUid)
          .get();

      if (landlordDoc.exists && mounted) {
        var data = landlordDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          //print("Landlord data found: $data"); // Debug print
          setState(() {
            _landlordName = data['fullName'] as String? ?? 'Name Not Available';
            _landlordPhoneNumber = data['phoneNumber'] as String?;
            _landlordEmail = data['email'] as String?;
            // Assuming profile pic URL isn't stored in landlord doc, fetch from storage next
          });
        } else {
          //print("Landlord document data is null."); // Debug print
          if (mounted) {
            setState(() => _landlordName = 'Landlord Data Not Found');
          }
        }
      } else {
        //print(
        //"Landlord document not found for UID: ${widget.landlordUid}",
        //); // Debug print
        if (mounted) setState(() => _landlordName = 'Landlord Not Found');
      }

      // 2. Fetch Landlord Profile Pic from Storage
      //print("Fetching landlord profile picture..."); // Debug print
      try {
        ListResult profilePicResult = await FirebaseStorage.instance
            .ref('${widget.landlordUid}/profile_pic/')
            .list(const ListOptions(maxResults: 1));
        if (profilePicResult.items.isNotEmpty && mounted) {
          String url = await profilePicResult.items.first.getDownloadURL();
          //print("Profile picture URL fetched: $url"); // Debug print
          setState(() {
            _landlordProfilePicUrl = url;
          });
        } else {
          //print("No profile picture found in storage."); // Debug print
        }
      } catch (storageError) {
        //print(
        //"Error fetching landlord profile pic: $storageError",
        //); // Keep default icon
      }

      // 3. Fetch Property Images from Storage
      List<String> imageUrls = [];
      String propertyFolderName =
          'property${widget.propertyIndex + 1}'; // property1, property2 etc.
      String imageFolderPath =
          '${widget.landlordUid}/$propertyFolderName/images/';
      //print("Fetching property images from: $imageFolderPath"); // Debug print
      try {
        ListResult imageListResult = await FirebaseStorage.instance
            .ref(imageFolderPath)
            .listAll();
        //print(
        //"Found ${imageListResult.items.length} images in storage.",
        //); // Debug print
        for (var item in imageListResult.items) {
          String url = await item.getDownloadURL();
          imageUrls.add(url);
        }
        if (mounted) {
          //print(
          //"Setting ${imageUrls.length} property image URLs.",
          //); // Debug print
          setState(() {
            _propertyImageUrls = imageUrls;
          });
        }
      } catch (storageError) {
        //print(
        //"Error fetching property images from $imageFolderPath: $storageError",
        //); // Will show placeholders
      }
    } catch (e) {
      //print("Error fetching landlord/property data: $e");
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
        //print(
        //"Finished fetching data, setting isLoading = false.",
        //); // Debug print
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget infoContainer(String title, List<Widget> children) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
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

    Widget infoRow(IconData icon, String text) {
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
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.3,
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
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
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
                                          color: Colors.white.withValues(
                                            alpha: 0.2,
                                          ),
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
                                              color: Colors.white.withValues(
                                                alpha: 0.2,
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
                                                  //print(
                                                  //"Error loading image URL ${_propertyImageUrls[index]}: $exception",
                                                  //);
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
                              infoContainer("About Property", [
                                infoRow(
                                  Icons.home,
                                  widget.propertyDetails['roomType'] ?? 'N/A',
                                ),
                                infoRow(
                                  Icons.location_on,
                                  widget.propertyDetails['location'] ?? 'N/A',
                                ),
                                infoRow(
                                  Icons.attach_money,
                                  "₹${widget.propertyDetails['rent'] ?? 'N/A'} / month",
                                ),
                                infoRow(
                                  Icons.people,
                                  "Max Occupancy: ${widget.propertyDetails['maxOccupancy'] ?? 'N/A'}",
                                ), // Slightly clearer text
                              ]),
                              const SizedBox(height: 25),
                              // Keep spacing
                              // ---------- Contact Section (Display fetched data) ----------
                              infoContainer("Contact Details", [
                                infoRow(
                                  Icons.phone,
                                  _landlordPhoneNumber ?? 'Not Available',
                                ),
                                infoRow(
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
                                    color: Colors.white.withValues(alpha: 0.1),
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
                                                .withValues(alpha: 0.8),
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
                              }),
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

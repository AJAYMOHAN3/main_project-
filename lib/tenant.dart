
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

import 'main.dart';
import 'landlord.dart';




class TenantHomePage extends StatefulWidget {
  const TenantHomePage({super.key});

  @override
  _TenantHomePageState createState() => _TenantHomePageState();
}

class _TenantHomePageState extends State<TenantHomePage> {
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
  Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      _handleCustomBack(); // Use the custom tab history logic
      return false; // prevent default pop
    }
    return true; // allow app exit
  }

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
    return WillPopScope(
      onWillPop: _onWillPop,
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
// Assuming necessary imports are present: dart:io, dart:ui, flutter/material.dart,
// firebase_auth, cloud_firestore, firebase_storage, file_picker, image_picker
// Also assuming helper classes DocumentField, HomeRental, AnimatedGradientBackground,
// CustomTopNavBar, GlassmorphismContainer are defined correctly elsewhere,
// and DocumentField now includes a 'File? pickedFile' field.

class TenantProfilePage extends StatefulWidget {
  final VoidCallback onBack; // callback for back button

  const TenantProfilePage({super.key, required this.onBack});

  @override
  _TenantProfilePageState createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  List<DocumentField> userDocuments = [DocumentField()];
  final List<String> userDocOptions = [
    "Aadhar",
    "PAN",
    "License",
    "Birth Certificate",
  ];

  // Dummy rented homes data remains
  List<HomeRental> rentedHomes = [
    HomeRental(name: "Sea View Apartment", address: "Beach Road, Goa"),
    HomeRental(name: "Sunshine Villa", address: "MG Road, Bangalore"),
  ];

  // --- State variables for fetched data ---
  String? _tenantName;
  String? _profilePicUrl;
  bool _isLoadingProfile = true; // Loading indicator for initial fetch

  // --- initState to fetch data ---
  @override
  void initState() {
    super.initState();
    _fetchTenantData();
  }

  Future<void> _fetchTenantData() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted)
        setState(() => _isLoadingProfile = false); // Stop loading if no user
      return;
    }

    // Fetch Name from 'tenant' collection
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
    } catch (e) {
      print("Error fetching tenant name: $e");
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
        print("No profile picture found for tenant.");
      }
    } catch (e) {
      print("Error fetching tenant profile picture: $e");
    } finally {
      if (mounted)
        setState(
              () => _isLoadingProfile = false,
        ); // Stop loading after fetching attempts
    }
  }

  // --- Function to pick a document file ---
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

  // --- Function to upload a single file to Firebase Storage ---
  Future<String?> _uploadFileToStorage(File file, String storagePath) async {
    // Show uploading snackbar immediately
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Uploading ${storagePath.split('/').last}...'),
        duration: const Duration(minutes: 1),
      ),
    );

    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print("Uploaded ${file.path} to $storagePath. URL: $downloadUrl");

      scaffoldMessenger.hideCurrentSnackBar(); // Hide uploading message
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('${storagePath.split('/').last} uploaded successfully'),
          backgroundColor: Colors.green,
        ),
      );
      return downloadUrl;
    } catch (e) {
      print("Error uploading file $storagePath: $e");
      scaffoldMessenger.hideCurrentSnackBar(); // Hide uploading message
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

    File? pickedFile = await _pickDocument();
    if (pickedFile != null) {
      // Update state to show picked file immediately (optional but good UX)
      setState(() {
        docField.pickedFile = pickedFile;
      });

      // Get UID for path
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Not logged in'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Construct path and upload
      String fileName = docField.selectedDoc!; // Use selected name
      // Add file extension - robustly handle cases where original name might not have one
      String extension = pickedFile.path.split('.').last;
      if (extension.isNotEmpty && extension.length <= 4) {
        // Basic check for valid extension
        fileName += '.$extension';
      }
      String storagePath = '$uid/user_docs/$fileName';

      // Upload the file
      String? downloadUrl = await _uploadFileToStorage(pickedFile, storagePath);
      if (downloadUrl != null && mounted) {
        setState(() {
          docField.downloadUrl = downloadUrl; // Store URL if needed
        });
      } else if (downloadUrl == null && mounted) {
        // If upload failed, maybe clear the picked file?
        // setState(() {
        //   docField.pickedFile = null;
        // });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onBack();
        return false; // prevent default back navigation
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const AnimatedGradientBackground(), // Keep original background
            SafeArea(
              child: Column(
                children: [
                  // ---------- TOP NAV BAR ----------
                  CustomTopNavBar(
                    // Keep original Top Nav
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack,
                  ),

                  // ---------- SCROLLABLE CONTENT ----------
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

                          // ---------- UPDATED PROFILE PIC ----------
                          CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white12, // Placeholder bg
                            backgroundImage: _profilePicUrl != null
                                ? NetworkImage(_profilePicUrl!)
                                : null,
                            child:
                            _isLoadingProfile // Show loading indicator while fetching
                                ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                                : (_profilePicUrl == null
                                ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.deepPurple,
                            )
                                : null), // Show icon if loading done and no URL
                          ),
                          const SizedBox(height: 20),

                          // ---------- UPDATED PROFILE DETAILS ----------
                          Text(
                            _tenantName ??
                                "Tenant Name", // Display fetched name or default
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                            ),
                          ),
                          Text(
                            // Keep original text format
                            "Agreements for ${rentedHomes.length} Homes",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 30),

                          // ---------- VALIDATE USER ----------
                          Text(
                            // Keep original style
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),

                          ListView.builder(
                            // Keep original structure
                            itemCount: userDocuments.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildUserDocField(
                                i,
                              ), // Calls updated build method
                            ),
                          ),

                          const SizedBox(height: 20),

                          ElevatedButton.icon(
                            // Keep original Add button
                            onPressed: () {
                              setState(() {
                                userDocuments.add(DocumentField());
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text(
                              "Add Document",
                              style: TextStyle(color: Colors.white),
                            ), // Text style for label added
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                            ),
                          ),

                          const SizedBox(height: 40),

                          // ---------- RENTED HOMES (Keep Original Dummy Data) ----------
                          Text(
                            // Keep original style
                            "My Rented Homes",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ListView.builder(
                            // Keep original structure
                            itemCount: rentedHomes.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final home = rentedHomes[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GlassmorphismContainer(
                                  // Keep original style
                                  opacity: 0.1,
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.home,
                                      color: Colors.orange,
                                    ),
                                    title: Text(
                                      home.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      home.address,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 40),

                          // ---------- LANDLORD REVIEWS (Keep Original Dummy Data) ----------
                          Text(
                            // Keep original style
                            "Landlord Reviews",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            // Keep original structure
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

                          const SizedBox(
                            height: 60,
                          ), // Keep original bottom padding
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

  // ---------- HELPER WIDGET FOR REVIEWS (Keep Original) ----------
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

  // ---------------- UPDATED USER DOCUMENT FIELD ----------------
  Widget _buildUserDocField(int index) {
    final docField = userDocuments[index]; // Use the object from the list
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
      // Keep original style
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              // Keep original style
              isExpanded: true,
              value: docField.selectedDoc,
              hint: const Text(
                "Select Document",
                style: TextStyle(color: Colors.white),
              ),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              underline:
              Container(), // Add this to remove default underline if needed
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

          // --- Show file name or Upload button ---
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
              tooltip: "Clear selected file",
              onPressed: () => setState(() => docField.pickedFile = null),
            ),
          ] else ...[
            ElevatedButton(
              // Keep original style
              // --- Call pick and upload function ---
              onPressed: () =>
                  _pickAndUploadUserDocument(index), // Pass the index
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: const Text(
                "Upload",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
          const SizedBox(width: 8), // Add spacing before remove icon if needed
          IconButton(
            // Keep original remove row button
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Remove this document row",
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
        ],
      ),
    );
  }
} // End of _TenantProfilePageState

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
  final int _numberOfStars = 30; // Density
  late final List<_ShootingStar> _stars;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _stars = List.generate(
      _numberOfStars,
          (_) => _ShootingStar.random(_random),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final bgColor =
        Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            const Color(0xFF01020A);

    return SizedBox.expand(
      child: Container(
        color: bgColor,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size(screenWidth, screenHeight),
              painter: _ShootingStarPainter(
                stars: _stars,
                progress: _controller.value,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// Shooting star model
class _ShootingStar {
  Offset start;
  Offset end;
  double size;
  double speed;

  _ShootingStar({
    required this.start,
    required this.end,
    required this.size,
    required this.speed,
  });

  factory _ShootingStar.random(Random random) {
    final startX = random.nextDouble();
    final startY = random.nextDouble();
    final endX =
        startX + (-0.2 + random.nextDouble() * 0.4); // horizontal variation
    final endY = startY + 0.2 + random.nextDouble() * 0.3; // downward movement

    return _ShootingStar(
      start: Offset(startX, startY),
      end: Offset(endX, endY),
      size: 1.5 + random.nextDouble() * 2.0,
      speed: 0.5 + random.nextDouble(),
    );
  }
}

// Painter
class _ShootingStarPainter extends CustomPainter {
  final List<_ShootingStar> stars;
  final double progress;
  final double screenWidth;
  final double screenHeight;

  _ShootingStarPainter({
    required this.stars,
    required this.progress,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (var star in stars) {
      final starProgress = (progress * star.speed) % 1.0;

      final x =
          lerpDouble(star.start.dx, star.end.dx, starProgress)! * screenWidth;
      final y =
          lerpDouble(star.start.dy, star.end.dy, starProgress)! * screenHeight;

      // Calculate movement direction vector
      final dx = star.end.dx - star.start.dx;
      final dy = star.end.dy - star.start.dy;
      final length = sqrt(dx * dx + dy * dy);
      final direction = Offset(dx / length, dy / length);

      // Trail opposite to movement
      final trailLength = star.size * 8; // visible length
      final trailEnd = Offset(
        x - direction.dx * trailLength * 10, // scaled for visible trail
        y - direction.dy * trailLength * 10,
      );

      final trailPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(0.0),
            Colors.white.withOpacity(0.6),
          ],
        ).createShader(Rect.fromPoints(trailEnd, Offset(x, y)))
        ..strokeWidth = star.size
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(trailEnd, Offset(x, y), trailPaint);

      // Draw star
      canvas.drawCircle(Offset(x, y), star.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter oldDelegate) => true;
}






class RequestsPage2 extends StatefulWidget {
  final VoidCallback onBack;
  const RequestsPage2({super.key, required this.onBack});

  @override
  State<RequestsPage2> createState() => _RequestsPageState2();
}

class _RequestsPageState2 extends State<RequestsPage2> {
  final List<Map<String, String>> pendingRequests = [
    {"name": "John Doe", "property": "Sunset Apartments"},
    {"name": "Emma Wilson", "property": "Greenwood Villa"},
    {"name": "Michael Smith", "property": "Oceanview Residences"},
  ];

  final List<Map<String, String>> acceptedRequests = [];
  final List<Map<String, String>> rejectedRequests = [];

  void _handleAction(BuildContext context, Map<String, String> tenant, bool accept) async {
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
        if (accept) {
          acceptedRequests.add(tenant);
        } else {
          rejectedRequests.add(tenant);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background same as SearchPage
          const AnimatedGradientBackground(),

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

                  // Pending Requests List with status only
                  ...pendingRequests.map(
                        (tenant) => Card(
                      color: Colors.white.withOpacity(0.1),
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        title: Text(
                          tenant["name"]!,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tenant["property"]!,
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Status: Pending",
                              style: TextStyle(
                                color: Colors.amberAccent,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => Landlordsearch_ProfilePage(
                                landlordUid: "DUMMY_UID",
                                propertyDetails: {
                                  "location": "Unknown",
                                  "roomType": "N/A",
                                  "rent": "N/A",
                                  "maxOccupancy": "N/A",
                                },
                                propertyIndex: 0,
                              ),
                            ),
                          );
                        },

                      ),
                    ),
                  ),

                  // Accepted Requests Section with status
                  if (acceptedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Approved Requests",
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
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenant["property"]!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Status: Approved",
                                style: TextStyle(
                                  color: Colors.lightGreenAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Rejected Requests Section with status
                  if (rejectedRequests.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0, bottom: 10),
                      child: Center(
                        child: Text(
                          "Rejected Requests",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...rejectedRequests.map(
                          (tenant) => Card(
                        color: Colors.red.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            tenant["name"]!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenant["property"]!,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "Status: Rejected",
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
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


// -------------------- SEARCH PAGE --------------------
class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});


  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  Set<Marker> _markers = {};


  final TextEditingController _searchController = TextEditingController();

  // --- MODIFIED: Removed "Location" controller ---
  final Map<String, TextEditingController> _filterControllers = {
    "Price": TextEditingController(),
    "People": TextEditingController(),
  };

  String? _activeFilter;
  bool _showResults = false;
  bool _isLoading = false; // Added loading state
  List<Map<String, dynamic>> _searchResults = []; // To store actual results

  // --- MODIFIED: Removed "Location" suggestions ---
  final Map<String, List<String>> filterSuggestions = {
    "Price": [
      "Below ₹5000",
      "₹5000 - ₹10000",
      "₹10000 - ₹20000",
      "Above ₹20000",
    ],
    "People": ["1 person", "2 people", "3 people", "4+ people"],
  };


  // --- ADDED: Search Function ---
  Future<void> _performSearch() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _showResults = true; // Show results area (will show loading indicator)
      _searchResults = []; // Clear previous results
    });

    // --- MODIFIED: Check if filters are active ---
    final bool isFilterActive =
        _filterControllers["Price"]!.text.isNotEmpty ||
            _filterControllers["People"]!.text.isNotEmpty;

    // --- MODIFIED: Set searchTerm to empty if filters are active ---
    final String searchTerm = isFilterActive
        ? ""
        : _searchController.text.trim().toLowerCase();

    final String priceFilter = _filterControllers["Price"]!.text.trim();
    final String peopleFilter = _filterControllers["People"]!.text.trim();

    print(
      "Performing search with term: '$searchTerm', price: '$priceFilter', people: '$peopleFilter'",
    );

    try {
      QuerySnapshot houseSnapshot = await FirebaseFirestore.instance
          .collection('house')
          .get();
      List<Map<String, dynamic>> results = [];

      print(
        "Fetched ${houseSnapshot.docs
            .length} documents from 'house' collection.",
      );

      for (var doc in houseSnapshot.docs) {
        String landlordUid = doc.id;
        var houseData = doc.data() as Map<String, dynamic>?;

        if (houseData != null &&
            houseData.containsKey('properties') &&
            houseData['properties'] is List) {
          List<dynamic> properties = houseData['properties'];
          print(
            "Processing landlord $landlordUid with ${properties
                .length} properties.",
          );

          for (int i = 0; i < properties.length; i++) {
            var property = properties[i];
            if (property is Map<String, dynamic>) {
              String location = (property['location'] as String? ?? '')
                  .toLowerCase();
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

              print(
                "  Property $i: Loc='$location', Rent='$rentStr', Occ='$occupancyStr', Type='$roomType'",
              );
              print(
                "    Filters: PriceMatch=$priceMatch, PeopleMatch=$peopleMatch. SearchMatch=$searchMatch",
              );

              if (priceMatch && peopleMatch && searchMatch) {
                print(
                  "    MATCH FOUND for property $i of landlord $landlordUid.",
                );
                results.add({
                  'landlordUid': landlordUid,
                  'propertyIndex': i,
                  'displayInfo':
                  '${roomType.isNotEmpty
                      ? roomType
                      : "Property"} - ${property['location'] ??
                      'Unknown Location'}',
                  'propertyDetails': property,
                });
              }
            } else {
              print("  Property $i data is not a Map.");
            }
          }
        } else {
          print(
            "Landlord $landlordUid document data is invalid or missing 'properties' list.",
          );
        }
      }

      print("Search complete. Found ${results.length} matching properties.");

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;

          // --- ADD MARKERS ---
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
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            Landlordsearch_ProfilePage(
                              landlordUid: result['landlordUid'],
                              propertyDetails: result['propertyDetails'],
                              propertyIndex: result['propertyIndex'],
                            ),
                      ),
                    );
                  },
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
      print("Error performing search: $e");
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


  // --- Helper function for Price Filter (Client-side) ---
  bool _checkPriceMatch(String rentStr, String priceFilter) {
    int? rent = int.tryParse(
      rentStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    ); // Extract digits only
    if (rent == null) return false; // Cannot compare if rent is not a number

    switch (priceFilter) {
      case "Below ₹5000":
        return rent < 5000;
      case "₹5000 - ₹10000":
        return rent >= 5000 && rent <= 10000;
      case "₹10000 - ₹20000":
        return rent > 10000 && rent <= 20000; // Corrected lower bound
      case "Above ₹20000":
        return rent > 20000;
      default:
        return true; // No filter if category unknown
    }
  }

  // --- Helper function for People Filter (Client-side) ---
  bool _checkOccupancyMatch(String occupancyStr, String peopleFilter) {
    int? occupancy = int.tryParse(
      occupancyStr.replaceAll(RegExp(r'[^0-9]'), '').trim(),
    ); // Extract digits
    if (occupancy == null) return false;

    switch (peopleFilter) {
      case "1 person":
        return occupancy >= 1; // Allows 1 or more
      case "2 people":
        return occupancy >= 2;
      case "3 people":
        return occupancy >= 3;
      case "4+ people":
        return occupancy >= 4;
      default:
        return true; // No filter if category unknown
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
    final bool isFilterActive = _filterControllers["Price"]!.text.isNotEmpty ||
        _filterControllers["People"]!.text.isNotEmpty;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                // --- TOP SEARCH/FILTER AREA (FIXED LAYOUT with Horizontal Safety) ---
                // Removed SingleChildScrollView here and rely on the outer Column/Expanded structure.
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ensure the CustomTopNavBar respects horizontal bounds
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
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                          softWrap: true,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Filter buttons (Horizontal Scrollable)
                      // The inner SingleChildScrollView handles the overflow for the buttons themselves.
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
                                    color: isActive ? Colors.black : Colors
                                        .white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? Colors.orange.shade300
                                      : Colors.white.withOpacity(0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
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
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // TextField implicitly takes full width of parent Container
                              TextField(
                                controller: _filterControllers[_activeFilter!],
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: "Enter ${_activeFilter!
                                      .toLowerCase()}...",
                                  hintStyle: const TextStyle(
                                      color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.08),
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
                                      (option) =>
                                      ChoiceChip(
                                        label: Text(option),
                                        labelStyle: const TextStyle(
                                            color: Colors.white),
                                        backgroundColor: Colors.white
                                            .withOpacity(0.1),
                                        selectedColor: Colors.orange.shade700,
                                        selected: _filterControllers[_activeFilter!]!
                                            .text == option,
                                        onSelected: (selected) {
                                          setState(() {
                                            _filterControllers[_activeFilter!]!
                                                .text =
                                            selected ? option : '';
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
                            Expanded( // Ensures TextField takes the available space
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: "Search homes, location, type...",
                                  hintStyle: const TextStyle(
                                      color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.white.withOpacity(0.08),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white.withOpacity(0.3)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.orange.shade700),
                                  ),
                                ),
                                onSubmitted: (_) => _performSearch(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Search button has fixed size
                            ElevatedButton(
                              onPressed: _performSearch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade700,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Icon(
                                  Icons.search, color: Colors.white),
                            ),
                          ],
                        ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                // --- END TOP SEARCH/FILTER AREA ---

                // Map + Results area (USES EXPANDED)
                if (_showResults)
                  Expanded(
                    child: Column(
                      children: [
                        // Map with max height
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 300,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: FlutterMap(
                                options: const MapOptions(
                                  initialCenter: LatLng(10.0, 76.0),
                                  initialZoom: 13,
                                ),
                                children: [
                                  // Using working CARTO Voyager tiles
                                  TileLayer(
                                    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager_labels_under/{z}/{x}/{y}{r}.png',
                                    subdomains: const ['a', 'b', 'c', 'd'],
                                    userAgentPackageName: 'com.yourcompany.appname',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Results list
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator(
                              color: Colors.orange))
                              : (_searchResults.isEmpty
                              ? const Center(
                            child: Text(
                              "No homes found matching your criteria.",
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                              : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final result = _searchResults[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          Landlordsearch_ProfilePage(
                                            landlordUid: result['landlordUid'],
                                            propertyDetails: result['propertyDetails'],
                                            propertyIndex: result['propertyIndex'],
                                          ),
                                    ),
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 6),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.home,
                                          color: Colors.orangeAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          result['displayInfo'],
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16),
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right,
                                          color: Colors.white54),
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
          ),
        ],
      ),
    );
  }
}

// -------------------- SETTINGS PAGE --------------------
class SettingsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage2({super.key, required this.onBack});

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
    // Keep controllers for fields being edited
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController =
    TextEditingController(); // Represents profileName (UserId)
    final TextEditingController phoneController = TextEditingController();
    XFile? _pickedImageFile;
    bool _isUpdating = false;


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
                    //String? imageUrl; // Only used locally if needed later

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
                        "Updating Firestore (tenant collection) for UID: $uid with data: $updateData",
                      );
                      // --- UPDATED: Use 'tenant' collection ---
                      await FirebaseFirestore.instance
                          .collection('tenant')
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
                  // Password complexity rules (assuming same as registration)
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
                    // Check user directly
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
  // Assuming this is defined statically within the same class or globally accessible
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
class AgreementsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const AgreementsPage2({super.key, required this.onBack});

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
                  onBack: onBack,
                ),
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
                              color: Colors.white.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
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
                                    color: Colors.white.withOpacity(0.8),
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
                            color: Colors.white.withOpacity(0.9),
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

class Tenantsearch_ProfilePage extends StatelessWidget {
  final String tenantName;
  final String propertyName;
  final VoidCallback onBack;

  const Tenantsearch_ProfilePage({
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
                    onPressed: () {
                      // TODO: Add review popup or form
                    },
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







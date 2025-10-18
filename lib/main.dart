import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';

// Global variable used for the login logic
int role = 0; // 1 for Landlord, 0 for Tenant

void main() {
  runApp(const MyApp());
}

// -------------------- APP ENTRY --------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Homes',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: const LoginPage(),
    );
  }
}

// -------------------- CUSTOM TOP NAV BAR --------------------


class CustomTopNavBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBack;
  final String title;
  final VoidCallback? onBack; // Custom back handler

  const CustomTopNavBar({
    super.key,
    this.showBack = false,
    required this.title,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ---------- LEFT SIDE: Back Button + Branding ----------
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Back Button (Conditional)
                if (showBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 24),
                    padding: EdgeInsets.zero, // Remove extra padding for a tight fit
                    constraints: const BoxConstraints(), // Allow minimal space
                    onPressed: () {
                      // CRITICAL FIX: Use the custom onBack logic
                      if (onBack != null) {
                        onBack!(); // Uses the tab history logic from LandlordHomePage
                      } else if (Navigator.canPop(context)) {
                        Navigator.pop(context); // Fallback for standard routes
                      }
                    },
                  )
                else
                // If no back button, show a placeholder for logo/name to start immediately
                  const SizedBox.shrink(),

                // 2. Logo/Icon
                const SizedBox(width: 8), // Small space after back button
                // NOTE: Using a placeholder icon as the asset path is local
                Image.asset('lib/assets/icon.png', height: 32, errorBuilder: (context, error, stackTrace) {
                  // Fallback icon if asset path is not working
                  return const Icon(Icons.security, color: Colors.white, size: 32);
                }),

                // 3. App Name
                const SizedBox(width: 12),
                const Text(
                  'SECURE HOMES', // App Name
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),

            // ---------- RIGHT SIDE: Spacer (Empty/Optional Action Button) ----------
            const SizedBox.shrink(), // Keeps the mainAxisAlignment: spaceBetween correct
          ],
        ),
      ),
    );
  }
}
// -------------------- LOGIN PAGE --------------------

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF141E30), Color(0xFF243B55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        const InfiniteDAGBackground(),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const CustomTopNavBar(title: '',),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 60.0, horizontal: 16.0),
                    child: const GlassmorphismCard(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------- GLASS CARD LOGIN --------------------

class GlassmorphismCard extends StatelessWidget {
  const GlassmorphismCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          padding: const EdgeInsets.all(30.0),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(25.0),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CustomTextField(hintText: 'Username'),
              const SizedBox(height: 25),
              const CustomTextField(hintText: 'Password', obscureText: true),
              const SizedBox(height: 35),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Navigate to LandlordHomePage or TenantProfilePage
                        if (role == 1) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const LandlordHomePage()),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                const TenantHomePage()),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'LOGIN',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) =>
                          const RoleSelectionDialog(),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blue.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'REGISTER',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              TextButton(
                onPressed: () {},
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    decoration: TextDecoration.underline,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------- ROLE SELECTION DIALOG --------------------

class RoleSelectionDialog extends StatelessWidget {
  const RoleSelectionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Your Role',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const TenantRegistrationPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.teal.withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Register as Tenant',
                        style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                            const LandlordRegistrationPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.indigo.withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Register as Landlord',
                        style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------- TENANT REGISTRATION --------------------
class TenantRegistrationPage extends StatefulWidget {
  const TenantRegistrationPage({super.key});

  @override
  _TenantRegistrationPageState createState() => _TenantRegistrationPageState();
}

class _TenantRegistrationPageState extends State<TenantRegistrationPage> {
  String? _gender;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF141E30), Color(0xFF243B55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const InfiniteDAGBackground(),
          SafeArea(
            child: Column(
              children: [
                const CustomTopNavBar(showBack: true, title: '',),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25.0),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(25.0),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Tenant Registration",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 24),
                                const CustomTextField(hintText: 'Full Name'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Profile Name'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Email'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Phone Number'),
                                const SizedBox(height: 16),
                                const CustomTextField(
                                    hintText: 'Password', obscureText: true),
                                const SizedBox(height: 16),
                                const CustomTextField(
                                    hintText: 'Preferred Location'),
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: 'Gender',
                                  value: _gender,
                                  items: const ['Male', 'Female', 'Other'],
                                  onChanged: (val) {
                                    setState(() {
                                      _gender = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.popUntil(
                                        context, (route) => route.isFirst);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    backgroundColor: Colors.orange.shade700,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    'REGISTER',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

// -------------------- LANDLORD REGISTRATION --------------------
class LandlordRegistrationPage extends StatefulWidget {
  const LandlordRegistrationPage({super.key});

  @override
  _LandlordRegistrationPageState createState() =>
      _LandlordRegistrationPageState();
}

class _LandlordRegistrationPageState extends State<LandlordRegistrationPage> {
  String? _gender;
  String? _houseType;
  final List<String> genders = ['Male', 'Female', 'Other'];
  final List<String> houseTypes = ['Apartment', 'Villa', 'Studio', 'Duplex'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF141E30), Color(0xFF243B55)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const InfiniteDAGBackground(),
          SafeArea(
            child: Column(
              children: [
                const CustomTopNavBar(showBack: true, title: '',),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(25.0),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(25.0),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  "Landlord Registration",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 24),
                                const CustomTextField(hintText: 'Full Name'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Profile Name'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Email'),
                                const SizedBox(height: 16),
                                const CustomTextField(hintText: 'Phone Number'),
                                const SizedBox(height: 16),
                                const CustomTextField(
                                    hintText: 'Password', obscureText: true),
                                const SizedBox(height: 16),
                                const CustomTextField(
                                    hintText: 'House Location'),
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: "Gender",
                                  value: _gender,
                                  items: genders,
                                  onChanged: (val) {
                                    setState(() {
                                      _gender = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 16),
                                DropdownContainer(
                                  label: "House Type",
                                  value: _houseType,
                                  items: houseTypes,
                                  onChanged: (val) {
                                    setState(() {
                                      _houseType = val;
                                    });
                                  },
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.popUntil(
                                        context, (route) => route.isFirst);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    backgroundColor: Colors.orange.shade700,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12)),
                                  ),
                                  child: const Text(
                                    'REGISTER',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
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

// -------------------- DROPDOWN CONTAINER --------------------
class DropdownContainer extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const DropdownContainer({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          hint: Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 16,
            ),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
          ),
          dropdownColor: Colors.white.withOpacity(0.95),
          items: items
              .map((item) => DropdownMenuItem<String>(
            value: item,
            child: Text(
              item,
              style: const TextStyle(color: Colors.black87),
            ),
          ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// -------------------- CUSTOM TEXT FIELD --------------------

class CustomTextField extends StatelessWidget {
  final String hintText;
  final bool obscureText;

  const CustomTextField(
      {super.key, required this.hintText, this.obscureText = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      obscureText: obscureText,
      style: const TextStyle(color: Colors.black87),
      cursorColor: Theme.of(context).primaryColor,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        contentPadding:
        const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      ),
    );
  }
}

// -------------------- INFINITE DAG BACKGROUND --------------------

class InfiniteDAGBackground extends StatefulWidget {
  const InfiniteDAGBackground({super.key});

  @override
  _InfiniteDAGBackgroundState createState() => _InfiniteDAGBackgroundState();
}

class _InfiniteDAGBackgroundState extends State<InfiniteDAGBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Offset> _nodes = [];
  List<Offset> _directions = [];
  final int nodeCount = 20;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  void _initializeNodes(Size screenSize) {
    final random = Random();
    _nodes = [];
    _directions = [];

    _nodes.add(Offset(screenSize.width / 2, 50));
    _directions.add(const Offset(0, 0));

    for (int i = 1; i < nodeCount; i++) {
      double dx = screenSize.width * 0.1 +
          (screenSize.width * 0.8) * random.nextDouble();
      double dy = 80 + (screenSize.height * 0.7) * random.nextDouble();
      _nodes.add(Offset(dx, dy));

      double dirX =
          (random.nextBool() ? 1 : -1) * (0.5 + random.nextDouble() * 0.5);
      double dirY =
          (random.nextBool() ? 1 : -1) * (0.5 + random.nextDouble() * 0.5);
      _directions.add(Offset(dirX, dirY));
    }

    _initialized = true;

    _controller.addListener(() {
      if (mounted) {
        setState(() {
          for (int i = 1; i < _nodes.length; i++) {
            Offset p = _nodes[i] + _directions[i];
            double x = p.dx;
            double y = p.dy;

            if (x < 0 || x > screenSize.width) {
              _directions[i] = Offset(-_directions[i].dx, _directions[i].dy);
            }
            if (y < 0 || y > screenSize.height) {
              _directions[i] = Offset(_directions[i].dx, -_directions[i].dy);
            }

            _nodes[i] = Offset(
              p.dx.clamp(0, screenSize.width),
              p.dy.clamp(0, screenSize.height),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_initialized && constraints.maxWidth > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _initializeNodes(constraints.biggest);
              });
            }
          });
        }
        return CustomPaint(
          size: constraints.biggest,
          painter: DAGPainter(nodes: _nodes),
        );
      },
    );
  }
}

class DAGPainter extends CustomPainter {
  final List<Offset> nodes;

  DAGPainter({required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1.5;

    for (int i = 1; i < nodes.length; i++) {
      int parentIndex = (i - 1) ~/ 2;
      canvas.drawLine(nodes[i], nodes[parentIndex], linePaint);
    }

    for (var point in nodes) {
      double radius = 5 + (point.dx + point.dy) % 4;
      canvas.drawCircle(point, radius, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}



// -------------------- DATA MODELS --------------------
class LandlordHomePage extends StatefulWidget {
  const LandlordHomePage({super.key});

  @override
  _LandlordHomePageState createState() => _LandlordHomePageState();
}

class _LandlordHomePageState extends State<LandlordHomePage> {
  int _currentIndex = 0;
  final List<int> _navigationStack = [0]; // history of visited tabs

  // The pages are initialized in initState so they can receive the custom callback
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Initialize pages, passing the custom back handler to each root tab
    _pages = [
      LandlordProfilePage(
        onBack: () {
          // Custom back logic for profile page
          if (_navigationStack.length > 1) {
            _handleCustomBack();
          } else {
            // Do nothing: stay on this page instead of popping
          }
        },
      ),
      AgreementsPage(onBack: _handleCustomBack),
      RequestsPage(onBack: _handleCustomBack),
      PaymentsPage(onBack: _handleCustomBack),
      SettingsPage(onBack: _handleCustomBack),
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
            BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Agreements'),
            BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Requests'),
            BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Payments'),
            BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}


// Dummy classes for compilation.
class DocumentField {
  String? selectedDoc;
  DocumentField({this.selectedDoc});
}

class PropertyCard {
  List<DocumentField> documents;
  PropertyCard({required this.documents});
}


// -------------------- LANDLORD PROFILE PAGE --------------------
class LandlordProfilePage extends StatefulWidget {
  final VoidCallback onBack; // callback for back button

  const LandlordProfilePage({super.key, required this.onBack});

  @override
  _LandlordProfilePageState createState() => _LandlordProfilePageState();
}

class _LandlordProfilePageState extends State<LandlordProfilePage> {
  List<DocumentField> userDocuments = [DocumentField()];
  List<PropertyCard> propertyCards = [PropertyCard(documents: [DocumentField()])];

  final List<String> userDocOptions = ["Aadhar", "PAN", "License", "Birth Certificate"];
  final List<String> propertyDocOptions = [
    "Property Tax Receipt",
    "Land Ownership Proof",
    "Electricity Bill",
    "Water Bill"
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent back navigation if stack is empty
        if (Navigator.canPop(context)) {
          return true; // allow pop
        } else {
          return false; // stay on page
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // ---------- BACKGROUND ----------
            Container(color: const Color(0xFF141E30)),
            const TwinklingStarBackground(),

            // ---------- MAIN CONTENT ----------
            SafeArea(
              minimum: EdgeInsets.zero, // no extra left/right padding
              child: Column(
                children: [
                  // ---------- TOP NAV BAR ----------
                  CustomTopNavBar(
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack, // use callback instead of Navigator.pop
                  ),

                  // ---------- SCROLLABLE CONTENT ----------
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // Added horizontal + vertical padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),

                          // ---------- PROFILE PIC ----------
                          const CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person, size: 60, color: Colors.deepPurple),
                          ),
                          const SizedBox(height: 20),

                          // ---------- PROFILE DETAILS ----------
                          const Text("Landlord Name", style: TextStyle(color: Colors.white, fontSize: 22)),
                          Text("Owner of ${propertyCards.length} Properties",
                              style: const TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 30),

                          // ---------- VALIDATE USER ----------
                          Text(
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12), // Increased spacing

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
                            label: const Text("Add Document"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                          ),
                          const SizedBox(height: 40),

                          // ---------- VALIDATE PROPERTY ----------
                          Text(
                            "Validate Property",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12), // Increased spacing

                          ListView.builder(
                            itemCount: propertyCards.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildPropertyCard(i),
                            ),
                          ),
                          const SizedBox(height: 20),

                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                propertyCards.add(PropertyCard(documents: [DocumentField()]));
                              });
                            },
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text("Add Property"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                          ),
                          const SizedBox(height: 60),
                   ]
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

  // ---------------- USER DOCUMENT FIELD ----------------
  Widget _buildUserDocField(int index) {
    final selectedDocs = userDocuments.map((e) => e.selectedDoc).whereType<String>().toList();
    final availableOptions = userDocOptions
        .where((doc) => !selectedDocs.contains(doc) || doc == userDocuments[index].selectedDoc)
        .toList();

    return GlassmorphismContainer(
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: userDocuments[index].selectedDoc,
              hint: const Text("Select Document", style: TextStyle(color: Colors.white)),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              items: availableOptions
                  .map((doc) => DropdownMenuItem(
                value: doc,
                child: Text(doc, style: const TextStyle(color: Colors.white)),
              ))
                  .toList(),
              onChanged: (val) {
                setState(() => userDocuments[index].selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text("Upload", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ---------------- PROPERTY CARD ----------------
  Widget _buildPropertyCard(int index) {
    final property = propertyCards[index];

    return GlassmorphismContainer(
      opacity: 0.12,
      padding: const EdgeInsets.all(12),
      borderRadius: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.home, color: Colors.orange.shade700),
              const SizedBox(width: 10),
              const Text("Property Validation",
                  style: TextStyle(color: Colors.white, fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => setState(() => propertyCards.removeAt(index)),
              ),
            ],
          ),
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
              label: const Text("Add Document", style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- PROPERTY DOCUMENT FIELD ----------------
  Widget _buildPropertyDocField(int propIndex, int docIndex) {
    final property = propertyCards[propIndex];
    final selectedDocs = property.documents.map((e) => e.selectedDoc).whereType<String>().toList();
    final availableOptions = propertyDocOptions
        .where((doc) => !selectedDocs.contains(doc) || doc == property.documents[docIndex].selectedDoc)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: property.documents[docIndex].selectedDoc,
              hint: const Text("Select Document", style: TextStyle(color: Colors.white)),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              items: availableOptions
                  .map((doc) => DropdownMenuItem(
                value: doc,
                child: Text(doc, style: const TextStyle(color: Colors.white)),
              ))
                  .toList(),
              onChanged: (val) {
                setState(() => property.documents[docIndex].selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () {
                  setState(() {
                    property.documents.removeAt(docIndex);
                  });
                },
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
                child: const Text("Upload", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



// -------------------- REQUESTS PAGE (Updated with BG and Glassmorphism Card) --------------------
class RequestsPage extends StatelessWidget {
  final VoidCallback onBack;
  const RequestsPage({super.key, required this.onBack});

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
                // Custom Top Nav Bar
                CustomTopNavBar(showBack: true, title: "Requests", onBack: onBack),

                // Screen Title
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Pending Requests",
                    style: TextStyle(
                      color: Colors.white,
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
    this.opacity = 0.05, // Default opacity lowered to 0.05 for more transparency
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
                        MaterialPageRoute(builder: (context) => const LoginPage()),
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
                    child: const Text('YES, Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    child: const Text('NO, Stay', style: TextStyle(color: Colors.white)),
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
  State<TwinklingStarBackground> createState() => _TwinklingStarBackgroundState();
}

class _TwinklingStarBackgroundState extends State<TwinklingStarBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final int _numberOfStars = 80; // INCREASED DENSITY from 50
  late List<Map<String, dynamic>> _stars;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15), // Longer duration for subtle movement
    )..repeat();

    // Initialize stars with random properties
    _stars = List.generate(_numberOfStars, (index) => _createRandomStar());
  }

  Map<String, dynamic> _createRandomStar() {
    return {
      'offset': Offset(Random().nextDouble(), Random().nextDouble()),
      'size': 2.0 + Random().nextDouble() * 3.0, // INCREASED SIZE range from 1.5-4.0 to 2.0-5.0
      'duration': Duration(milliseconds: 1500 + Random().nextInt(1500)), // Twinkle duration
      'delay': Duration(milliseconds: Random().nextInt(10000)), // Starting delay
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
              final double timeInMilliseconds = _controller.value * _controller.duration!.inMilliseconds;
              final double timeOffset = (timeInMilliseconds + star['delay'].inMilliseconds) / star['duration'].inMilliseconds;

              // Use a sine wave for blinking effect, slightly offset to prevent perfect synchronization
              final double opacityFactor = (sin(timeOffset * pi * 2) + 1) / 2;

              // INCREASED INTENSITY/OPACITY: Opacity range from very dim (0.1) to bright (0.8)
              final double opacity = 0.1 + (0.7 * opacityFactor); // Multiplier changed from 0.5 to 0.7

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

  // Data structure for settings options
  static final List<Map<String, dynamic>> _settingsOptions = [
    {
      'title': 'Edit Profile',
      'icon': Icons.person_outline,
      'color': Colors.blue,
      'action': (BuildContext context) => print('Navigate to Profile Edit'),
    },
    {
      'title': 'Change Password',
      'icon': Icons.lock_outline,
      'color': Colors.orange,
      'action': (BuildContext context) => print('Navigate to Password Change'),
    },
    {
      'title': 'Notification Preferences',
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
      'action': (BuildContext context) => print('Navigate to Help'),
    },
  ];

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
                // Custom Top Nav Bar
                CustomTopNavBar(showBack: true, title: "Settings", onBack: onBack),

                // Screen Title below the App Branding
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Account Settings",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Settings List with Glassmorphism Cards
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
                              opacity: 0.08, // Opacity reduced for more transparency
                              onTap: () => option['action'](context),
                              child: Row(
                                children: [
                                  Icon(
                                    option['icon'] as IconData,
                                    color: option['color'] as Color,
                                    size: 30,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option['title'] as String,
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

                        const SizedBox(height: 40),

                        // Logout Button (Triggers the confirmation dialog)
                        GlassmorphismContainer(
                          borderRadius: 15,
                          opacity: 0.08, // Opacity reduced for more transparency
                          onTap: () {
                            // Shows the confirmation dialog
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) => const LogoutConfirmationDialog(),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout, color: Colors.redAccent, size: 30),
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
                CustomTopNavBar(showBack: true, title: "Agreements", onBack: onBack),

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
                    showBack: true, title: "Payments", onBack: widget.onBack),
                const SizedBox(height: 15),

                // Flexible + Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset + 20),
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
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                ),
                                const SizedBox(height: 10),

                                // Payment method buttons
                                Wrap(
                                  spacing: 10,
                                  children: [
                                    _paymentButton("UPI", Icons.account_balance_wallet),
                                    _paymentButton("Credit/Debit Card", Icons.credit_card),
                                    _paymentButton("Net Banking", Icons.account_balance),
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
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: ListTile(
                                leading: Icon(Icons.receipt_long,
                                    color: Colors.orange.shade400),
                                title: Text(
                                  "₹${data['amount']} - ${data['method']}",
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  data['date'],
                                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
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
        backgroundColor:
        isSelected ? Colors.orange.shade700 : Colors.white.withOpacity(0.1),
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
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
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
                            "Payment of ₹$amount initiated via $selectedMethod"),
                      ),
                    );
                  },
                  child:
                  const Text("Confirm", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

// -------------------- TENANT PROFILE PAGE (Redirect Target) --------------------


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
  BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Agreements'),
    BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
  BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Requests'),
  BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Payments'),
  BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),

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
  _TenantProfilePageState createState() => _TenantProfilePageState();
}

class _TenantProfilePageState extends State<TenantProfilePage> {
  List<DocumentField> userDocuments = [DocumentField()];
  final List<String> userDocOptions = ["Aadhar", "PAN", "License", "Birth Certificate"];

  List<HomeRental> rentedHomes = [
    HomeRental(name: "Sea View Apartment", address: "Beach Road, Goa"),
    HomeRental(name: "Sunshine Villa", address: "MG Road, Bangalore"),
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent back navigation if stack is empty
        if (Navigator.canPop(context)) {
          return true; // allow pop
        } else {
          return false; // stay on page
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const AnimatedGradientBackground(),
            SafeArea(
              child: Column(
                children: [
                  // ---------- TOP NAV BAR ----------
                  CustomTopNavBar(
                    showBack: true,
                    title: 'My Profile',
                    onBack: widget.onBack, // <-- use callback instead of Navigator.pop
                  ),

                  // ---------- SCROLLABLE CONTENT ----------
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // added padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),

                          // ---------- PROFILE PIC ----------
                          const CircleAvatar(
                            radius: 55,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.person, size: 60, color: Colors.deepPurple),
                          ),
                          const SizedBox(height: 20),

                          // ---------- PROFILE DETAILS ----------
                          const Text("Tenant Name", style: TextStyle(color: Colors.white, fontSize: 22)),
                          Text("Agreements for ${rentedHomes.length} Homes",
                              style: const TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 30),

                          // ---------- VALIDATE USER ----------
                          Text(
                            "Validate User",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12), // slightly increased spacing

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
                            label: const Text("Add Document"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                          ),
                          const SizedBox(height: 40),

                          // ---------- RENTED HOMES ----------
                          Text(
                            "My Rented Homes",
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12), // increased spacing

                          ListView.builder(
                            itemCount: rentedHomes.length,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              final home = rentedHomes[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GlassmorphismContainer(
                                  opacity: 0.1,
                                  child: ListTile(
                                    leading: const Icon(Icons.home, color: Colors.orange),
                                    title: Text(home.name, style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(home.address, style: const TextStyle(color: Colors.white70)),
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
      ),
    );
  }



  // ---------------- USER DOCUMENT FIELD ----------------
  Widget _buildUserDocField(int index) {
    final selectedDocs = userDocuments.map((e) => e.selectedDoc).whereType<String>().toList();
    final availableOptions = userDocOptions
        .where((doc) => !selectedDocs.contains(doc) || doc == userDocuments[index].selectedDoc)
        .toList();

    return GlassmorphismContainer(
      opacity: 0.1,
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: userDocuments[index].selectedDoc,
              hint: const Text("Select Document", style: TextStyle(color: Colors.white)),
              dropdownColor: Colors.grey.shade900,
              style: const TextStyle(color: Colors.white),
              items: availableOptions
                  .map((doc) => DropdownMenuItem(
                value: doc,
                child: Text(doc, style: const TextStyle(color: Colors.white)),
              ))
                  .toList(),
              onChanged: (val) {
                setState(() => userDocuments[index].selectedDoc = val);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: () => setState(() => userDocuments.removeAt(index)),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text("Upload", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
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

class _AnimatedGradientBackgroundState
    extends State<AnimatedGradientBackground> with SingleTickerProviderStateMixin {
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

    _stars = List.generate(_numberOfStars, (_) => _ShootingStar.random(_random));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final bgColor = Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
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
    final endX = startX + (-0.2 + random.nextDouble() * 0.4); // horizontal variation
    final endY = startY + 0.2 + random.nextDouble() * 0.3;     // downward movement

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


// -------------------- SEARCH PAGE --------------------
class SearchPage extends StatefulWidget {
  final VoidCallback onBack;
  const SearchPage({super.key, required this.onBack});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(
                  showBack: true,
                  title: 'Search',
                  onBack: widget.onBack,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "SEARCH HOMES",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Search homes, agreements, etc.",
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          final query = _searchController.text.trim();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Search: $query')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(Icons.search, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Center(
                    child: Text(
                      'Search results will appear here',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16),
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

// -------------------- REQUESTS PAGE --------------------
class RequestsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const RequestsPage2({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(showBack: true, title: "Requests", onBack: onBack),
                const Padding(
                  padding: EdgeInsets.only(top: 8.0, bottom: 20.0),
                  child: Text(
                    "Pending Requests",
                    style: TextStyle(
                      color: Colors.white,
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

// -------------------- SETTINGS PAGE --------------------
class SettingsPage2 extends StatelessWidget {
  final VoidCallback onBack;
  const SettingsPage2({super.key, required this.onBack});

  static final List<Map<String, dynamic>> _settingsOptions = [
    {
      'title': 'Edit Profile',
      'icon': Icons.person_outline,
      'color': Colors.blue,
      'action': (BuildContext context) => print('Navigate to Profile Edit'),
    },
    {
      'title': 'Change Password',
      'icon': Icons.lock_outline,
      'color': Colors.orange,
      'action': (BuildContext context) => print('Navigate to Password Change'),
    },
    {
      'title': 'Notification Preferences',
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
      'action': (BuildContext context) => print('Navigate to Help'),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                CustomTopNavBar(showBack: true, title: "Settings", onBack: onBack),
                const SizedBox(height: 20),

                // ------------------- ACCOUNT SETTINGS HEADING -------------------
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                        // Settings options
                        ..._settingsOptions.map((option) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GlassmorphismContainer(
                              borderRadius: 15,
                              opacity: 0.08,
                              onTap: () => option['action'](context),
                              child: Row(
                                children: [
                                  Icon(option['icon'] as IconData,
                                      color: option['color'] as Color, size: 30),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option['title'] as String,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios,
                                      color: Colors.white54, size: 16),
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
                                        borderRadius: BorderRadius.circular(15)),
                                    title: const Text(
                                      "Confirm Logout",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    content: const Text(
                                      "Are you sure you want to logout?",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext),
                                        child: const Text("Cancel",
                                            style: TextStyle(color: Colors.grey)),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent),
                                        onPressed: () {
                                          Navigator.pop(dialogContext);
                                          // Navigate to LoginPage
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) => const LoginPage()),
                                          );
                                        },
                                        child: const Text("Logout",
                                            style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                            );
                          },
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout,
                                  color: Colors.redAccent, size: 30),
                              SizedBox(width: 15),
                              Text(
                                'LOGOUT',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold),
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
                CustomTopNavBar(showBack: true, title: "Agreements", onBack: onBack),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // -------------------- PAYMENT SETUP --------------------
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                                    style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    children: [
                                      _paymentButton("UPI", Icons.account_balance_wallet),
                                      _paymentButton("Credit/Debit Card", Icons.credit_card),
                                      _paymentButton("Net Banking", Icons.account_balance),
                                      _paymentButton("Wallets", Icons.wallet),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (selectedMethod != null)
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: _buildPaymentFields(selectedMethod!),
                                    ),
                                ],
                              ),
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
                                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  ),
                                  child: ListTile(
                                    leading: Icon(Icons.receipt_long,
                                        color: Colors.orange.shade400),
                                    title: Text(
                                      "₹${data['amount']} - ${data['method']}",
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Text(
                                      data['date'],
                                      style: TextStyle(color: Colors.white.withOpacity(0.7)),
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
        backgroundColor:
        isSelected ? Colors.orange.shade700 : Colors.white.withOpacity(0.1),
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
                  borderRadius: BorderRadius.circular(15)),
              title: const Text(
                "Confirm Payment",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                "Are you sure you want to proceed with ₹$amount via $selectedMethod?",
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
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
                              "Payment of ₹$amount initiated via $selectedMethod")),
                    );
                  },
                  child: const Text("Confirm", style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange.shade700,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

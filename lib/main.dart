import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:main_project/landlord/landlord_registration_page.dart';
import 'package:main_project/login_page.dart';
import 'package:main_project/tenant/tenant_registration_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'tenant/tenant.dart';
import 'package:main_project/landlord/landlord.dart';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:main_project/config.dart';

int? role;
String uid = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Widget startScreen = const LoginPage();

  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? storedUid = prefs.getString('user_id');
    final int? storedRole = prefs.getInt('user_role');

    if (storedUid != null && storedRole != null) {
      uid = storedUid;
      role = storedRole;
      if (storedRole == 1) {
        startScreen = const LandlordHomePage();
      } else if (storedRole == 0) {
        startScreen = const TenantHomePage();
      }
    }
  } catch (e) {
    // Fallback to LoginPage on error
  }

  runApp(MyApp(startScreen: startScreen));
}

class MyApp extends StatelessWidget {
  final Widget startScreen;

  const MyApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secure Homes',
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.blue),
      home: startScreen,
    );
  }
}

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
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Your Role',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
                          builder: (context) => const TenantRegistrationPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.teal.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Register as Tenant',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
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
                              const LandlordRegistrationPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.indigo.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Register as Landlord',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
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
        color: Colors.white.withValues(alpha: 0.95),
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
            style: const TextStyle(color: Colors.black54, fontSize: 16),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black87),
          style: const TextStyle(color: Colors.black87, fontSize: 16),
          dropdownColor: Colors.white.withValues(alpha: 0.95),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(color: Colors.black87),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class CustomTextField extends StatelessWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  const CustomTextField({
    super.key,
    required this.hintText,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 20,
        ),
      ),
    );
  }
}

class InfiniteDAGBackground extends StatefulWidget {
  const InfiniteDAGBackground({super.key});

  @override
  InfiniteDAGBackgroundState createState() => InfiniteDAGBackgroundState();
}

class InfiniteDAGBackgroundState extends State<InfiniteDAGBackground>
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
      double dx =
          screenSize.width * 0.1 +
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
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
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

class CustomTopNavBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBack;
  final String title;
  final VoidCallback? onBack;

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
      // Reduced horizontal padding slightly to prevent overflow on small screens
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 15.0),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3)),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Expanded allows the inner Row to take available space but not overflow
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Back Button (Conditional)
                  if (showBack)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        if (onBack != null) {
                          onBack!();
                        } else if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    )
                  else
                    const SizedBox.shrink(),

                  const SizedBox(width: 8),

                  // Logo
                  Image.asset(
                    'lib/assets/icon.png',
                    height: 32,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.security,
                        color: Colors.white,
                        size: 32,
                      );
                    },
                  ),

                  const SizedBox(width: 12),

                  // FIX: Flexible prevents the text from causing an overflow
                  const Flexible(
                    child: Text(
                      'SECURE HOMES',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class RestReference implements Reference {
  @override
  final String name;
  @override
  final String fullPath;
  RestReference({required this.name, required this.fullPath});
  @override
  Future<String> getDownloadURL() async {
    String encodedName = Uri.encodeComponent(fullPath);
    return '$kStorageBaseUrl/$encodedName?alt=media&key=$kFirebaseAPIKey';
  }

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

dynamic requestsParseFirestoreValue(Map<String, dynamic> valueMap) {
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
    return values.map((v) => requestsParseFirestoreValue(v)).toList();
  }
  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    Map<String, dynamic> result = {};
    fields.forEach((key, val) {
      result[key] = requestsParseFirestoreValue(val);
    });
    return result;
  }
  return null;
}

dynamic parseFirestoreRestValue(Map<String, dynamic> valueMap) {
  if (valueMap.containsKey('stringValue')) return valueMap['stringValue'];
  if (valueMap.containsKey('integerValue')) {
    return int.tryParse(valueMap['integerValue'] ?? '0');
  }
  // ... inside dynamic parseFirestoreRestValue(Map<String, dynamic> valueMap) ...

  // REPLACE THIS BLOCK:
  if (valueMap.containsKey('doubleValue')) {
    var val = valueMap['doubleValue'];
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0; // Fallback
  }
  if (valueMap.containsKey('booleanValue')) return valueMap['booleanValue'];
  if (valueMap.containsKey('arrayValue')) {
    var values = valueMap['arrayValue']['values'] as List?;
    if (values == null) return [];
    return values.map((v) => parseFirestoreRestValue(v)).toList();
  }
  if (valueMap.containsKey('mapValue')) {
    var fields = valueMap['mapValue']['fields'] as Map<String, dynamic>?;
    if (fields == null) return {};
    Map<String, dynamic> result = {};
    fields.forEach((key, val) {
      result[key] = parseFirestoreRestValue(val);
    });
    return result;
  }
  return null;
}

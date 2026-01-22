import 'package:flutter/material.dart';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:main_project/tenant/agreements_page_tenant.dart';
import 'package:main_project/tenant/payments_page_tenant.dart';
import 'package:main_project/tenant/request_page_tenant.dart';
import 'package:main_project/tenant/search_home.dart';
import 'package:main_project/tenant/tenant_home_page.dart';
import 'package:main_project/tenant/tenant_settings.dart';

class TenantHomePage extends StatefulWidget {
  const TenantHomePage({super.key});

  @override
  TenantHomePageState createState() => TenantHomePageState();
}

class TenantHomePageState extends State<TenantHomePage> {
  int _currentIndex = 0;
  final List<int> _navigationStack = [0];

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      TenantProfilePage(
        onBack: () {
          if (_navigationStack.length > 1) {
            _handleCustomBack();
          } else {}
        },
      ),
      AgreementsPage2(onBack: _handleCustomBack),
      SearchPage(onBack: _handleCustomBack),
      RequestsPage2(onBack: _handleCustomBack),
      PaymentsPage2(onBack: _handleCustomBack),
      SettingsPage2(onBack: _handleCustomBack),
    ];
  }

  void _handleCustomBack() {
    if (_navigationStack.length > 1) {
      setState(() {
        _navigationStack.removeLast();
        _currentIndex = _navigationStack.last;
      });
    } else {
      Navigator.pop(context);
    }
  }

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

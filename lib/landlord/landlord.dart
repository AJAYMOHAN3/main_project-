import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math';
import 'package:main_project/landlord/landlord_home_page.dart';
import 'package:main_project/landlord/agreements_page_landlord.dart';
import 'package:main_project/landlord/payments_page_landlord.dart';
import 'package:main_project/landlord/requests_landlord.dart';
import 'package:main_project/landlord/settings_page_landlord.dart';

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
              color: Colors.white.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
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
                          color: Colors.white.withValues(alpha: 0.5 * opacity),
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

class LandlordHomePage extends StatefulWidget {
  const LandlordHomePage({super.key});

  @override
  LandlordHomePageState createState() => LandlordHomePageState();
}

class LandlordHomePageState extends State<LandlordHomePage> {
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
    return PopScope<Object?>(
      canPop: true,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
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

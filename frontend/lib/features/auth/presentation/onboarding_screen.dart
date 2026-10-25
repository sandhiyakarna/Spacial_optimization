import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../app/constants/app_constants.dart';
import '../../../app/themes/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'title': 'Visualize Your Space',
      'description': 'Capture 360° of your room and bring it to life in 3D.',
      'imageUrl': 'https://images.unsplash.com/photo-1540518614846-7eded433c457?w=600&auto=format&fit=crop',
    },
    {
      'title': 'AI-Powered Planning',
      'description': 'Get intelligent layout suggestions based on interior design rules.',
      'imageUrl': 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=600&auto=format&fit=crop',
    },
    {
      'title': 'Walk Through Your Design',
      'description': 'Experience your future room in immersive walkthrough mode.',
      'imageUrl': 'https://images.unsplash.com/photo-1556911220-e15b29be8c8f?w=600&auto=format&fit=crop',
    },
    {
      'title': 'Optimize for Comfort',
      'description': 'Perfect your space with lighting, ergonomics and smart analytics.',
      'imageUrl': 'https://images.unsplash.com/photo-1505691938895-1758d7feb511?w=600&auto=format&fit=crop',
    },
  ];

  Future<void> _completeOnboarding() async {
    await TokenStorage().setHasSeenOnboarding(true);
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar (Skip Button)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.space24,
                vertical: AppConstants.space16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentPage < _onboardingData.length - 1)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 48), // Spacer to maintain layout height
                ],
              ),
            ),

            // Slider Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) {
                  final data = _onboardingData[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppConstants.space24),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Arched Illustration Frame
                          Container(
                            height: (MediaQuery.of(context).size.height * 0.4).clamp(140.0, 320.0),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(120),
                                bottom: Radius.circular(AppConstants.radiusCard),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                              border: Border.all(
                                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                                width: 1.0,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(120),
                                bottom: Radius.circular(AppConstants.radiusCard),
                              ),
                              child: (data['imageUrl']!.isEmpty || data['imageUrl']!.contains('unsplash.com'))
                                  ? Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [AppTheme.primary, AppTheme.secondary],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.architecture_rounded,
                                          size: 80,
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  : Image.network(
                                      data['imageUrl']!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        // Fallback beautiful brand gradient
                                        return Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [AppTheme.primary, AppTheme.secondary],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Icon(
                                              Icons.architecture_rounded,
                                              size: 80,
                                              color: Colors.white,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: AppConstants.space32),

                          // Text Title
                          Text(
                            data['title']!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: AppConstants.space16),

                          // Description
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppConstants.space16),
                            child: Text(
                              data['description']!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom Controls (Dots & Next/Get Started)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.space24,
                vertical: AppConstants.space32,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators / Dots
                  Row(
                    children: List.generate(
                      _onboardingData.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppTheme.primary
                              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Action Button
                  _currentPage < _onboardingData.length - 1
                      ? FilledButton(
                          onPressed: () {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                            elevation: 4,
                            shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded),
                        )
                      : FilledButton(
                          onPressed: _completeOnboarding,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppConstants.radiusButton),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                            elevation: 4,
                            shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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

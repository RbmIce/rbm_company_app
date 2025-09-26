// loading_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rbm/screens/welcome_screen.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  // Update the _checkAuthStatus method
  Future<void> _checkAuthStatus() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final session = await authService.isLoggedIn();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => session != null ? const LandingScreen() : const LoginScreen(),
        ),
      );
    } catch (e) {
      print('Error checking auth status: $e');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[800],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icons/rbm_ice_logo.png',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 20),
            const Text(
              'RBM Ice Company',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Business Management System',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class AuthService with ChangeNotifier { // Changed to 'with ChangeNotifier'
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _adminPasswordKey = 'admin_password';
  static const String _userSessionKey = 'user_session';
  static const String _defaultAdminPassword = 'admin123';
  static const int _sessionTimeoutMinutes = 30;

  // Add a property to track authentication state
  Map<String, dynamic>? _currentSession;
  Map<String, dynamic>? get currentSession => _currentSession;

  // Hash password using SHA-256
  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  // Login with role detection
  Future<Map<String, dynamic>> login(String password) async {
    try {
      final hashedPassword = _hashPassword(password);

      // Check if it's admin password
      final adminPassword = await _getAdminPassword();
      if (hashedPassword == adminPassword) {
        await _saveSession('admin', 'admin');
        return {'success': true, 'role': 'admin', 'userId': 'admin'};
      }

      // Check if it's a manager password
      final manager = await _getManagerByPassword(hashedPassword);
      if (manager != null) {
        await _saveSession('manager', manager['id']);
        return {
          'success': true,
          'role': 'manager',
          'userId': manager['id'],
          'username': manager['username']
        };
      }

      return {'success': false, 'error': 'Invalid password'};
    } catch (e) {
      print('Error during login: $e');
      return {'success': false, 'error': 'Login failed: $e'};
    }
  }

  // Check if user is logged in and session is valid
  Future<Map<String, dynamic>?> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionData = prefs.getString(_userSessionKey);

      if (sessionData == null) {
        _currentSession = null;
        notifyListeners();
        return null;
      }

      final session = json.decode(sessionData);
      final lastActivity = DateTime.parse(session['lastActivity']);
      final now = DateTime.now();

      // Check session timeout
      if (now.difference(lastActivity).inMinutes > _sessionTimeoutMinutes) {
        await logout();
        return null;
      }

      // Update last activity
      await _updateSessionActivity();

      _currentSession = session;
      notifyListeners();
      return session;
    } catch (e) {
      print('Error checking login status: $e');
      await logout();
      return null;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userSessionKey);
      _currentSession = null;
      notifyListeners();
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  // Save session
  Future<void> _saveSession(String role, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final session = {
      'role': role,
      'userId': userId,
      'loginTime': DateTime.now().toIso8601String(),
      'lastActivity': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_userSessionKey, json.encode(session));
    _currentSession = session;
    notifyListeners();
  }

  // Update session activity
  Future<void> _updateSessionActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionData = prefs.getString(_userSessionKey);
      if (sessionData != null) {
        final session = json.decode(sessionData);
        session['lastActivity'] = DateTime.now().toIso8601String();
        await prefs.setString(_userSessionKey, json.encode(session));
        _currentSession = session;
      }
    } catch (e) {
      print('Error updating session activity: $e');
    }
  }

  // Get admin password from Firestore
  Future<String> _getAdminPassword() async {
    try {
      final doc = await _firestore.collection('settings').doc('security').get();

      if (doc.exists && doc.data()?['adminPassword'] != null) {
        return doc.data()!['adminPassword'] as String;
      }

      // Set default admin password if not exists
      final defaultHashedPassword = _hashPassword(_defaultAdminPassword);
      await _firestore.collection('settings').doc('security').set({
        'adminPassword': defaultHashedPassword,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return defaultHashedPassword;
    } catch (e) {
      print('Error getting admin password: $e');
      return _hashPassword(_defaultAdminPassword);
    }
  }

  // Get manager by password
  Future<Map<String, dynamic>?> _getManagerByPassword(String hashedPassword) async {
    try {
      final snapshot = await _firestore
          .collection('managers')
          .where('password', isEqualTo: hashedPassword)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final manager = snapshot.docs.first;
        return {
          'id': manager.id,
          'username': manager.data()['username'],
          'createdAt': manager.data()['createdAt'],
        };
      }
      return null;
    } catch (e) {
      print('Error getting manager by password: $e');
      return null;
    }
  }

  // Manager management methods (Admin only)
  Future<bool> createManager(String username, String password) async {
    try {
      // Check if username already exists
      final existingSnapshot = await _firestore
          .collection('managers')
          .where('username', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (existingSnapshot.docs.isNotEmpty) {
        throw Exception('Username already exists');
      }

      final hashedPassword = _hashPassword(password);
      await _firestore.collection('managers').add({
        'username': username.toLowerCase(),
        'password': hashedPassword,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
      });

      return true;
    } catch (e) {
      print('Error creating manager: $e');
      throw e;
    }
  }

  Future<bool> updateManagerPassword(String managerId, String newPassword) async {
    try {
      final hashedPassword = _hashPassword(newPassword);
      await _firestore.collection('managers').doc(managerId).update({
        'password': hashedPassword,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error updating manager password: $e');
      throw e;
    }
  }

  Future<bool> deleteManager(String managerId) async {
    try {
      await _firestore.collection('managers').doc(managerId).update({
        'status': 'deleted',
        'deletedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('Error deleting manager: $e');
      throw e;
    }
  }

  Future<bool> changeAdminPassword(String currentPassword, String newPassword) async {
    try {
      final currentHashedPassword = _hashPassword(currentPassword);
      final adminPassword = await _getAdminPassword();

      if (currentHashedPassword != adminPassword) {
        throw Exception('Current password is incorrect');
      }

      final newHashedPassword = _hashPassword(newPassword);
      await _firestore.collection('settings').doc('security').update({
        'adminPassword': newHashedPassword,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update session if admin is currently logged in
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_userSessionKey)) {
        await _saveSession('admin', 'admin');
      }

      return true;
    } catch (e) {
      print('Error changing admin password: $e');
      throw e;
    }
  }

  // Get all active managers
  Future<List<Map<String, dynamic>>> getManagers() async {
    try {
      final snapshot = await _firestore
          .collection('managers')
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'username': data['username'],
          'createdAt': data['createdAt']?.toDate() ?? DateTime.now(),
          'createdBy': data['createdBy'] ?? 'admin',
        };
      }).toList();
    } catch (e) {
      print('Error getting managers: $e');
      return [];
    }
  }

  // Validate session for protected operations
  Future<void> validateAdminSession() async {
    final session = await isLoggedIn();
    if (session == null || session['role'] != 'admin') {
      throw Exception('Unauthorized: Admin access required');
    }
    await _updateSessionActivity();
  }

  // Get current user info
  Future<Map<String, dynamic>?> getCurrentUser() async {
    return await isLoggedIn();
  }
}
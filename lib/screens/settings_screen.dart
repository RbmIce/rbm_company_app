// // settings_screen.dart
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../services/auth_service.dart';
//
// class SettingsScreen extends StatefulWidget {
//   const SettingsScreen({super.key});
//
//   @override
//   State<SettingsScreen> createState() => _SettingsScreenState();
// }
//
// class _SettingsScreenState extends State<SettingsScreen> {
//   final _formKey = GlobalKey<FormState>();
//   final _currentPasswordController = TextEditingController();
//   final _newPasswordController = TextEditingController();
//   final _confirmPasswordController = TextEditingController();
//   final _adminPasswordController = TextEditingController();
//   bool _isLoading = false;
//   String _message = '';
//
//   Future<void> _changePassword() async {
//     if (_formKey.currentState!.validate()) {
//       setState(() {
//         _isLoading = true;
//         _message = '';
//       });
//
//       final authService = Provider.of<AuthService>(context, listen: false);
//       final success = await authService.changePassword(
//         _currentPasswordController.text,
//         _newPasswordController.text,
//         _adminPasswordController.text,
//       );
//
//       setState(() {
//         _isLoading = false;
//         if (success) {
//           _message = 'Password changed successfully!';
//           _currentPasswordController.clear();
//           _newPasswordController.clear();
//           _confirmPasswordController.clear();
//           _adminPasswordController.clear();
//         } else {
//           _message = 'Failed to change password. Please check your inputs.';
//         }
//       });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Settings'),
//         backgroundColor: Colors.blue[800],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Form(
//           key: _formKey,
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               const Text(
//                 'Change Password',
//                 style: TextStyle(
//                   fontSize: 20,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 20),
//               if (_message.isNotEmpty)
//                 Container(
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: _message.contains('success')
//                         ? Colors.green[50]
//                         : Colors.red[50],
//                     borderRadius: BorderRadius.circular(8),
//                     border: Border.all(
//                       color: _message.contains('success')
//                           ? Colors.green[200]!
//                           : Colors.red[200]!,
//                     ),
//                   ),
//                   child: Row(
//                     children: [
//                       Icon(
//                         _message.contains('success')
//                             ? Icons.check_circle
//                             : Icons.error_outline,
//                         color: _message.contains('success')
//                             ? Colors.green
//                             : Colors.red,
//                       ),
//                       const SizedBox(width: 10),
//                       Expanded(
//                         child: Text(
//                           _message,
//                           style: TextStyle(
//                             color: _message.contains('success')
//                                 ? Colors.green
//                                 : Colors.red,
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               if (_message.isNotEmpty) const SizedBox(height: 20),
//               TextFormField(
//                 controller: _currentPasswordController,
//                 obscureText: true,
//                 decoration: const InputDecoration(
//                   labelText: 'Current Password',
//                   border: OutlineInputBorder(),
//                 ),
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please enter current password';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 16),
//               TextFormField(
//                 controller: _newPasswordController,
//                 obscureText: true,
//                 decoration: const InputDecoration(
//                   labelText: 'New Password',
//                   border: OutlineInputBorder(),
//                 ),
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please enter new password';
//                   }
//                   if (value.length < 6) {
//                     return 'Password must be at least 6 characters';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 16),
//               TextFormField(
//                 controller: _confirmPasswordController,
//                 obscureText: true,
//                 decoration: const InputDecoration(
//                   labelText: 'Confirm New Password',
//                   border: OutlineInputBorder(),
//                 ),
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please confirm new password';
//                   }
//                   if (value != _newPasswordController.text) {
//                     return 'Passwords do not match';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 16),
//               TextFormField(
//                 controller: _adminPasswordController,
//                 obscureText: true,
//                 decoration: const InputDecoration(
//                   labelText: 'Admin Password',
//                   border: OutlineInputBorder(),
//                 ),
//                 validator: (value) {
//                   if (value == null || value.isEmpty) {
//                     return 'Please enter admin password';
//                   }
//                   return null;
//                 },
//               ),
//               const SizedBox(height: 24),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton(
//                   onPressed: _isLoading ? null : _changePassword,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.blue[800],
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 16),
//                   ),
//                   child: _isLoading
//                       ? const SizedBox(
//                     width: 20,
//                     height: 20,
//                     child: CircularProgressIndicator(
//                       strokeWidth: 2,
//                       valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
//                     ),
//                   )
//                       : const Text('Change Password'),
//                 ),
//               ),
//               const SizedBox(height: 20),
//               const Divider(),
//               const SizedBox(height: 20),
//               const Text(
//                 'Security Information',
//                 style: TextStyle(
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//               const SizedBox(height: 10),
//               const Text(
//                 '• Admin password can only be changed in the database\n'
//                     '• Default password: admin123\n'
//                     '• Password is stored securely on your device\n'
//                     '• You will be automatically logged out if password changes',
//                 style: TextStyle(color: Colors.grey),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   @override
//   void dispose() {
//     _currentPasswordController.dispose();
//     _newPasswordController.dispose();
//     _confirmPasswordController.dispose();
//     _adminPasswordController.dispose();
//     super.dispose();
//   }
// }
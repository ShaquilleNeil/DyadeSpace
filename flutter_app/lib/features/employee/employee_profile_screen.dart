import 'package:flutter/material.dart';

import '../shared/widgets/profile_view.dart';

class EmployeeProfileScreen extends StatelessWidget {
  const EmployeeProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile'), automaticallyImplyLeading: false),
        body: const SafeArea(child: ProfileView()),
      );
}

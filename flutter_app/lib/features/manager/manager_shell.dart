import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ManagerShell extends StatelessWidget {
  const ManagerShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) =>
            navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Staff'),
          NavigationDestination(icon: Icon(Icons.task), label: 'My Tasks'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'Reports'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

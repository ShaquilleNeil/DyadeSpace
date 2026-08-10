import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/employee/employee_home_screen.dart';
import '../features/employee/employee_profile_screen.dart';
import '../features/employee/employee_shell.dart';
import '../features/manager/manager_home_screen.dart';
import '../features/manager/manager_profile_screen.dart';
import '../features/manager/manager_shell.dart';
import '../features/manager/manager_staff_screen.dart';
import '../features/manager/manager_tasks_screen.dart';
import '../features/manager/project_employees_screen.dart';
import '../features/manager/project_tasks_screen.dart';
import '../features/manager/project_view_screen.dart';
import '../features/manager/task_view_screen.dart';
import '../features/shared/splash_screen.dart';
import '../providers/auth_providers.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _GoRouterRefreshNotifier(ref);
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ManagerShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/manager', builder: (context, state) => const ManagerHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/manager/staff',
              builder: (context, state) => const ManagerStaffScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/manager/tasks',
              builder: (context, state) => const ManagerTasksScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/manager/profile',
              builder: (context, state) => const ManagerProfileScreen(),
            ),
          ]),
        ],
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            EmployeeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/employee', builder: (context, state) => const EmployeeHomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/employee/profile',
              builder: (context, state) => const EmployeeProfileScreen(),
            ),
          ]),
        ],
      ),

      // Global routes, reachable from either role, pushed over the shell.
      GoRoute(
        path: '/project/:projectId',
        builder: (context, state) =>
            ProjectViewScreen(projectId: state.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/project/:projectId/employees',
        builder: (context, state) =>
            ProjectEmployeesScreen(projectId: state.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/project/:projectId/tasks',
        builder: (context, state) =>
            ProjectTasksScreen(projectId: state.pathParameters['projectId']!),
      ),
      GoRoute(
        path: '/task/:taskId',
        builder: (context, state) => TaskViewScreen(taskId: state.pathParameters['taskId']!),
      ),
    ],
  );
});

bool _isGlobalRoute(String location) =>
    location.startsWith('/project') || location.startsWith('/task');

String? _redirect(Ref ref, GoRouterState state) {
  final location = state.matchedLocation;
  final loggingIn = location == '/login' || location == '/signup';

  final authAsync = ref.read(authStateChangesProvider);
  if (authAsync.isLoading) {
    return location == '/splash' ? null : '/splash';
  }

  final user = authAsync.value;
  if (user == null) {
    return loggingIn ? null : '/login';
  }

  final employeeAsync = ref.read(currentEmployeeProvider);
  if (employeeAsync.isLoading) {
    return location == '/splash' ? null : '/splash';
  }

  final employee = employeeAsync.value;
  if (employee == null) {
    // Auth succeeded but the employee doc hasn't resolved (or doesn't exist) —
    // treat like not-yet-authorized, keep at login rather than a half-built shell.
    return loggingIn ? null : '/login';
  }

  final isManagerRoute = location.startsWith('/manager');
  final isEmployeeRoute = location.startsWith('/employee');

  if (employee.isManager) {
    if (loggingIn || location == '/splash' || (!isManagerRoute && !_isGlobalRoute(location))) {
      return '/manager';
    }
  } else {
    if (loggingIn || location == '/splash' || (!isEmployeeRoute && !_isGlobalRoute(location))) {
      return '/employee';
    }
  }

  return null;
}

class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Ref ref) {
    ref.listen(authStateChangesProvider, (previous, next) => notifyListeners());
    ref.listen(currentEmployeeProvider, (previous, next) => notifyListeners());
  }
}

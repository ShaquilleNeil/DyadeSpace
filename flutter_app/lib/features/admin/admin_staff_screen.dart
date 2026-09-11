import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/employee.dart';
import '../../providers/employees_providers.dart';
import '../../providers/invite_providers.dart';
import '../../providers/projects_providers.dart';
import '../../utils/friendly_error.dart';
import '../shared/widgets/employee_card.dart';
import '../shared/widgets/invite_staff_form.dart';
import '../shared/widgets/search_field.dart';
import '../shared/widgets/staff_edit_form.dart';

/// Admin's staff directory — every employee, with the ability to change
/// their role (worker/manager) and which project(s) they're on.
class AdminStaffScreen extends ConsumerStatefulWidget {
  const AdminStaffScreen({super.key});

  @override
  ConsumerState<AdminStaffScreen> createState() => _AdminStaffScreenState();
}

class _AdminStaffScreenState extends ConsumerState<AdminStaffScreen> {
  String _query = '';
  bool _showClients = false;

  void _openInviteSheet() {
    final allProjects = ref.read(visibleProjectsProvider).value ?? const [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => InviteStaffForm(
        allProjects: allProjects,
        onSave: (firstName, lastName, email, role, projectIds) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref.read(inviteControllerProvider).inviteStaff(
                  firstName: firstName,
                  lastName: lastName,
                  email: email,
                  role: role,
                  projectIds: projectIds,
                );
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text('Invite sent to $email')),
            );
          } on InviteEmailFailedException {
            // The account was created — only the reset email failed to
            // send — so close the sheet like a success, but say so.
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '$email was added, but the invite email could not be sent. '
                  'Ask them to use "Forgot password?" on the login screen.',
                ),
              ),
            );
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not send invite. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _openEditSheet(Employee employee) {
    final allProjects = ref.read(visibleProjectsProvider).value ?? const [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StaffEditForm(
        employee: employee,
        allProjects: allProjects,
        onSave: (role, projectIds) async {
          try {
            final admin = ref.read(employeeAdminControllerProvider);
            if (role != employee.role) {
              await admin.updateRole(employee.id, role);
            }
            await admin.setProjects(
              employee.id,
              currentProjectIds: employee.projectIds,
              newProjectIds: projectIds,
            );
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not update staff member. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(visibleEmployeesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Directory'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: 'Invite staff',
            onPressed: _openInviteSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Staff')),
                  ButtonSegment(value: true, label: Text('Clients')),
                ],
                selected: {_showClients},
                onSelectionChanged: (selection) =>
                    setState(() => _showClients = selection.first),
              ),
            ),
            SearchField(onChanged: (value) => setState(() => _query = value)),
            Expanded(
              child: employeesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
                data: (allEmployees) {
                  final employees =
                      allEmployees.where((e) => e.isClient == _showClients).toList();
                  final query = _query.toLowerCase();
                  final displayed = query.trim().isEmpty
                      ? employees
                      : employees
                          .where((e) =>
                              e.fullName.toLowerCase().contains(query) ||
                              e.role.toLowerCase().contains(query))
                          .toList();

                  if (displayed.isEmpty) {
                    return const Center(child: Text('No employees found'));
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 170,
                    ),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final emp = displayed[index];
                      final countAsync = ref.watch(activeTaskCountProvider(emp.id));
                      return EmployeeCard(
                        employee: emp,
                        taskCount: countAsync.value ?? 0,
                        actionIcon: Icons.edit,
                        onAddTask: emp.isAdmin ? () {} : () => _openEditSheet(emp),
                        onTap: () => context.push('/staff/${emp.id}'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

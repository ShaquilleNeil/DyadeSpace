import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/employee.dart';
import '../../../providers/auth_providers.dart';

/// Shared by ManagerProfileScreen and EmployeeProfileScreen — the two were
/// pixel-identical Kotlin screens differing only in which shell they lived
/// under, so this single widget replaces both.
class ProfileView extends ConsumerStatefulWidget {
  const ProfileView({super.key});

  @override
  ConsumerState<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<ProfileView> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  bool _isEditing = false;
  File? _pickedImage;
  Employee? _loadedEmployee;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _loadFrom(Employee employee) {
    _loadedEmployee = employee;
    _firstName.text = employee.firstName;
    _lastName.text = employee.lastName ?? '';
    _email.text = employee.email ?? '';
    _phone.text = employee.phone ?? '';
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return employeeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (employee) {
        if (employee == null) {
          return const Center(child: Text('No profile found'));
        }
        if (_loadedEmployee?.id != employee.id) {
          _loadFrom(employee);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _pickedImage != null
                  ? CircleAvatar(radius: 60, backgroundImage: FileImage(_pickedImage!))
                  : CircleAvatar(
                      radius: 60,
                      backgroundImage: (employee.avatarUrl?.isNotEmpty ?? false)
                          ? NetworkImage(employee.avatarUrl!)
                          : null,
                      child:
                          (employee.avatarUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person, size: 60),
                    ),
              if (_isEditing) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: _pickImage, child: const Text('Upload Image')),
              ],
              const SizedBox(height: 20),
              Text('${_firstName.text} ${_lastName.text}', style: Theme.of(context).textTheme.headlineSmall),
              Text(
                _email.text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (_isEditing) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _firstName,
                        decoration: const InputDecoration(labelText: 'First Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lastName,
                        decoration: const InputDecoration(labelText: 'Last Name'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _phone,
                readOnly: !_isEditing,
                enabled: _isEditing,
                decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  if (_isEditing) {
                    ref.read(authControllerProvider).updateEmployee(
                          employee.copyWith(
                            firstName: _firstName.text,
                            lastName: _lastName.text,
                            phone: _phone.text,
                            email: _email.text,
                          ),
                          newAvatarFile: _pickedImage,
                        );
                  }
                  setState(() => _isEditing = !_isEditing);
                },
                icon: Icon(_isEditing ? Icons.save : Icons.edit),
                label: Text(_isEditing ? 'Save Changes' : 'Edit Profile'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(authControllerProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          ),
        );
      },
    );
  }
}

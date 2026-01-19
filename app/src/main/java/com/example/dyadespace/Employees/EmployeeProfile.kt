package com.example.dyadespace.Employees

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import com.example.dyadespace.R
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.manager.ManagerProfile
import com.example.dyadespace.ui.theme.DyadeSpaceTheme

@Composable
fun EmployeeProfile(viewModel: AuthViewModel, mainNavController: NavController){

    var email by remember { mutableStateOf("") }
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var role by remember { mutableStateOf("") }
    var isEditing by remember { mutableStateOf(false) }

    var imageUri by remember { mutableStateOf<Uri?>(null) }

    LaunchedEffect(Unit) {
        viewModel.fetchRole()
        viewModel.fetchCurrentEmployee()
    }

    val employee by viewModel.currentEmployee.collectAsState()

    // Load employee into UI state safely
    LaunchedEffect(employee) {
        employee?.let {
            firstName = it.Employee_fn.orEmpty()
            lastName = it.Employee_ln.orEmpty()
            email = it.Employee_email.orEmpty()
            phone = it.Employee_phone.orEmpty()
            role = it.role.orEmpty()

            imageUri = it.Avatar_url
                ?.takeIf { url -> url.isNotBlank() }
                ?.let { Uri.parse(it) }
        }
    }

    // ✅ Modern photo picker (NO permissions required)
    val imagePickerLauncher = rememberLauncherForActivityResult(
        contract = PickVisualMedia()
    ) { uri ->
        imageUri = uri
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    )
    {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp)
        )
        {

            // Avatar
            if (imageUri == null) {
                Icon(
                    imageVector = Icons.Default.Person,
                    contentDescription = "Default Avatar",
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                AsyncImage(
                    model = imageUri,
                    contentDescription = "Profile Image",
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape),
                    contentScale = ContentScale.Crop
                )
            }

            if (isEditing) {
                Button(
                    onClick = {
                        imagePickerLauncher.launch(
                            PickVisualMediaRequest(PickVisualMedia.ImageOnly)
                        )
                    },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Upload Image")
                }
            }

            Text(
                "$firstName $lastName",
                style = MaterialTheme.typography.headlineSmall
            )

            Text(
                email,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (isEditing) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    OutlinedTextField(
                        value = firstName,
                        onValueChange = { firstName = it },
                        label = { Text(stringResource(R.string.firstname)) },
                        modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        value = lastName,
                        onValueChange = { lastName = it },
                        label = { Text(stringResource(R.string.lastname)) },
                        modifier = Modifier.weight(1f)
                    )
                }

                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text(stringResource(R.string.email)) },
                    leadingIcon = {
                        Icon(Icons.Default.Email, contentDescription = null)
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }

            OutlinedTextField(
                value = phone,
                onValueChange = { if (isEditing) phone = it },
                label = { Text(stringResource(R.string.phone)) },
                leadingIcon = {
                    Icon(Icons.Default.Phone, contentDescription = null)
                },
                readOnly = !isEditing,
                enabled = isEditing,
                modifier = Modifier.fillMaxWidth()
            )

            Button(
                onClick = {
                    if (isEditing) {
                        val updatedEmployee = employee?.copy(
                            Employee_fn = firstName,
                            Employee_ln = lastName,
                            Employee_phone = phone,
                            Employee_email = email,
                            role = role,
                            Avatar_url = imageUri?.toString()
                        )
                        viewModel.updateEmployee(updatedEmployee, imageUri)
                    }
                    isEditing = !isEditing
                },
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp)
            ) {
                Icon(
                    imageVector = if (isEditing) Icons.Default.Save else Icons.Default.Edit,
                    contentDescription = null
                )
                Spacer(Modifier.width(8.dp))
                Text(if (isEditing) stringResource(R.string.savechanges) else stringResource(R.string.editprofile))
            }

            Button(
                onClick = {
                    viewModel.signOut()
                    mainNavController.navigate("login") {
                        popUpTo(0) { inclusive = true }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.error
                )
            ) {
                Icon(Icons.Default.ExitToApp, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.logout))
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
fun EmployeeProfilePreview(){
    DyadeSpaceTheme {
        EmployeeProfile(
            viewModel = AuthViewModel().apply {
                setFakeEmployee(
                    Employee(
                        EID = "123",
                        Employee_fn = "Shaq",
                        Employee_ln = "Neil",
                        Employee_phone = "123-4567",
                        Employee_email = "shaq@mail.com",
                        role = "employee",
                        Avatar_url = "https://ui-avatars.com/api/?name=Shaq+Neil",
                        created_at = "Now"
                    )
                )
            },
            mainNavController = rememberNavController()
        )
    }
}
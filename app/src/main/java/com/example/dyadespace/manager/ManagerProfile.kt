package com.example.dyadespace.manager

import android.content.Intent
import android.provider.MediaStore
import androidx.compose.runtime.Composable

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.app.Activity
import android.net.Uri
import androidx.compose.material3.LocalTextStyle
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavController


@Composable
fun ManagerProfile(viewModel: AuthViewModel, mainNavController: NavController){

    var email by remember { mutableStateOf("") }
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var isEditing by remember { mutableStateOf(false) }


    // Image picker launcher inside composable
    val imagePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val imageUri: Uri? = result.data?.data
            println("Selected image URI: $imageUri")
            // TODO → Upload to Supabase Storage next
        }
    }



    LaunchedEffect(Unit) {
        viewModel.fetchRole { }
    }

    val employee = viewModel.currentEmployee.collectAsState().value


    //load employee into ui state to assign to variables
    LaunchedEffect(employee) {
        employee?.let {
            firstName = it.Employee_fn ?: ""
            lastName = it.Employee_ln ?: ""
            email = it.Employee_email ?: ""
            phone = it.Employee_phone ?: ""
        }
    }



    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),


    ) {

        if (isEditing) {
            Button(
                onClick = {
                    val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    imagePickerLauncher.launch(intent)


                },
                modifier = Modifier.fillMaxWidth()

            ){
                Text("Upload Image")
            }
        }


        OutlinedTextField(
            value = firstName,
            onValueChange = {if (isEditing) firstName = it },
            readOnly = !isEditing,
            enabled = isEditing,
            label = { Text("First Name") },
            textStyle = LocalTextStyle.current.copy(color = Color.Black),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = lastName,
            onValueChange = { if (isEditing) lastName = it },
            readOnly = !isEditing,
            enabled = isEditing,
            label = { Text("Last Name") },
            textStyle = LocalTextStyle.current.copy(color = Color.Black),   // text color
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = email,
            onValueChange = { if (isEditing) email = it },
            label = { Text("Email") },
            readOnly = !isEditing,
            enabled = isEditing,
            textStyle = LocalTextStyle.current.copy(color = Color.Black),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = phone,
            onValueChange = {if (isEditing) phone = it },
            label = { Text("Phone") },
            readOnly = !isEditing,
            enabled = isEditing,
            textStyle = LocalTextStyle.current.copy(color = Color.Black),
            modifier = Modifier.fillMaxWidth()
        )


        Button(
            onClick = {
                isEditing = !isEditing
            },
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (isEditing) "Save" else "Edit")
        }

        Button(
            onClick = {
                viewModel.signOut()
                viewModel.setMessage("Logged out")

                mainNavController.navigate("login") {
                    popUpTo(0) { inclusive = true }
                    launchSingleTop = true
                }
            },
            modifier = Modifier.fillMaxWidth(),
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error
            )
        ) {
            Text("Logout")
        }





    }
}


//preview
@Preview(showBackground = true)
@Composable
fun ManagerProfilePreview() {
    val fakeVM = AuthViewModel().apply {
        setFakeEmployee(
            Employee(
                EID = "123",
                Employee_fn = "Shaq",
                Employee_ln = "Neil",
                Employee_phone = "123-4567",
                Employee_email = "shaq@mail.com",
                role = "manager",
                Avatar_url = null,
                created_at = "Now"
            )
        )
    }
    ManagerProfile(viewModel = fakeVM,  mainNavController = NavController(LocalContext.current))
}
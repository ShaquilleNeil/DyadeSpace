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
import android.content.res.Configuration
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Surface
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import com.example.dyadespace.ui.theme.DyadeSpaceTheme


@Composable
fun ManagerProfile(viewModel: AuthViewModel, mainNavController: NavController){

    var email by remember { mutableStateOf("") }
    var firstName by remember { mutableStateOf("") }
    var lastName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var isEditing by remember { mutableStateOf(false) }
    var role by remember { mutableStateOf("") }
    var imageUri by remember { mutableStateOf<Uri?>(null) }



    LaunchedEffect(Unit) {
        viewModel.fetchRole { }
        viewModel.fetchCurrentEmployee()
    }

    val employee = viewModel.currentEmployee.collectAsState().value


    //load employee into ui state to assign to variables
    LaunchedEffect(employee) {
        employee?.let {

            firstName = it.Employee_fn ?: ""
            lastName = it.Employee_ln ?: ""
            email = it.Employee_email ?: ""
            phone = it.Employee_phone ?: ""
            role = it.role ?: ""

            imageUri = Uri.parse(it.Avatar_url)
        }
    }

    val imagePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val selectedUri = result.data?.data
            imageUri = selectedUri     // <-- store result here
            println("Selected image URI: $selectedUri")

            // Later: Upload to Supabase Storage

        }
    }


    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).safeDrawingPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),



    ) {
        if (imageUri == null) {
            Icon(
                imageVector = Icons.Default.Person,
                contentDescription = "Default Avatar",
                modifier = Modifier
                    .size(120.dp)
                    .padding(8.dp)
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
                    .padding(8.dp)
                    .clip(CircleShape)
                ,
                contentScale = ContentScale.Crop
            )
        }


        if (isEditing) {
            Button(
                onClick = {
                    val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                    imagePickerLauncher.launch(intent)

                    //store the image uri


                },
                modifier = Modifier.fillMaxWidth()

            ){
                Text("Upload Image", color = MaterialTheme.colorScheme.onSurface)
            }
        }

        Text(firstName + " " + lastName, style = MaterialTheme.typography.headlineSmall)
        Text(email, style = MaterialTheme.typography.bodyMedium,
            color = Color.Gray)



        if (isEditing) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {

                OutlinedTextField(
                    value = firstName,
                    onValueChange = {if (isEditing) firstName = it },
                    readOnly = !isEditing,
                    enabled = isEditing,
                    label = { Text("First Name") },
                    textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface),
                    modifier = Modifier.weight(1f)
                )
                OutlinedTextField(
                    value = lastName,
                    onValueChange = { if (isEditing) lastName = it },
                    readOnly = !isEditing,
                    enabled = isEditing,
                    label = { Text("Last Name") },
                    textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface),   // text color
                    modifier = Modifier.weight(1f)
                )
            }

            OutlinedTextField(
                value = email,
                onValueChange = { if (isEditing) email = it },
                label = { Text("Email", color = MaterialTheme.colorScheme.onSurface) },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Email,
                        contentDescription = "Person Icon",
                        tint = MaterialTheme.colorScheme.onSurface
                    )
                },
                readOnly = !isEditing,
                enabled = isEditing,
                textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface),
                modifier = Modifier.fillMaxWidth()
            )

        }




        OutlinedTextField(
            value = phone,
            onValueChange = {if (isEditing) phone = it },
            label = { Text("Phone", color = MaterialTheme.colorScheme.onSurface) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Default.Phone,
                    contentDescription = "Person Icon",
                    tint = MaterialTheme.colorScheme.onSurface
                )
            },
            readOnly = !isEditing,
            enabled = isEditing,
            textStyle = LocalTextStyle.current.copy(color = MaterialTheme.colorScheme.onSurface),
            modifier = Modifier.fillMaxWidth()
        )




        Button(
            onClick = {
                if (isEditing) {
                    // <- only update when we are SAVING
                    val updatedEmployee = employee?.copy(
                        Employee_fn = firstName,
                        Employee_ln = lastName,
                        Employee_phone = phone,
                        Employee_email = email,
                        role = role,   // if role is editable
                        Avatar_url = imageUri?.toString()
                    )
                    viewModel.updateEmployee(updatedEmployee, imageUri)
                    viewModel.setMessage("Update successful")

                }

                isEditing = !isEditing // <-- toggle after save logic
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(20),
            elevation = ButtonDefaults.buttonElevation(
                defaultElevation = 10.dp,
                pressedElevation = 15.dp,
                disabledElevation = 0.dp),
        ) {
            if (isEditing) {
                Icon(
                    imageVector = Icons.Default.Save,
                    contentDescription = "Save Icon",
                    modifier = Modifier.size(20.dp),
                    tint = Color.White)
            } else {
                Icon(
                    imageVector = Icons.Default.Edit,
                    contentDescription = "Edit Icon",
                    modifier = Modifier.size(20.dp),
                    tint = Color.White
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            Text(if (isEditing) "Save Changes" else "Edit Profile")
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
            shape = RoundedCornerShape(20),
            elevation = ButtonDefaults.buttonElevation(
                defaultElevation = 10.dp,
                pressedElevation = 15.dp,
                disabledElevation = 0.dp),
            modifier = Modifier.fillMaxWidth(),
            colors = androidx.compose.material3.ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error
            )
        ) {
            Icon(
                imageVector = Icons.Default.ExitToApp,
                contentDescription = "Person Icon",
                modifier = Modifier.size(20.dp),
                tint = Color.White
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text("Logout", color = Color.White)
        }





    }
}


//preview
@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun ManagerProfilePreview() {

    DyadeSpaceTheme() {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            val fakeVM = AuthViewModel().apply {
                setFakeEmployee(
                    Employee(
                        EID = "123",
                        Employee_fn = "Shaq",
                        Employee_ln = "Neil",
                        Employee_phone = "123-4567",
                        Employee_email = "shaq@mail.com",
                        role = "manager",
                        Avatar_url = "https://ui-avatars.com/api/?name=Shaq+Neil&background=0F172A&color=FFFFFF&size=256",
                        created_at = "Now"
                    )
                )
            }

            ManagerProfile(
                viewModel = fakeVM,
                mainNavController = rememberNavController()
            )
        }
    }


}
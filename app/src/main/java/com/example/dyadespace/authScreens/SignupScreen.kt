package com.example.dyadespace.authScreens


import android.content.res.Configuration
import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import com.example.dyadespace.ui.theme.DyadeSpaceTheme


@Composable //@Composable marks a function that produces UI instead of returning a value.
fun SignupScreen(navController: NavController, viewModel: AuthViewModel){
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {


        Column( //basically a vstack, Row is the hstack and box is the zstack
            modifier = Modifier.fillMaxSize()
                .padding(24.dp), //describe show an element behaves or looks
            verticalArrangement = Arrangement.Center
        )
        {
            //add state variables
            //remember {mutableStateof) = This creates a variable that Compose can watch for changes.
            var firstName by remember { mutableStateOf("") }
            var lastName by remember { mutableStateOf("") }
            var phone by remember { mutableStateOf("") }
            var email by remember { mutableStateOf("") }
            var password by remember { mutableStateOf("") }
            var confirmPassword by remember { mutableStateOf("") }
            val message by viewModel.authMessage.collectAsState() //oberve viewmodel messages


            Text(
                "Create Account",
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )

            Spacer(Modifier.height(20.dp))

            //form fields
            OutlinedTextField(
                value = firstName,
                onValueChange = { firstName = it },
                label = { Text("First Name", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()


            )

            OutlinedTextField(
                value = lastName,
                onValueChange = { lastName = it },
                label = { Text("Last Name", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = phone,
                onValueChange = { phone = it },
                label = { Text("Phone", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()
            )


            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()

            )

            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = confirmPassword,
                onValueChange = { confirmPassword = it },
                label = { Text("Confirm Password", color = MaterialTheme.colorScheme.onSurface) },
                modifier = Modifier.fillMaxWidth()
            )

            Button(
                onClick = {
                    if (password == confirmPassword) {
                        viewModel.signUp(firstName, lastName, phone, "employee", email, password)
                    } else {
                        viewModel.authMessage.value = "Passwords do not match"
                    }
                },
                modifier = Modifier.width(200.dp).padding(top = 16.dp)
                    .align(Alignment.CenterHorizontally),
                shape = MaterialTheme.shapes.medium,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.Blue,
                    contentColor = MaterialTheme.colorScheme.onSurface
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = 10.dp,
                    pressedElevation = 15.dp,
                    disabledElevation = 0.dp
                )

            ) {
                Text("Sign Up", color = Color.White, fontSize = 16.sp)

            }

            LaunchedEffect(message) {
                if (message == "Sign up successful") {
                    navController.navigate("login")

                }

            }

            Spacer(Modifier.height(16.dp))

            viewModel.authMessage.value?.let {
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.primary
                )
            }


        }

    }
}



@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun SignUpPreview() {
    val fakeNav = rememberNavController()
    val vm = AuthViewModel() // temporary ViewModel instance for preview

    DyadeSpaceTheme() {
        Surface(
            color = MaterialTheme.colorScheme.background
        ) {
            SignupScreen(
                navController = fakeNav,
                viewModel = vm
            )

        }
        }
}
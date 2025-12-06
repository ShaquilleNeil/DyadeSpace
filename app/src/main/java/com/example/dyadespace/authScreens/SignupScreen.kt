package com.example.dyadespace.authScreens


import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController


@Composable //@Composable marks a function that produces UI instead of returning a value.
fun SignupScreen(navController: NavController, viewModel: AuthViewModel){
    Column( //basically a vstack, Row is the hstack and box is the zstack
        modifier = Modifier.fillMaxSize().padding(24.dp), //describe show an element behaves or looks
        verticalArrangement = Arrangement.Center
    ){
        //add state variables
        //remember {mutableStateof) = This creates a variable that Compose can watch for changes.
        var firstName by remember { mutableStateOf("") }
        var lastName by remember { mutableStateOf("") }
        var phone by remember { mutableStateOf("") }
        var email by remember { mutableStateOf("") }
        var password by remember { mutableStateOf("") }
        var confirmPassword by remember { mutableStateOf("") }
        val message by viewModel.authMessage.collectAsState() //oberve viewmodel messages


        Text("Create Account", style = MaterialTheme.typography.headlineMedium
        , modifier = Modifier.align(Alignment.CenterHorizontally))

        Spacer(Modifier.height(20.dp))

        //form fields
        OutlinedTextField(
            value = firstName,
            onValueChange = { firstName = it },
            label = { Text("First Name") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = lastName,
            onValueChange = { lastName = it },
            label = { Text("Last Name") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = phone,
            onValueChange = { phone = it },
            label = { Text("Phone") },
            modifier = Modifier.fillMaxWidth()
        )


        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email") },
            modifier = Modifier.fillMaxWidth()

        )

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = confirmPassword,
            onValueChange = { confirmPassword = it },
            label = { Text("Confirm Password") },
            modifier = Modifier.fillMaxWidth()
        )

        Button(
            onClick = {
                if(password == confirmPassword){
                    viewModel.signUp(firstName, lastName, phone, "employee", email, password)
                } else {
                    viewModel.authMessage.value = "Passwords do not match"
                }
            },
            modifier = Modifier.width(200.dp)
                .align(Alignment.CenterHorizontally)
                .padding(top = 16.dp)
        ) {
            Text("Sign Up", color = MaterialTheme.colorScheme.onPrimary, fontSize = 16.sp)

        }

        LaunchedEffect(message){
            if (message == "Sign up successful"){
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



@Preview(showBackground = true)
@Composable
fun SignUpPreview() {
    val fakeNav = rememberNavController()
    val vm = AuthViewModel() // temporary ViewModel instance for preview
    SignupScreen(
        navController = fakeNav,
        viewModel = vm
    )
}
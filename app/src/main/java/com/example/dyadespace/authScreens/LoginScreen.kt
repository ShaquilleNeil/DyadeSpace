package com.example.dyadespace.authScreens

import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Alignment
import androidx.compose.ui.tooling.preview.Preview
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController


@Composable
fun LoginScreen(navController: NavController, viewModel: AuthViewModel) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    val message: String? by viewModel.authMessage.collectAsState()
//oberve viewmodel messages



    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Login", style = MaterialTheme.typography.headlineMedium)

        Spacer(Modifier.height(20.dp))


        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email") },
            modifier = Modifier.fillMaxWidth())

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            modifier = Modifier.fillMaxWidth()

        )

        Button(
            onClick = {
                if (email.isNotEmpty() && password.isNotEmpty()) {
                    viewModel.logIn(email, password)   // Just trigger login, no nav here
                } else {
                    viewModel.setMessage("Please enter email and password")
                }
            },
            modifier = Modifier.width(200.dp).padding(top = 16.dp)
        ) {
            Text("Login")
        }


        // 🔥 Wait for auth result and navigate when success happens
        LaunchedEffect(message) {
            if (message == "Sign in successful") {

                // Reset message so it doesn't trigger again later
                viewModel.setMessage(null)

                viewModel.fetchRole { employee ->
                    if (employee?.role == "manager") {
                        navController.navigate("manager") {
                            popUpTo("login") { inclusive = true }
                            launchSingleTop = true
                        }
                    } else {
                        navController.navigate("TestConnectionScreen") {
                            popUpTo("login") { inclusive = true }
                            launchSingleTop = true
                        }
                    }
                }
            }
        }




        Spacer(Modifier.height(16.dp))


//        val message = viewModel.authMessage.collectAsState().value // Listens for updates coming from ViewModel
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }

        //link to sign up screen

        TextButton(
            onClick = {
                navController.navigate("signup")
            }

        ){
            Text("Create Account")
        }

    }


}













@Preview(showBackground = true)
@Composable
fun LoginPreview() {

    val fakeNav = rememberNavController()      // create mock controller
    val vm = AuthViewModel()                   // create viewmodel for preview

    LoginScreen(
        navController = fakeNav,
        viewModel = vm
    )
}


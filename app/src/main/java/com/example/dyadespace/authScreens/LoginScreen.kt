package com.example.dyadespace.authScreens

import androidx.compose.runtime.*
import androidx.compose.material3.*
import androidx.compose.foundation.layout.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.OutlinedTextField




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
        Text("Login",
            style = MaterialTheme.typography.headlineMedium,
            color = Color.Black,
            modifier = Modifier.padding(bottom = 16.dp))

        Spacer(Modifier.height(20.dp))


        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("Email", color = Color.Black) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            textStyle = LocalTextStyle.current.copy(color = Color.Black),
            colors = TextFieldDefaults.colors(
                focusedIndicatorColor = Color.Black,
                unfocusedIndicatorColor = Color.Black,
            )


        )



        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text("Password") },
            modifier = Modifier.fillMaxWidth(),
            textStyle = LocalTextStyle.current.copy(color = Color.Black),
//            colors = TextFieldDefaults.colors(
//                focusedIndicatorColor = Color.Black,
//                unfocusedIndicatorColor = Color.Black,
//                focusedLabelColor = Color.Black,
//                unfocusedLabelColor = Color.Black,
//                cursorColor = Color.Black,
//                focusedTextColor = Color.Black,
//                unfocusedTextColor = Color.Black
//            )

        )

        Button(
            onClick = {
                if (email.isNotEmpty() && password.isNotEmpty()) {
                    viewModel.logIn(email, password)   // Just trigger login, no nav here
                } else {
                    viewModel.setMessage("Please enter email and password")
                }
            },
            modifier = Modifier.width(200.dp).padding(top = 16.dp),
            shape = MaterialTheme.shapes.medium,
            colors = ButtonDefaults.buttonColors(
                containerColor = Color.Blue,
                contentColor = Color.White
            ),
            elevation = ButtonDefaults.buttonElevation(
                defaultElevation = 10.dp,
                pressedElevation = 15.dp,
                disabledElevation = 0.dp)

        ) {
            Text("Login")
        }


        // 🔥 Wait for auth result and navigate when success happens
        val isLoggedIn by viewModel.isLoggedIn

        LaunchedEffect(isLoggedIn) {
            if (isLoggedIn) {
                viewModel.fetchRole { role ->
                    when (role?.role) {
                        "manager" -> navController.navigate("manager") {
                            popUpTo("login") { inclusive = true }
                        }
                        "employee" -> navController.navigate("TestConnectionScreen") {
                            popUpTo("login") { inclusive = true }
                        }
                        else -> {
                            viewModel.setMessage("Account not configured")
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


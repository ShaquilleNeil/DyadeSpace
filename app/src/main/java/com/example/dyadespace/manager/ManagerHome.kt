package com.example.dyadespace.manager

import android.R
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import coil.compose.AsyncImage




@Composable
fun ManagerHome(viewModel: AuthViewModel){

    //runs once the screen loads to fire the fetch role again
    LaunchedEffect(Unit) {
        viewModel.fetchRole { }
    }
    val employee = viewModel.currentEmployee.collectAsState().value
    println("🟢 ManagerHome employee = $employee")


    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState())

    ){
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(
                    model = employee?.Avatar_url ?: "",
                    contentDescription = "Avatar",
                    modifier = Modifier.size(80.dp).clip(CircleShape),
                    contentScale = ContentScale.Crop
                )

                Spacer(modifier = Modifier.width(16.dp))

                Column {
                    Text("${employee?.Employee_fn} ${employee?.Employee_ln}", style = MaterialTheme.typography.titleMedium)
                    Text(employee?.role ?: "none", color = Color.Gray, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            Text("Email: ${employee?.Employee_email}")
            Spacer(modifier = Modifier.weight(1f))
            Text("Phone: ${employee?.Employee_phone}")
        }

        Text("Quick Actions", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp))
        Row(modifier = Modifier.fillMaxWidth()) {
            Button(onClick = { /*TODO*/ }, modifier = Modifier.weight(1f)
                .clip(CircleShape)) {
                Text("Projects")
            }
            Button(onClick = { /*TODO*/ }, modifier = Modifier.weight(1f)
                .clip(CircleShape)) {
                Text("Projects")
            }
            Button(onClick = { /*TODO*/ }, modifier = Modifier.weight(1f)
                .clip(CircleShape)) {
                Text("Projects")
            }
            Button(onClick = { /*TODO*/ }, modifier = Modifier.weight(1f)
                .clip(CircleShape)) {
                Text("Projects")
            }

        }

        Text("Recent Tasks", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 24.dp))
//        LazyColumn(modifier = Modifier.fillMaxWidth()) {}


    }
}


@Preview(showBackground = true)
@Composable
fun ManagerHomePreview() {
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

    ManagerHome(viewModel = fakeVM)
}

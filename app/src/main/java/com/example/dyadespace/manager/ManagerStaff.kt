package com.example.dyadespace.manager

import android.content.res.Configuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.example.dyadespace.R
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.ui.theme.DyadeSpaceTheme
import com.example.dyadespace.viewitems.EmployeeCard


@Composable
fun ManagerStaff(
    authViewModel: AuthViewModel,
    taskViewModel: TaskViewModel,
    navController: NavController
){
    LaunchedEffect(Unit){
        authViewModel.fetchAllEmployees()
    }

    val employees = authViewModel.employees.collectAsState().value

    ManagerStaffContent(employees, taskViewModel)
}

@Composable
fun ManagerStaffContent(employees: List<Employee>, taskViewModel: TaskViewModel? = null) {

    var searchQuery by remember { mutableStateOf("") }
    val taskCounts = remember {mutableStateOf<Map<String, Int>>(emptyMap())}

    LaunchedEffect(employees) {

        if (taskViewModel == null) return@LaunchedEffect

        val newMap = mutableMapOf<String, Int>()

        employees.forEach { emp ->
            val count = taskViewModel.getActiveTaskCountForEmployee(emp.EID)
            newMap[emp.EID] = count
        }

        taskCounts.value = newMap
    }

    // ✅ Correct employee filtering
    val filteredEmployees = employees.filter { emp ->
        val fullName = "${emp.Employee_fn} ${emp.Employee_ln}"
        fullName.contains(searchQuery, ignoreCase = true) ||
                (emp.role?.contains(searchQuery, ignoreCase = true) ?: false)
    }

    val displayedEmployees =
        if (searchQuery.isBlank()) employees else filteredEmployees


    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(2.dp)
    ) {

        Text(
            text = "Staff Directory",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier
                .padding(top = 10.dp, bottom = 10.dp)
                .align(Alignment.CenterHorizontally)

        )

        // 🔎 Search bar
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 4.dp),
            shape = RoundedCornerShape(12.dp),
            elevation = CardDefaults.cardElevation(0.dp)
        )
        {
            TextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(44.dp),
                placeholder = {
                    Text(
                        text = stringResource(R.string.search),
                        style = MaterialTheme.typography.bodySmall
                    )
                },
                leadingIcon = {
                    Icon(
                        Icons.Filled.Search,
                        contentDescription = null
                    )
                },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,

                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,

                    cursorColor = MaterialTheme.colorScheme.primary
                ),
                textStyle = MaterialTheme.typography.bodySmall
            )
        }

        Spacer(
            modifier = Modifier
                .fillMaxWidth()
                .height(15.dp)
        )
        Divider()


        // 👥 Employee grid
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            contentPadding = PaddingValues(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            items(displayedEmployees.size) { index ->
                val emp = displayedEmployees[index]

                EmployeeCard(
                    emp = emp,
                    taskCount = taskCounts.value[emp.EID] ?: 0
                )
            }
        }
    }
}



@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(showBackground = true, name = "Dark", uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
fun ManagerStaffPreview() {

    val fakeEmployees = listOf(
        Employee("1","Alex","Rivera","", "", "Manager","https://picsum.photos/200"),
        Employee("2","Sarah","Chen","", "", "Shift Lead","https://picsum.photos/201"),
        Employee("3","Jordan","Smith","", "", "Barista","https://picsum.photos/202"),
        Employee("4","Maria","Garcia","", "", "Operations","https://picsum.photos/203"),
        Employee("5","Liam","Wilson","", "", "Inventory","https://picsum.photos/204"),
        Employee("6","Taylor","Reed","", "", "Kitchen","https://picsum.photos/205")
    )

    DyadeSpaceTheme {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            ManagerStaffContent(
                employees = fakeEmployees,
            )
        }
    }
}
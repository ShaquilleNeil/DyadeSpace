package com.example.dyadespace.manager

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PlaylistAdd
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.viewitems.EmployeeItem
import com.example.dyadespace.viewitems.TaskForm
import com.example.dyadespace.viewitems.TaskItem
import io.github.jan.supabase.realtime.Column


/* ---------------------------------------------------
   UI-ONLY COMPOSABLE (PREVIEWABLE)
--------------------------------------------------- */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectViewUi(project: Projects, employees: List<Employee>, tasks: List<Tasks>, allEmployees: List<Employee> , viewModel: AuthViewModel) {

    var employeesExpanded by remember { mutableStateOf(false) }
    var tasksExpanded by remember { mutableStateOf(false) }
    val tabs = listOf( "To-Do", "In Progress", "Done")
    var selectedTab by remember { mutableStateOf(0) }
    var expanded by remember { mutableStateOf(false) }
    var dropdownExpanded by remember { mutableStateOf(false) }
    var selectedEmployee by remember { mutableStateOf<Employee?>(null) }


    //state tha controls the sheet
     val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = false
    )

    var showSheet by remember { mutableStateOf(false) }
    var showtaskform by remember { mutableStateOf(false) }






    val filteredTasks = remember(selectedTab, tasks) {
        when (tabs[selectedTab]) {
            "To-Do" -> tasks.filter { it.status == "todo" }
            "In Progress" -> tasks.filter { it.status == "in-progress" }
            "Done" -> tasks.filter { it.status == "done" }
            else -> tasks
        }
    }


    Column(
        modifier = Modifier
            .fillMaxSize()
            .safeDrawingPadding()
            .padding(16.dp),
        horizontalAlignment = Alignment.Start
    ) {



        AsyncImage(
            model = project.photo_url,
            contentDescription = "Project Image",
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp))

        )

        Text(
            text = project.name ?: "Unnamed Project",
            modifier = Modifier
                .padding(bottom = 12.dp)
                .align(Alignment.Start),
            style = MaterialTheme.typography.titleLarge
        )


        Text(

            text = project.address ?: "",
            modifier = Modifier
                .padding(top = 8.dp)
                .align(Alignment.Start),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary,
            fontWeight =  androidx.compose.ui.text.font.FontWeight.Bold
        )

        Text(
            text = project.description ?: "",
            modifier = Modifier.padding(top = 16.dp),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.primary
        )

        HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

        /* ---------- EMPLOYEES HEADER (CLICKABLE) ---------- */
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { employeesExpanded = !employeesExpanded }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Employees (${employees.size})",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )

            Icon(
                imageVector = if (employeesExpanded)
                    Icons.Default.ExpandLess
                else
                    Icons.Default.ExpandMore,
                contentDescription = null
            )
        }

        /* ---------- COLLAPSIBLE EMPLOYEE ROW ---------- */
        AnimatedVisibility(visible = employeesExpanded) {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                items(employees) { emp ->
                    EmployeeItem(emp)
                }
            }
        }

//        HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

        /* ---------- TASKS HEADER ---------- */
        Row (
            modifier = Modifier
                .fillMaxWidth()
                .clickable { tasksExpanded = !tasksExpanded }
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically

        ){
            Text("Tasks (${tasks.size})",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f)
            )



            Icon(
                imageVector = if (tasksExpanded)
                    Icons.Default.ExpandLess
                else
                    Icons.Default.ExpandMore,
                contentDescription = null
            )

        }

        AnimatedVisibility(visible = tasksExpanded) {

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 10.dp)
            ){

                // 🔹 Status picker
                TabRow(selectedTabIndex = selectedTab) {
                    tabs.forEachIndexed { index, title ->
                        Tab(
                            selected = selectedTab == index,
                            onClick = { selectedTab = index },
                            text = { Text(title) },
                            modifier = Modifier.padding(horizontal = 8.dp)
                        )
                    }
                }

                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                    modifier = Modifier
                        .padding(bottom = 16.dp)
                        .fillMaxWidth()
                        .padding(top = 10.dp)
                ) {
                    items(filteredTasks) { tsk ->
                        TaskItem(tsk,
                            modifier = Modifier.fillMaxWidth())
                    }
                }
            }


        }

        Box(modifier = Modifier.fillMaxSize()) {


            Column(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.End
            ){

                AnimatedVisibility(expanded) {

                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.Bottom),
                        horizontalAlignment = Alignment.End

                    )
                    {
                        FloatingActionButton(
                            onClick = {
                                showSheet = true
                            },
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            shape = CircleShape,
                            modifier = Modifier
                                .padding(1.dp)

                        ){
                            Icon(
                                imageVector = Icons.Default.PersonAdd,
                                contentDescription = "Add employee"
                            )

                        }

                        FloatingActionButton(
                            onClick = { showtaskform = true },
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            shape = CircleShape,
                            modifier = Modifier
                                .padding(1.dp)

                        ){
                            Icon(
                                imageVector = Icons.Default.PlaylistAdd,
                                contentDescription = "Add task"
                            )

                        }
                    }
                }


                // 🔹 Main FAB
                FloatingActionButton(
                    onClick = { expanded = !expanded }
                ) {
                    Icon(
                        imageVector = if (expanded)
                            Icons.Default.Close
                        else
                            Icons.Default.Add,
                        contentDescription = "Actions"
                    )
                }

            }


            if(showSheet){
                ModalBottomSheet(
                    onDismissRequest = { showSheet = false },
                    sheetState = sheetState
                ){
                    //content of the sheet
                    //add employee
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp)
                    ){
                        Text("Add Employee to Project",
                        style = MaterialTheme.typography.titleMedium)

                        ExposedDropdownMenuBox(
                            expanded = dropdownExpanded,
                            onExpandedChange = { dropdownExpanded = !dropdownExpanded },
                            modifier = Modifier.fillMaxWidth()

                        ) {
                            TextField(
                                value = selectedEmployee?.let{
                                    "${it.Employee_fn} ${it.Employee_ln}"
                                } ?: "Select Employee",
                                onValueChange = {},
                                readOnly = true,
                                trailingIcon = {
                                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = dropdownExpanded)
                                },
                                modifier = Modifier.menuAnchor().fillMaxWidth()

                            )

                            ExposedDropdownMenu(
                                expanded = dropdownExpanded,
                                onDismissRequest = { dropdownExpanded = false }
                            ) {
//                                Text("DEBUG: ${allEmployees.size} employees")
                                allEmployees.forEach { emp ->
                                    DropdownMenuItem(
                                        text = { Text("${emp.Employee_fn} ${emp.Employee_ln}") },
                                        onClick = {
                                            selectedEmployee = emp
                                            dropdownExpanded = false
                                        }
                                    )

                                }
                            }
                        }

                       ///button to add employee
                        Button(
                            onClick = {
                                if (selectedEmployee != null) {
                                    viewModel.addEmployeeToProject(project.id, selectedEmployee!!.EID)
                                }
                            }

                        ){
                            Text("Add")
                        }


                    }

                }
            }

            if(showtaskform){
                ModalBottomSheet(
                    onDismissRequest = {showtaskform = false},
                    sheetState = rememberModalBottomSheetState()
                ){
                    TaskForm(
                        projectId = project.id!!,
                        allEmployees = allEmployees,
                        onDismiss = { showtaskform = false },
                        onSave = { task ->
                            viewModel.addTask( task)
                            showtaskform = false
                        }
                    )
                }
            }




        }


    }
}

/* ---------------------------------------------------
   RUNTIME SCREEN (NAV + VIEWMODEL)
--------------------------------------------------- */
@Composable
fun ProjectViewContent(
    projectId: String,

    navController: NavController,
    viewModel: AuthViewModel
) {
    LaunchedEffect(projectId) {
        println("🟡 ProjectViewContent projectId = $projectId")
        viewModel.fetchProjectById(projectId)
        viewModel.fetchProjectEmployees(projectId)
        viewModel.fetchProjectTasks(projectId)
        viewModel.fetchAllEmployees()

    }

    val project by viewModel.aproject.collectAsState()
    val employees by viewModel.projectemployees.collectAsState()
    val tasks by viewModel.projectasks.collectAsState()
    val allEmployees by viewModel.employees.collectAsState()




    if (project == null) {
        Text("Loading project…")
    } else {
        ProjectViewUi(project = project!!, employees = employees, tasks = tasks, allEmployees = allEmployees, viewModel = viewModel)
    }
}

/* ---------------------------------------------------
   PREVIEW (FAKE DATA ONLY)
--------------------------------------------------- */
@Preview(showBackground = true)
@Composable
fun ProjectViewPreview() {
    ProjectViewUi(
        project = Projects(
            id = "P123",
            name = "Downtown Office Renovation",
            description = "Complete interior renovation including electrical, drywall, and finishes.",
            address = "Montreal, QC",
            photo_url = "https://picsum.photos/1200/800"
        ),
        employees = listOf(
            Employee(
                EID = "E1",
                Employee_fn = "Shaq",
                Employee_ln = "Neil",
                Employee_phone = "123-4567",
                Employee_email = "shaq@example.com",
                role = "Manager",
                Avatar_url = "https://picsum.photos/200?1"
            ),
            Employee(
                EID = "E2",
                Employee_fn = "Alex",
                Employee_ln = "Martin",
                Employee_phone = "555-9876",
                Employee_email = "alex@example.com",
                role = "Electrician",
                Avatar_url = "https://picsum.photos/200?2"
            )
        ),
        tasks = listOf(
            Tasks(
                id = "T1",
                title = "Install drywall",
                description = "Finish drywall installation on floor 2",
                status = "in_progress",
                deadline = "2023-11-15"
            ),
            Tasks(
                id = "T2",
                title = "Electrical rough-in",
                description = "Run wiring for lighting",
                status = "pending",
                deadline = "2023-11-20"
            )
        ),
        allEmployees = listOf(),
        viewModel = AuthViewModel()

    )
}


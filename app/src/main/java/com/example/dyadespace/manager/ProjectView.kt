package com.example.dyadespace.manager

import android.content.res.Configuration
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
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
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import coil.compose.AsyncImage
import com.example.dyadespace.authScreens.AuthViewModel
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.ui.theme.DyadeSpaceTheme
import com.example.dyadespace.viewitems.EmployeeItem
import com.example.dyadespace.viewitems.TaskForm
import com.example.dyadespace.viewitems.TaskItem
import io.github.jan.supabase.realtime.Column


/* ---------------------------------------------------
   UI-ONLY COMPOSABLE (PREVIEWABLE)
--------------------------------------------------- */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectViewUi(project: Projects, employees: List<Employee>, tasks: List<Tasks>, allEmployees: List<Employee>, onAddEmployee: (String, String) -> Unit,
                  onAddTask: (Tasks, String?) -> Unit,
                  onViewAllEmployees: (String) -> Unit, navcontroller: NavController) {

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

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                ,
            horizontalAlignment = Alignment.Start
        )
        {



            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(260.dp) // banner height
            )
            {
                // 1️⃣ Image
                AsyncImage(
                    model = project.photo_url,
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )

                // 2️⃣ Gradient fade (this creates the “banner → content” effect)
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(
                                    Color.Transparent,
                                    MaterialTheme.colorScheme.background
                                ),
                                startY = 120f // controls where fade begins
                            )
                        )
                )

                // 3️⃣ Overlayed title + address
                Column(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(16.dp)
                ) {
                    Text(
                        text = project.name ?: "Unnamed Project",
                        style = MaterialTheme.typography.titleLarge,
                        color = Color.White
                    )

                    Text(
                        text = project.address ?: "",
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp)
            ) {

                Text(
                    text = project.description ?: "",
                    modifier = Modifier.padding(top = 16.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurface
                )

                HorizontalDivider(modifier = Modifier.padding(vertical = 16.dp))

                /* ---------- EMPLOYEES HEADER (CLICKABLE) ---------- */
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { employeesExpanded = !employeesExpanded }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                )
                {
                    Text(
                        text = "Employees (${employees.size})",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.weight(1f)
                    )

                    TextButton(
                        onClick = {
                            project.id?.let {navcontroller.navigate("projectEmployeesScreen/$it")}
                        }
                    ) {
                        Text("View All", style = MaterialTheme.typography.labelSmall)
                    }

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

                )
                {
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
                    )
                    {

                        // 🔹 Status picker
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            tabs.forEachIndexed { index, title ->
                                FilterChip(
                                    selected = selectedTab == index,
                                    onClick = { selectedTab = index },
                                    modifier = Modifier.weight(1f),
                                    label = {
                                        Text(
                                            text = title,
                                            maxLines = 1,
                                            softWrap = false,
                                            overflow = TextOverflow.Ellipsis,
                                            textAlign = TextAlign.Center,
                                            modifier = Modifier.fillMaxWidth()
                                        )
                                    }
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
                                    modifier = Modifier.fillMaxWidth(), navController = navcontroller
                                )
                            }
                        }
                    }


                }

                Box(modifier = Modifier.fillMaxSize())
                {


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
                                            onAddEmployee(project.id!!, selectedEmployee!!.EID)
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
                            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
                        ){
                            TaskForm(
                                projectId = project.id!!,
                                allEmployees = allEmployees,
                                onDismiss = { showtaskform = false },
                                onSave = { task, employeeId ->
                                    onAddTask(task, employeeId)
                                    showtaskform = false
                                }
                            )
                        }
                    }




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
    viewModel: AuthViewModel,
    projectViewModel: ProjectViewModel,
    taskViewModel: TaskViewModel
) {
    LaunchedEffect(projectId) {
        println("🟡 ProjectViewContent projectId = $projectId")
        projectViewModel.fetchProjectById(projectId)
        projectViewModel.fetchProjectEmployees(projectId)
        projectViewModel.fetchProjectTasks(projectId)
        viewModel.fetchAllEmployees()

    }

    val project by projectViewModel.aproject.collectAsState()
    val employees by projectViewModel.projectemployees.collectAsState()
    val tasks by projectViewModel.projectasks.collectAsState()
    val allEmployees by viewModel.employees.collectAsState()




    if (project == null) {
        Text("Loading project…")
    } else {
        ProjectViewUi(
            project = project!!,
            employees = employees,
            tasks = tasks,
            allEmployees = allEmployees,
            navcontroller = navController,
            onViewAllEmployees = { id ->
                navController.navigate("projectEmployeesScreen/$id")
            },
            onAddEmployee = { projectId, employeeId ->
                projectViewModel.addEmployeeToProject(projectId, employeeId)
            },
            onAddTask = { task, employeeId ->
                taskViewModel.addTaskAndAssign(task, employeeId)
            }
        )
    }
}

/* ---------------------------------------------------
   PREVIEW (FAKE DATA ONLY)
--------------------------------------------------- */
@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun ProjectViewPreview() {
    DyadeSpaceTheme {
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
                    Avatar_url = null
                )
            ),
            tasks = listOf(
                Tasks(
                    id = "T1",
                    title = "Install drywall",
                    status = "in-progress",
                    deadline = "2023-11-15"
                )
            ),
            allEmployees = emptyList(),
            navcontroller = rememberNavController(),
            onViewAllEmployees = {},
            onAddEmployee = { _, _ -> },
            onAddTask = { _, _ -> }
        )
    }
}


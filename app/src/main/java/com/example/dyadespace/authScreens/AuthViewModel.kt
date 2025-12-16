package com.example.dyadespace.authScreens

//view model scopes to begin auths
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch //coroutines do work in the background
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.State
import android.net.Uri
import com.example.dyadespace.MyApp
import com.example.dyadespace.classes.EmployeeTask
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import kotlinx.serialization.Serializable



class AuthViewModel : ViewModel() {



    private val _authMessage = MutableStateFlow<String?>(null) //mutable state flow, a value that can change over time
    val authMessage = _authMessage //the underscore means only a viewmodel can change this variable(it's liek a toast)
    private val _currentEmployee = MutableStateFlow<Employee?>(null)
    val currentEmployee: StateFlow<Employee?> = _currentEmployee.asStateFlow() //value to pass to screens
     private val _employees = MutableStateFlow<List<Employee>>(emptyList())
    val employees: StateFlow<List<Employee>> = _employees.asStateFlow()
    private val _allTasks = MutableStateFlow<List<Tasks>>(emptyList())
    val allTasks = _allTasks.asStateFlow()

    private val _myTasks = MutableStateFlow<List<Tasks>>(emptyList())
    val myTasks = _myTasks.asStateFlow()


    private val _assignedTasks = MutableStateFlow<List<EmployeeTask>>(emptyList())
    val assignedTasks = _assignedTasks.asStateFlow()


    private val _projects = MutableStateFlow<List<Projects>>(emptyList())
    val projects: StateFlow<List<Projects>> = _projects.asStateFlow()

    val _aproject = MutableStateFlow<Projects?>(null)
    val aproject: StateFlow<Projects?> = _aproject.asStateFlow()

    val _projectemployees = MutableStateFlow<List<Employee>>(emptyList())
    val projectemployees: StateFlow<List<Employee>> = _projectemployees

    val _projectasks = MutableStateFlow<List<Tasks>>(emptyList())
    val projectasks: StateFlow<List<Tasks>> = _projectasks




    private val _isLoggedIn = mutableStateOf(false)
    val isLoggedIn: State<Boolean> = _isLoggedIn

//    init {
//        checkSession() // runs on app launch
//    }
//
//    fun checkSession() {
//        viewModelScope.launch {
//            try {
//                val session = SupabaseClient.client.auth.currentSessionOrNull()
//                _isLoggedIn.value = session != null
//            } catch (e: Exception) {
//                _isLoggedIn.value = false
//            }
//        }
//    }








    //sign up functions

    //Supabase operations (auth + database insert) happen over the network, and network calls take time — they’re not instant like adding two numbers. Kotlin protects the app from freezing by forcing long-running or waiting code to run asynchronously.
    //
    //So, suspend means:
    //
    //“This function might pause while waiting (like waiting for network response), but won't block the UI thread.”
    //
    //A phone app can't freeze while waiting for the internet, right?
    //If we didn't use suspend and called it directly inside Compose, the UI could lock up — no animations, no typing, looks like the app crashed.
    fun signUp( firstName: String,
                lastName: String,
                phone: String,
                role: String = "employee",
                email: String,
                password: String) {
        viewModelScope.launch { //starts a coroutine inside the viewmodel -
            // We use viewModelScope.launch because Supabase functions are suspend calls,
            // and running them in a coroutine keeps the UI thread free so the app stays smooth.
            try {
                //supabase sign up call
                val result = SupabaseClient.client.auth.signUpWith(Email){
                    this.email = email
                    this.password = password
                }

                val userId = result?.id.toString(); // grab the user id to use in database

                //insert into employees tables
                SupabaseClient.client.from("employees").insert(
                    mapOf(
                        "EID" to userId,
                        "Employee_fn" to firstName,
                        "Employee_ln" to lastName,
                        "Employee_phone" to phone,
                        "Employee_email" to email,
                        "role" to role,
                        "Avatar_url" to "" // optional placeholder
                    )
                )


                _authMessage.value = "Sign up successful"
            } catch (e: Exception) {
                _authMessage.value = e.message
            }

        }
    }

    fun logIn(email: String, password: String){
        viewModelScope.launch{
            try{
                SupabaseClient.client.auth.signInWith(Email){
                    this.email = email
                    this.password = password
                }
                _authMessage.value = "Sign in successful"


//                checkSession()
            } catch (e: Exception){
                _authMessage.value = e.message
            }

        }
    }

    fun setMessage(msg: String?) {
        _authMessage.value = msg
    }

    //update employee in database

    suspend fun uploadProfileImage(newUri: Uri, oldUrl: String?): String {
        // Convert local image -> ByteArray
        val bytes = withContext(Dispatchers.IO) {
            MyApp.appContext.contentResolver.openInputStream(newUri)?.readBytes()
                ?: throw Exception("Could not read file")
        }

        // Extract filename (unique)
        val fileName = "${System.currentTimeMillis()}.jpg"

        val bucket = SupabaseClient.client.storage.from("employee_profilepic")

        // 🗑 delete previous file if exists
        if (!oldUrl.isNullOrEmpty()) {
            val oldPath = oldUrl.substringAfter("employee_profilepic/") // extract storage path
            bucket.delete(oldPath)
        }

        // Upload replacement
        bucket.upload("avatars/$fileName", bytes)

        // Get new public URL
        return bucket.publicUrl("avatars/$fileName")
    }


    fun updateEmployee(employee: Employee?, newImageUri: Uri?) {
        viewModelScope.launch {
            try {
                val userId = SupabaseClient.client.auth.currentSessionOrNull()?.user?.id
                    ?: throw Exception("User not authenticated")

                var avatarUrl = employee?.Avatar_url

                // Only upload if user selected a new image
                if (newImageUri != null) {
                    avatarUrl = uploadProfileImage(newImageUri, oldUrl = avatarUrl)
                }

                SupabaseClient.client.postgrest["employees"].update(
                    mapOf(
                        "Employee_fn" to employee?.Employee_fn,
                        "Employee_ln" to employee?.Employee_ln,
                        "Employee_phone" to employee?.Employee_phone,
                        "Employee_email" to employee?.Employee_email,
                        "role" to employee?.role,
                        "Avatar_url" to avatarUrl
                    )
                ) {
                    filter { eq("EID", userId) }
                }

                _currentEmployee.value = employee?.copy(Avatar_url = avatarUrl)
                _authMessage.value = "Profile Updated"

            } catch (e: Exception) {
                _authMessage.value = e.message
            }
        }
    }




    fun fetchAllEmployees() {
        viewModelScope.launch {
            try{
                val employees = SupabaseClient.client.postgrest["employees"].select().decodeList<Employee>()
                _employees.value = employees


            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }


    // Fetch every task in the system (Manager view)
    fun fetchAllTasks() {
        viewModelScope.launch {
            try {
                val tasks = SupabaseClient.client.postgrest["tasks"]
                    .select()
                    .decodeList<Tasks>()

                _allTasks.value = tasks

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    // Fetch only tasks assigned to currently logged-in employee
    fun fetchMyTasks() {
        viewModelScope.launch {
            try {
                val userId = SupabaseClient.client.auth.currentSessionOrNull()?.user?.id
                    ?: throw Exception("User not authenticated")

                // 1️⃣ Get employee_task links
                val assigned = SupabaseClient.client.postgrest["employee_tasks"]
                    .select(columns = Columns.list("id", "EID")) {
                        filter { eq("EID", userId) }
                    }
                    .decodeList<EmployeeTask>()

                val taskIds = assigned.map { it.id }

                if (taskIds.isEmpty()) {
                    _myTasks.value = emptyList()
                    return@launch
                }

                // 2️⃣ Fetch tasks matching taskIds
                val tasks = SupabaseClient.client.postgrest["tasks"]
                    .select(
                        columns = Columns.list(
                            "id","title","description","deadline",
                            "status","created_at","project_id"
                        )
                    ) {
                        filter {
                            taskIds.forEach { id ->
                                or { eq("id", id) }
                            }
                        }  // <-- No import needed
                    }
                    .decodeList<Tasks>()

                _myTasks.value = tasks  // 🔥 Push to StateFlow

                println("Loaded tasks: $tasks")

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }





    fun fetchAllProjects(){
        viewModelScope.launch {
            try {
                val projects = SupabaseClient.client.postgrest["projects"].select().decodeList<Projects>()
                _projects.value = projects

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    //fetch employees for project
    fun fetchProjectEmployees(projectId: String) {
        viewModelScope.launch {
            try {
                val employees = SupabaseClient.client
                    .postgrest["projects_employees"]
                    .select(
                        columns = Columns.raw(
                            """
                        employees (
                            "EID",
                            "Employee_fn",
                            "Employee_ln",
                            "Employee_email",
                            "Employee_phone",
                            "role",
                            "Avatar_url"
                        )
                        """
                        )
                    ) {
                        filter {
                            eq("id", projectId)
                        }
                    }
                    .decodeList<ProjectEmployeeWithEmployee>()
                    .map { it.employees }

                _projectemployees.value = employees

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun fetchProjectTasks(projectId: String) {
        viewModelScope.launch {
            try {
                val tasks = SupabaseClient.client
                    .postgrest["project_tasks"]
                    .select(
                        columns = Columns.raw(
                            """
                        tasks!project_tasks_Id_fkey (
                            id,
                            title,
                            description,
                            deadline,
                            status,
                            created_at,
                            project_id
                        )
                        """
                        )
                    ) {
                        filter {
                            eq("id", projectId) // id = project_id
                        }
                    }
                    .decodeList<ProjectTaskWithTask>()
                    .map { it.tasks }

                _projectasks.value = tasks

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }


    @Serializable
    data class ProjectEmployeeWithEmployee(
        val employees: Employee
    )

    @Serializable
    data class ProjectTaskWithTask(
        val tasks: Tasks
    )


    //fetch project by id
    fun fetchProjectById(projectId: String){
        viewModelScope.launch {
            try {
                val project = SupabaseClient.client.postgrest["projects"]
                    .select{
                        filter {
                            eq("id", projectId)

                        }
                    }
                    .decodeSingle<Projects>()
                _aproject.value = project
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }



    //we need something to wait for the response because it is not immediate : onResult (a callback function)
    fun fetchRole(onResult:(Employee?) -> Unit){
        viewModelScope.launch {
            try {
                val userId = SupabaseClient.client.auth.currentSessionOrNull()?.user?.id
                    ?: return@launch onResult(null)


                val employee = SupabaseClient.client.postgrest["employees"]
                    .select(
                        columns = Columns.list(
                            "EID",
                            "Employee_fn",
                            "Employee_ln",
                            "Employee_phone",
                            "Employee_email",
                            "role",
                            "Avatar_url",
                            "created_at"
                        )
                    ){
                        filter{
                            eq("EID", userId)
                        }

                    }
                    .decodeSingle<Employee>()




                println("🟢 Employee row = $employee")
                println("🟢 Employee role = ${employee?.role}")
                _currentEmployee.value = employee //stored information to send
                println("🟢 _currentEmployee = ${_currentEmployee.value}")

                onResult(employee)

            } catch(e: Exception) {
                e.printStackTrace()
                onResult(null)
            }
        }
    }


    fun setFakeEmployee(emp: Employee) {
        _currentEmployee.value = emp
    }



    fun signOut() {
        viewModelScope.launch {
            try {
                SupabaseClient.client.auth.signOut()
                _authMessage.value = "Sign out successful"
                _currentEmployee.value = null
            } catch (e: Exception) {
                _authMessage.value = e.message

            }


        }
    }



}
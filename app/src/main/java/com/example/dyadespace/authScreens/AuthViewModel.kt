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
import io.github.jan.supabase.auth.status.SessionStatus
import com.example.dyadespace.classes.UserRole





class AuthViewModel: ViewModel() {

    @Serializable
    data class RoleResult(
        val role: String
    )


    val taskViewModel: TaskViewModel
        get() {
            TODO()
        }
    private val _authMessage = MutableStateFlow<String?>(null) //mutable state flow, a value that can change over time
    val authMessage = _authMessage //the underscore means only a viewmodel can change this variable(it's liek a toast)
    private val _currentEmployee = MutableStateFlow<Employee?>(null)
    val currentEmployee: StateFlow<Employee?> = _currentEmployee.asStateFlow() //value to pass to screens
     private val _employees = MutableStateFlow<List<Employee>>(emptyList())
    val employees: StateFlow<List<Employee>> = _employees.asStateFlow()

    private val _userRole = MutableStateFlow<UserRole?>(null)
    val userRole: StateFlow<UserRole?> = _userRole.asStateFlow()





    private val _isLoggedIn = MutableStateFlow<Boolean?>(null)
    val isLoggedIn: StateFlow<Boolean?> = _isLoggedIn.asStateFlow()

//    init {
//        checkSession() // runs on app launch
//    }
//
init {
    viewModelScope.launch {
//        SupabaseClient.client.auth.sessionStatus.collect { status ->
//            _isLoggedIn.value = when (status) {
//                is SessionStatus.Authenticated -> true
//                is SessionStatus.NotAuthenticated -> false
//                is SessionStatus.RefreshFailure -> false
//                is SessionStatus.Initializing -> null
//            }
//        }
        SupabaseClient.client.auth.sessionStatus.collect { status ->
            when (status) {
                is SessionStatus.Authenticated -> {
                    _isLoggedIn.value = true
                    fetchRole() // 🔑 load role ONCE
                }
                is SessionStatus.NotAuthenticated -> {
                    _isLoggedIn.value = false
                    _userRole.value = null
                }
                is SessionStatus.RefreshFailure -> {
                    _isLoggedIn.value = false
                    _userRole.value = null
                }
                is SessionStatus.Initializing -> {
                    _isLoggedIn.value = null
                    _userRole.value = null
                }
            }
        }

    }
}










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
                password: String)
    {
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

                SupabaseClient.client.auth.signOut()

                _authMessage.value = "Sign up successful"
            } catch (e: Exception) {
                _authMessage.value = e.message
            }

        }
    }

    fun logIn(email: String, password: String) {
        viewModelScope.launch {
            try {
                SupabaseClient.client.auth.signInWith(Email) {
                    this.email = email
                    this.password = password
                }


            } catch (e: Exception) {
                _authMessage.value = "Authentication failed"
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


    fun fetchCurrentEmployee() {
        viewModelScope.launch {
            try {
                val userId = SupabaseClient.client.auth.currentSessionOrNull()?.user?.id
                    ?: return@launch

                val employee = SupabaseClient.client
                    .postgrest["employees"]
                    .select {
                        filter { eq("EID", userId) }
                    }
                    .decodeSingle<Employee>()

                _currentEmployee.value = employee

            } catch (e: Exception) {
                e.printStackTrace()
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


    //assign task to employee
//    fun assignTask(taskId: String, employeeId: String){
//        if (taskId.isNullOrBlank() || employeeId.isNullOrBlank()) {
//            return // invalid assignment, do nothing
//        }
//
//        viewModelScope.launch {
//            try {
//                SupabaseClient.client.postgrest["employee_tasks"].insert(
//                    mapOf(
//                        "id" to taskId,
//                        "EID" to employeeId
//                    ))
//
//            } catch (e: Exception) {
//                e.printStackTrace()
//            }
//        }
//    }


    //add tasks
//    fun addTask(task: Tasks) {
//        viewModelScope.launch{
//
//            try {
//                val insertedTask = SupabaseClient.client.postgrest["tasks"].insert(task){
//                    select()
//                }.decodeSingle<Tasks>()
//
//                SupabaseClient.client.postgrest["project_tasks"]
//                    .insert(
//                        ProjectTaskInsert(
//                            project_id = insertedTask.project_id!!,
//                            task_id = insertedTask.id!!
//                        )
//                    )
//
////                TODO add to employee_tasks
//                fetchProjectTasks(insertedTask.project_id)
//
//            } catch (e: Exception) {
//                e.printStackTrace()
//            }
//        }
//    }








    //we need something to wait for the response because it is not immediate : onResult (a callback function)
    fun fetchRole() {
        viewModelScope.launch {
            try {
                val result = SupabaseClient.client
                    .postgrest
                    .rpc("get_my_role")
                    .decodeSingle<RoleResult>()

                println("AUTH DEBUG → raw role = ${result.role}")

                _userRole.value = when (result.role.lowercase()) {
                    "manager" -> UserRole.MANAGER
                    "employee" -> UserRole.EMPLOYEE
                    else -> null
                }

                println("AUTH DEBUG → mapped role = ${_userRole.value}")

            } catch (e: Exception) {
                println("ROLE FETCH ERROR → ${e.message}")
                // 🚫 DO NOT set EMPLOYEE here
                // leave role as null so navigation waits
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
                _isLoggedIn.value = false

            } catch (e: Exception) {
                _authMessage.value = e.message

            }


        }
    }



}
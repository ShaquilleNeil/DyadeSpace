package com.example.dyadespace.authScreens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.data.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ProjectViewModel: ViewModel() {


    private val _projects = MutableStateFlow<List<Projects>>(emptyList())
    val projects: StateFlow<List<Projects>> = _projects.asStateFlow()

    val _aproject = MutableStateFlow<Projects?>(null)
    val aproject: StateFlow<Projects?> = _aproject.asStateFlow()

    val _projectemployees = MutableStateFlow<List<Employee>>(emptyList())
    val projectemployees: StateFlow<List<Employee>> = _projectemployees

    val _projectasks = MutableStateFlow<List<Tasks>>(emptyList())
    val projectasks: StateFlow<List<Tasks>> = _projectasks


    fun setFakeProjects(fake: List<Projects>) {
        _projects.value = fake
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

    // add employees to project
    fun addEmployeeToProject(projectId: String?, employeeId: String){
        viewModelScope.launch {
            try {
                SupabaseClient.client.postgrest["projects_employees"].insert(
                    mapOf(
                        "id" to projectId,
                        "EID" to employeeId
                    )
                )

                fetchProjectEmployees(projectId!!)


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
                            eq("project_id", projectId) // id = project_id
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


}
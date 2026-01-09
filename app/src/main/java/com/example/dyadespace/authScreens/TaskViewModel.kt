package com.example.dyadespace.authScreens

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.example.dyadespace.classes.EmployeeTask
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.data.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class TaskViewModel(private val ProjectViewModel: ProjectViewModel) : ViewModel() {
    private val _allTasks = MutableStateFlow<List<Tasks>>(emptyList())
    val allTasks = _allTasks.asStateFlow()

    private val _myTasks = MutableStateFlow<List<Tasks>>(emptyList())
    val myTasks = _myTasks.asStateFlow()

    private val _taskbyid = MutableStateFlow<Tasks?>(null)
    val taskbyid: StateFlow<Tasks?> = _taskbyid


    private val _assignedTasks = MutableStateFlow<List<EmployeeTask>>(emptyList())
    val assignedTasks = _assignedTasks.asStateFlow()

    fun setFakeTasks(fake: List<Tasks>) {
        _allTasks.value = fake
    }


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

    fun fetchTaskById(taskId: String) {
        viewModelScope.launch {
            try{
                val tsk = SupabaseClient.client.postgrest["tasks"]
                    .select{
                        filter {
                            eq("id", taskId)
                        }
                    }
                    .decodeSingle<Tasks>()

                _taskbyid.value = tsk



            } catch (e: Exception) {
                e.printStackTrace()
            }

        }

    }


    fun addTaskAndAssign(task: Tasks, employeeId: String?) {
        viewModelScope.launch {
            try {
                // 1️⃣ Insert task and get generated ID
                val insertedTask = SupabaseClient.client
                    .postgrest["tasks"]
                    .insert(task) {
                        select()
                    }
                    .decodeSingle<Tasks>()

                val taskId = insertedTask.id ?: return@launch

                // 2️⃣ Assign employee if selected
                if (!employeeId.isNullOrBlank()) {
                    SupabaseClient.client.postgrest["employee_tasks"]
                        .insert(
                            mapOf(
                                "id" to taskId,
                                "EID" to employeeId
                            )
                        )
                }

                SupabaseClient.client.postgrest["project_tasks"]
                    .insert(
                        ProjectTaskInsert(
                            project_id = insertedTask.project_id!!,
                            task_id = insertedTask.id!!
                        )
                    )

                // 3️⃣ Refresh UI
                ProjectViewModel.fetchProjectTasks(insertedTask.project_id!!)

            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun updateTaskStatus(taskId: String, newStatus: String) {
        viewModelScope.launch{
            try {
                SupabaseClient.client.postgrest["tasks"].update(
                    mapOf("status" to newStatus)

                ){
                    filter { eq("id", taskId) }
                }
                fetchTaskById(taskId)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }


}
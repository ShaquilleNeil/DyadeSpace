package com.example.dyadespace.classes

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import com.example.dyadespace.authScreens.ProjectViewModel
import com.example.dyadespace.authScreens.TaskViewModel

class TaskViewModelFactory(
    private val projectViewModel: ProjectViewModel
) : ViewModelProvider.Factory {

    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(TaskViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return TaskViewModel(projectViewModel) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}

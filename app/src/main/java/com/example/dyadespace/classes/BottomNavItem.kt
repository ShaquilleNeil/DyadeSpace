package com.example.dyadespace.classes

import androidx.annotation.DrawableRes
import com.example.dyadespace.R

sealed class BottomNavItem(
    val route:String,
    var title:String,
    @DrawableRes val icon:Int
) { //A sealed class in Kotlin is like a smart enum on steroids — it allows you to define a restricted set of possible types/states, but each type can carry data.


   // object is used when that state has no data attached and we only need one instance of it.
    //we are creating the nav items here and also the destinations and order
    object Home: BottomNavItem("ManagerHome","Home", R.drawable.baseline_home_24)

    object Staff: BottomNavItem("ManagerStaff","Staff", R.drawable.baseline_group_people_24)


    object Tasks: BottomNavItem("ManagerTasks","My Tasks", R.drawable.baseline_task_24)

    object Profile: BottomNavItem("ManagerProfile","Profile", R.drawable.baseline_person_24)

    object EmployeeHome: BottomNavItem("EmployeeHome","Home", R.drawable.baseline_home_24)
    object EmployeeProfile: BottomNavItem("EmployeeProfile","Profile", R.drawable.baseline_person_24)

    companion object {
        val ManagerBottomNavItems = listOf(
            Home,
            Staff,
            Tasks,
            Profile
        )

        val EmployeeBottomNavItems = listOf(
            EmployeeHome,
            EmployeeProfile
        )
    }

}




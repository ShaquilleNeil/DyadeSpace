package com.example.dyadespace.viewitems

import android.content.res.Configuration
import android.view.RoundedCorner
import android.view.Surface
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.ExpandCircleDown
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CardDefaults.cardColors
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.example.dyadespace.classes.Tasks
import com.example.dyadespace.ui.theme.DyadeSpaceTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue

@Composable
fun TaskItem(tsk: Tasks,
             modifier: Modifier = Modifier,
             navController: NavController,
             showRemove: Boolean,
             onRemove: () -> Unit) {

var taskexpanded by remember { mutableStateOf(false) }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 2.dp, vertical = 2.dp),
        elevation = CardDefaults.cardElevation(6.dp),
        shape = RoundedCornerShape(15.dp),
        colors = cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
    ) {


        Row (
            modifier = Modifier
                .fillMaxWidth()
                .padding(15.dp)
                .clickable{taskexpanded = !taskexpanded},
            verticalAlignment = Alignment.CenterVertically
        )
        {
            Text(
                text = tsk.title ?: "",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface
            )
///////////////////////////////////////////////////////PROGRESS CHIP///////////////////////////////////////////////////////
            val statusText = when (tsk.status) {
                "todo" -> "To Do"
                "in-progress" -> "In Progress"
                "done" -> "Completed"
                else -> ""

            }


            Surface(
                modifier = Modifier
                    .padding(start = 10.dp),
                shape = RoundedCornerShape(15),
                if (tsk.status == "in-progress") Color.Yellow
                else if (tsk.status == "completed") Color.Green
                else Color.Blue,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)

            ) {
                Text(
                    text = statusText,
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.Black,
                    modifier = Modifier.padding(horizontal = 5.dp, vertical = 5.dp)
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            if(showRemove){

                    Text("Remove",
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.clickable {
                            onRemove()
                        },
                        style = MaterialTheme.typography.labelMedium

                    )
            }
//////////////////////////////////////////////////////////////////////DROPDOWN ICON////////////////////////////////////////
            Spacer(modifier = Modifier.weight(1f))
            Icon(
                imageVector = if (taskexpanded)
                    Icons.Default.ExpandLess
                else
                    Icons.Default.ExpandCircleDown,
                contentDescription = null
            )


        }

        AnimatedVisibility(visible = taskexpanded,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically()) {

                Column(
                    modifier = Modifier
                        .padding(top = 4.dp, start = 15.dp, bottom = 15.dp)
                        .fillMaxWidth()
                )
                {


                    Text(
                        text = "Due: ${tsk.deadline ?: ""}",
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(top = 8.dp)
                    )

                    Button(
                        onClick = {
                            tsk.id?.let {id ->
                                navController.navigate("taskView/$id")
                            }
                        },
                        shape = RoundedCornerShape(20),
                        modifier = Modifier.align(Alignment.Start).padding(top = 10.dp).height(35.dp)

                    ){
                        Text("View Details ")
                        Icon(
                            imageVector = Icons.Default.ArrowForward,
                            contentDescription = "Person Icon",
                            modifier = Modifier.size(20.dp),
                            tint = Color.White
                        )

                    }
                }


        }



    }
}


@Preview(showBackground = true, name = "Light", uiMode = Configuration.UI_MODE_NIGHT_NO)
@Preview(
    showBackground = true,
    name = "Dark",
    uiMode = Configuration.UI_MODE_NIGHT_YES
)
@Composable
fun TaskItemPreview() {

    DyadeSpaceTheme() {
        Surface(
            color = MaterialTheme.colorScheme.background
        ) {
            TaskItem(
                Tasks(
                    id = "1",
                    title = "Mix Concrete",
                    description = "Prepare concrete mix for walkway slab",
                    status = "in-progress",
                    deadline = "2025-01-13",
                    created_at = null,
                    project_id = null
                ),
                modifier = Modifier,
                navController = NavController(LocalContext.current),
                showRemove = true,
                onRemove = {}
            )
        }
    }


}

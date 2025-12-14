package com.example.dyadespace.viewitems

import android.view.RoundedCorner
import android.view.Surface
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CardDefaults.cardColors
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.example.dyadespace.classes.Tasks

@Composable
fun TaskItem(tsk: Tasks) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(140.dp)
            .padding(horizontal = 2.dp, vertical = 2.dp),
        elevation = CardDefaults.cardElevation(6.dp),
        shape = RoundedCornerShape(15.dp),
        colors = cardColors(containerColor = Color.White),
        border = BorderStroke(1.dp, Color.Black)
    ) {
        Box(modifier = Modifier.fillMaxWidth()) {

            Column(
                modifier = Modifier
                    .padding(16.dp)
                    .fillMaxWidth()
            ) {

                Text(
                    text = tsk.title ?: "",
                    style = MaterialTheme.typography.titleMedium
                )

//                Text(
//                    text = tsk.description ?: "",
//                    style = MaterialTheme.typography.bodyMedium,
//                    modifier = Modifier.padding(top = 6.dp)
//                )

                Text(
                    text = "Due: ${tsk.deadline ?: ""}",
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(top = 8.dp)
                )

                Button(
                    onClick = { /* TODO: Navigate */ },
                    shape = RoundedCornerShape(20),
                    modifier = Modifier.align(Alignment.Start).padding(top = 10.dp).height(35.dp)

                ){
                    Text("View Details →")

                }
            }

            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp),
                shape = RoundedCornerShape(50),
                if (tsk.status == "in-progress") Color.Green
                else if (tsk.status == "completed") Color.Blue
                else Color.Red

            ) {
                Text(
                    text = tsk.status ?: "",
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }
        }
    }
}


@Preview(showBackground = true)
@Composable
fun TaskItemPreview() {
    TaskItem(
        Tasks(
            id = "1",
            title = "Mix Concrete",
            description = "Prepare concrete mix for walkway slab",
            status = "in-progress",
            deadline = "2025-01-13",
            created_at = null,
            project_id = null
        )
    )
}

package com.example.dyadespace.viewitems

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Employee
import com.example.dyadespace.manager.ManagerTasks
import com.example.dyadespace.ui.preview.previewData
import com.example.dyadespace.ui.theme.DyadeSpaceTheme



@Composable
fun EmployeeCard(emp: Employee, taskCount: Int) {

    Card(
        modifier = Modifier
            .width(170.dp)
            .height(230.dp),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(
            containerColor = Color(0xFF2B2B2B)
        )
    ) {

        Box(modifier = Modifier.fillMaxSize()) {

            // 🔵 Floating + button
            FilledIconButton(
                onClick = {},
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .size(36.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = Color.Blue,
                    contentColor = Color.White
                ),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.Add, contentDescription = null)
            }

            // 🟣 Main content
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {

                // Avatar + status dot
                Box {

                    AsyncImage(
                        model = emp.Avatar_url,
                        contentDescription = null,
                        modifier = Modifier
                            .size(72.dp)
                            .clip(CircleShape),
                        contentScale = ContentScale.Crop
                    )

                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .size(14.dp)
                            .background(Color.Green, CircleShape)
                            .border(2.dp, Color.Black, CircleShape)
                    )
                }

                Spacer(Modifier.height(12.dp))

                Text(
                    emp.Employee_fn,
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    color = Color.White
                )

                Text(
                    emp.role ?: "Unknown",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Gray,
                    maxLines = 1
                )

                Spacer(Modifier.height(8.dp))

                // Status chip
                Box(
                    modifier = Modifier
                        .background(Color(0xFF0F5132), RoundedCornerShape(20.dp))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(
                        "AVAILABLE",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFF4ADE80)
                    )
                }

                Spacer(Modifier.height(6.dp))

                Text(
                    "${taskCount} tasks active",
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.LightGray
                )
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
fun EmployeeCardsPreview() {
    DyadeSpaceTheme() {
        Surface() {
            EmployeeCard(
                Employee(
                    EID = "123",
                    Employee_fn = "Shaq",
                    Employee_ln = "Neil",
                    Employee_phone = "123-4567",
                    Employee_email = "john.quincy.adams@examplepetstore.com",
                    role = "Manager",
                    Avatar_url = "https://picsum.photos/200",

                    ),
                taskCount = 12
            )
        }
    }

}

package com.example.dyadespace.viewitems


import android.view.RoundedCorner
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import androidx.navigation.compose.rememberNavController
import androidx.test.espresso.base.Default
import coil.compose.AsyncImage
import com.example.dyadespace.classes.Projects
import com.example.dyadespace.classes.Tasks

@Composable
fun ProjectItem(p: Projects, navController: NavController) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(350.dp)
            .padding(horizontal = 16.dp, vertical = 16.dp),
        shape = RoundedCornerShape(25.dp),
        elevation = CardDefaults.cardElevation(8.dp)
    ) {
        Box(modifier = Modifier.fillMaxSize()) {

            // Background image
            AsyncImage(
                model = p.photo_url?.let { "$it?type=image/jpeg" } ?: "",
                contentDescription = "Project Image",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )

            // Gradient overlay
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                Color.Black.copy(alpha = 0.7f)
                            )
                        )
                    )
            )

            // Optional status chip (top-left)
            Surface(
                modifier = Modifier
                    .padding(16.dp)
                    .align(Alignment.TopStart),
                shape = RoundedCornerShape(50),
                color = Color(0xFF34D399)
            ) {
                Text(
                    text = "IN PROGRESS",
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.Black
                )
            }

            // Bottom content
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(16.dp)
            ) {

                Text(
                    text = p.name ?: "Unnamed Project",
                    style = MaterialTheme.typography.titleLarge,
                    color = Color.White
                )

                Text(
                    text = p.description ?: "",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.85f),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 6.dp)
                )

                Spacer(modifier = Modifier.height(10.dp))

                Text(
                    text = p.address ?: "N/A",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color(0xFF34D399)
                )

                Spacer(modifier = Modifier.height(14.dp))

                Button(
                    onClick = {
                        p.id?.let { id ->
                            navController.navigate("projectView/$id")
                        }

                    },
                    shape = RoundedCornerShape(50),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White.copy(alpha = 0.15f)
                    )
                ) {
                    Text("View Details →", color = Color.White)
                }
            }
        }
    }
}





@Preview(showBackground = true)
@Composable
fun ProjectItemPreview() {
    val navController = rememberNavController()

    ProjectItem(
        p = Projects(
            id = "P123",
            name = "Office Renovation",
            description = "Renovating the office 3rd floor — electricians and drywall phase this week.",
            address = "Montreal QC",
            photo_url = "https://gpzpemmuoybkihvlfqxv.supabase.co/storage/v1/object/public/project_photos/images/1765305622455_asd.jpg"
        ),
        navController = navController
    )
}
